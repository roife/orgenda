import CryptoKit
import Foundation

extension WorkspaceStore {
    nonisolated static var localWorkspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    var storageDescription: String {
        isFolderConnected ? String(localized: "Changes save to the connected folder.") : String(localized: "Connect a folder to save changes.")
    }

    func startWorkspace(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        localWorkspaceURL: URL? = nil
    ) async {
        guard !hasStarted, !Task.isCancelled else { return }
        hasStarted = true
        isStartingWorkspace = true
        let isUITestWorkspace = Self.isUITestWorkspace(arguments: arguments)
        defer {
            if Task.isCancelled {
                hasStarted = false
            } else {
                isStartingWorkspace = false
                // A failed startup can be retried after the folder becomes available.
                hasStarted = isFolderConnected || isUITestWorkspace
            }
        }
        if isUITestWorkspace {
            #if DEBUG
            if arguments.contains("--image-preview-fixture") {
                do { try await configureImagePreviewFixture() }
                catch { fileSyncError = error.localizedDescription }
                return
            }
            #endif
            if arguments.contains("--file-browser-fixture") {
                items = []
                journalEntries = []
                documents = [
                    WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "* TODO File gesture probe\n", kind: .org),
                    WorkspaceDocument(path: "projects", title: "Projects", contents: "", kind: .folder),
                    WorkspaceDocument(path: "projects/child", title: "Child", contents: "", kind: .folder),
                    WorkspaceDocument(path: "projects/child/notes.org", title: "Notes", contents: "* Nested content 中文\n", kind: .org),
                    WorkspaceDocument(path: "destination", title: "Destination", contents: "", kind: .folder)
                ]
            }
            scheduleWorkspaceParse()
            await waitForWorkspaceIndex()
            return
        }
        let localWorkspaceURL = localWorkspaceURL ?? Self.localWorkspaceURL
        if let bookmark = defaults.data(forKey: "workspaceFolderBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI,
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                await connectFolder(url, defaults: defaults)
            } catch {
                fileSyncError = String(localized: "The saved folder is unavailable. Choose it again in Workspace & Sync.")
            }
        } else {
            do {
                // Creating an existing directory is harmless and never seeds or
                // replaces its contents. Keep filesystem work off the UI actor.
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: localWorkspaceURL, withIntermediateDirectories: true)
                }.value
                try Task.checkCancellation()
                await connectFolder(localWorkspaceURL, remember: false)
            } catch {
                if !(error is CancellationError) {
                    fileSyncError = String(localized: "Could not create the local workspace: \(error.localizedDescription)")
                }
            }
        }
        await waitForWorkspaceIndex()
    }

    func connectFolder(_ url: URL, remember: Bool = true, defaults: UserDefaults = .standard) async {
        guard await waitForFileOperation() else { return }
        if !dirtyFilePaths.isEmpty {
            await synchronizeFiles()
            guard dirtyFilePaths.isEmpty else {
                fileSyncError = String(localized: "Save or resolve the pending changes before switching folders.")
                return
            }
        }
        let previousDocuments = documents
        isSynchronizing = true
        defer { isSynchronizing = false }
        let hasAccess = url.startAccessingSecurityScopedResource()
        let candidate = WorkspaceFileStore(rootURL: url)
        do {
            let loaded = try await candidate.load()
            try Task.checkCancellation()
            // A provider can take time to download its folder. Edits to the old
            // workspace during that await must remain attached to the old store.
            guard documents == previousDocuments, dirtyFilePaths.isEmpty else {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
                fileSyncError = String(localized: "The current workspace changed while opening the folder. Save those changes, then choose the folder again.")
                return
            }
            if remember {
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(bookmark, forKey: "workspaceFolderBookmark")
            }
            folderAccessURL?.stopAccessingSecurityScopedResource()
            folderAccessURL = hasAccess ? url : nil
            fileStore = candidate
            workspaceFileSessionID = UUID()
            fileUndo = nil
            recentlyDeleted = []
            demoDeletedFiles = [:]
            fileSaveErrors.removeAll()
            isFolderConnected = true
            usesEmacsConfiguration = true
            workspaceName = url.lastPathComponent == "Workspace" ? String(localized: "Org Workspace") : url.lastPathComponent
            let cloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            workspaceLocation = cloud ? String(localized: "iCloud Drive folder") : String(localized: "Connected folder")
            if url.standardizedFileURL == Self.localWorkspaceURL.standardizedFileURL {
                workspaceLocation = String(localized: "On My iPhone · Workspace")
            }
            persistedContents = Dictionary(uniqueKeysWithValues: loaded.filter { $0.kind != .folder }.map { ($0.path, $0.contents) })
            fileSaveTask?.cancel()
            fileSaveTask = nil
            resetWorkspaceIndex()
            items.removeAll()
            documents.removeAll()
            journalEntries.removeAll()
            acceptDiskDocuments(loaded)
            fileSyncError = nil
            lastFileSync = .now
            await waitForWorkspaceIndex()
        } catch {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            if !(error is CancellationError) {
                fileSyncError = String(localized: "Could not open the folder: \(error.localizedDescription)")
            }
        }
    }

    func queueFileSave(paths: Set<String>) {
        guard isFolderConnected else { return }
        for path in paths {
            if let document = documents.first(where: { $0.path == path }),
               document.kind != .folder, document.contents != persistedContents[path] {
                dirtyFilePaths.insert(path)
            }
        }
        pendingFileCount = dirtyFilePaths.count
        guard !dirtyFilePaths.isEmpty else { return }
        fileSaveTask?.cancel()
        fileSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.synchronizeFiles()
        }
    }

    /// The same path handles automatic saves, foreground refresh and manual refresh.
    /// Compare-before-write prevents a stale editor from replacing external changes.
    func synchronizeFiles() async {
        guard await waitForFileOperation(), let fileStore else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        var failures: [String] = []
        for path in dirtyFilePaths.sorted() {
            guard let contents = documents.first(where: { $0.path == path })?.contents else { continue }
            do {
                try await fileStore.write(path: path, contents: contents, expectedContents: persistedContents[path])
                fileSaveErrors.removeValue(forKey: path)
                persistedContents[path] = contents
                if documents.first(where: { $0.path == path })?.contents == contents {
                    dirtyFilePaths.remove(path)
                }
            } catch {
                fileSaveErrors[path] = error.localizedDescription
                failures.append("\(path): \(error.localizedDescription)")
                // Keep a recoverable copy outside the connected folder. It is never
                // synchronized over the user's conflicting source file.
                do {
                    try await Self.preserveUnsaved(contents, path: path, workspaceIdentity: fileStore.recoveryIdentity)
                }
                catch { failures.append(String(localized: "Recovery copy failed: \(error.localizedDescription)")) }
            }
        }
        pendingFileCount = dirtyFilePaths.count
        do {
            let loaded = try await fileStore.load()
            for document in loaded where document.kind != .folder && !dirtyFilePaths.contains(document.path) {
                persistedContents[document.path] = document.contents
            }
            let paths = Set(loaded.map(\.path)).union(dirtyFilePaths)
            persistedContents = persistedContents.filter { paths.contains($0.key) }
            acceptDiskDocuments(loaded)
            lastFileSync = .now
        } catch {
            failures.append(String(localized: "Could not refresh files: \(error.localizedDescription)"))
        }
        fileSyncError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    /// Explicit conflict resolution: archive pending edits before adopting the
    /// folder's current content. It never writes into the connected folder.
    @discardableResult
    func adoptFolderVersions() async -> Bool {
        guard await waitForFileOperation(), let fileStore else { return false }
        let snapshot = documents
        let pending = dirtyFilePaths
        isSynchronizing = true
        defer { isSynchronizing = false }
        do {
            for document in snapshot where pending.contains(document.path) {
                try await Self.preserveUnsaved(document.contents, path: document.path,
                                               workspaceIdentity: fileStore.recoveryIdentity)
            }
            let loaded = try await fileStore.load()
            try Task.checkCancellation()
            guard documents == snapshot, dirtyFilePaths == pending else {
                fileSyncError = String(localized: "Files changed while preparing the reload. Your latest edits are still pending; finish editing and try again.")
                return false
            }
            fileSaveTask?.cancel()
            fileSaveTask = nil
            dirtyFilePaths.removeAll()
            fileSaveErrors.removeAll()
            pendingFileCount = 0
            persistedContents = Dictionary(uniqueKeysWithValues: loaded.filter { $0.kind != .folder }.map { ($0.path, $0.contents) })
            acceptDiskDocuments(loaded)
            fileSyncError = nil
            lastFileSync = .now
            await waitForWorkspaceIndex()
            return true
        } catch {
            if !(error is CancellationError) {
                fileSyncError = String(localized: "Could not reload the folder. Your edits are still pending: \(error.localizedDescription)")
            }
            return false
        }
    }

    static func unsavedEditsFolder(for workspaceIdentity: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unsaved Edits", isDirectory: true)
            .appendingPathComponent(recoveryDigest(workspaceIdentity), isDirectory: true)
    }

    private func waitForFileOperation() async -> Bool {
        while isSynchronizing {
            do { try await Task.sleep(for: .milliseconds(25)) }
            catch { return false }
        }
        return !Task.isCancelled
    }

    private static func recoveryDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func preserveUnsaved(_ contents: String, path: String, workspaceIdentity: String) async throws {
        let recovery = unsavedEditsFolder(for: workspaceIdentity)
        // Content addressing keeps every distinct draft, without duplicating an
        // unchanged conflict on each refresh or colliding across workspaces.
        let name = recoveryDigest(path) + "-" + recoveryDigest(contents)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: recovery.appendingPathComponent(name + ".txt"), options: .atomic)
            let metadata = ["workspace": workspaceIdentity, "path": path]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: recovery.appendingPathComponent(name + ".json"), options: .atomic)
        }.value
    }
}
