import Foundation

extension WorkspaceStore {
    static let storageConnectionKey = "storageConnection.v1"

    func restoreConfiguredStorage(defaults: UserDefaults, localURL: URL) async {
        connectionDefaults = defaults
        if let data = defaults.data(forKey: Self.storageConnectionKey) {
            do {
                let connection = try JSONDecoder().decode(StorageConnection.self, from: data)
                if connection.provider.isRemote {
                    let backend: any RemoteWorkspaceBackend
                    do { backend = try await CloudConnectionFactory.restore(connection) }
                    catch { backend = UnavailableStorageBackend(reason: (error as? StorageError) ?? .configuration(error.localizedDescription)) }
                    let session = try WorkspaceSession(connection: connection, cacheDirectory: storageCacheDirectory, remote: backend)
                    try await restoreSession(session, connection: connection, folderURL: nil)
                } else {
                    var stale = false
                    let url: URL
                    do {
                        if let bookmark = connection.bookmark {
                            url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI,
                                          relativeTo: nil, bookmarkDataIsStale: &stale)
                        } else {
                            url = URL(fileURLWithPath: connection.rootID, isDirectory: true)
                        }
                    } catch {
                        // A revoked bookmark cannot prevent reading the last
                        // complete snapshot. This backend never accesses the URL.
                        let unavailable = UnavailableStorageBackend(reason: .configuration(error.localizedDescription))
                        let session = try WorkspaceSession(connection: connection, cacheDirectory: storageCacheDirectory, remote: unavailable)
                        try await restoreSession(session, connection: connection, folderURL: nil)
                        return
                    }
                    let access = url.startAccessingSecurityScopedResource()
                    do {
                        let folder = WorkspaceFileStore(rootURL: url)
                        var restored = connection
                        if stale {
                            restored.bookmark = try url.bookmarkData(options: .minimalBookmark,
                                includingResourceValuesForKeys: nil, relativeTo: nil)
                        }
                        let session = try WorkspaceSession(connection: restored, cacheDirectory: storageCacheDirectory, folder: folder)
                        try await restoreSession(session, connection: restored, folderURL: access ? url : nil)
                        if stale { defaults.set(try JSONEncoder().encode(restored), forKey: Self.storageConnectionKey) }
                    } catch {
                        if access { url.stopAccessingSecurityScopedResource() }
                        throw error
                    }
                }
            } catch { reportStorageError(error) }
            return
        }
        if let bookmark = defaults.data(forKey: "workspaceFolderBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI,
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                await connectFolder(url, defaults: defaults)
            } catch {
                reportStorageError(StorageError.configuration(String(localized: "The saved folder is unavailable. Choose it again in Workspace & Sync.")))
            }
        } else {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
                }.value
                try Task.checkCancellation()
                await connectFolder(localURL, remember: false, defaults: defaults)
            } catch { if !(error is CancellationError) { reportStorageError(error) } }
        }
    }

    private func restoreSession(_ session: WorkspaceSession, connection: StorageConnection, folderURL: URL?) async throws {
        if let cached = try? await session.snapshot() {
            try Task.checkCancellation()
            activateSession(session, connection: connection, snapshot: cached, folderURL: folderURL)
            // Offline startup is ready immediately. The scene's foreground
            // sync task validates the provider without blocking initial UI.
        } else {
            try await session.initialize()
            try Task.checkCancellation()
            let snapshot = try await session.snapshot()
            activateSession(session, connection: connection, snapshot: snapshot, folderURL: folderURL)
        }
    }

    func connectFolder(_ url: URL, remember: Bool = true, defaults: UserDefaults = .standard,
                       preservePending: Bool = false) async {
        guard !isChangingStorage, !isSavingConfiguration, await waitForFileOperation() else { return }
        isChangingStorage = true
        defer { isChangingStorage = false }
        let access = url.startAccessingSecurityScopedResource()
        do {
            let root = url.resolvingSymlinksInPath().standardizedFileURL.path
            if var connection = storageConnection, connection.rootID == root, !connection.provider.isRemote,
               let workspaceSession {
                await persistFileEdits()
                try await workspaceSession.replaceFolderBackend(WorkspaceFileStore(rootURL: url))
                if remember {
                    connection.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    defaults.set(try JSONEncoder().encode(connection), forKey: Self.storageConnectionKey)
                    defaults.set(connection.bookmark, forKey: "workspaceFolderBookmark")
                }
                folderAccessURL?.stopAccessingSecurityScopedResource()
                folderAccessURL = access ? url : nil
                storageConnection = connection
                await synchronizeFiles()
                return
            }
            let cloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            let digest = Self.recoveryDigest(root)
            let hex = Array(digest.prefix(32))
            let uuidString = String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16])
                + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
            var connection = StorageConnection(id: UUID(uuidString: uuidString)!, provider: cloud ? .iCloud : .local,
                displayName: url.lastPathComponent == "Workspace" ? String(localized: "Org Workspace") : url.lastPathComponent,
                rootID: root)
            if remember {
                connection.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            let session = try WorkspaceSession(connection: connection, cacheDirectory: storageCacheDirectory,
                                               folder: WorkspaceFileStore(rootURL: url))
            try await session.initialize()
            let snapshot = try await session.snapshot()
            let replacement = try await prepareStorageReplacement(preservePending: preservePending)
            try Task.checkCancellation()
            try validateStorageReplacement(replacement)
            let previous = storageConnection
            if remember {
                defaults.set(try JSONEncoder().encode(connection), forKey: Self.storageConnectionKey)
                defaults.set(connection.bookmark, forKey: "workspaceFolderBookmark")
            }
            connectionDefaults = defaults
            activateSession(session, connection: connection, snapshot: snapshot, folderURL: access ? url : nil)
            if let retiredSession = replacement.retiredSession {
                do { try await retiredSession.retireAfterArchiving() }
                catch { reportStorageError(error) }
            }
            if let previous, previous.id != connection.id, previous.provider.isRemote {
                try? CloudConnectionFactory.removeCredentials(for: previous)
            }
            await waitForWorkspaceIndex()
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            if !(error is CancellationError) { reportStorageError(error) }
        }
    }

    func connectWebDAV(_ configuration: WebDAVConfiguration, preservePending: Bool = false) async -> Bool {
        await connectRemote(preservePending: preservePending) {
            try await CloudConnectionFactory.prepareWebDAV(configuration: configuration)
        }
    }

    func connectCloud(_ provider: StorageProvider, preservePending: Bool = false) async -> Bool {
        await connectRemote(preservePending: preservePending) {
            try await CloudConnectionFactory.prepareCloud(provider: provider)
        }
    }

    /// Renew access to the same account and root without rebinding its outbox.
    func reconnectStorage(webDAVPassword: String? = nil) async -> Bool {
        guard !isChangingStorage, !isSavingConfiguration, let original = storageConnection, original.provider.isRemote,
              let workspaceSession else { return false }
        isChangingStorage = true
        defer { isChangingStorage = false }
        let identity = workspaceFileSessionID
        var candidate: PreparedRemoteConnection?
        do {
            let refreshed = try await CloudConnectionFactory.reauthenticate(original, webDAVPassword: webDAVPassword)
            candidate = refreshed
            guard identity == workspaceFileSessionID, refreshed.connection.identity == original.identity,
                  await waitForFileOperation() else { throw StorageError.rootUnavailable }
            await persistFileEdits()
            guard identity == workspaceFileSessionID else { throw StorageError.rootUnavailable }
            try await workspaceSession.replaceRemoteBackend(refreshed.backend)
            connectionDefaults.set(try JSONEncoder().encode(refreshed.connection), forKey: Self.storageConnectionKey)
            storageConnection = refreshed.connection
            if original.credentialKey != refreshed.connection.credentialKey {
                try? CloudConnectionFactory.removeCredentials(for: original)
            }
            fileSyncError = nil
            await synchronizeFiles()
            return true
        } catch {
            if let candidate, candidate.connection.credentialKey != storageConnection?.credentialKey {
                try? CloudConnectionFactory.removeCredentials(for: candidate.connection)
            }
            if !(error is CancellationError) { reportStorageError(error) }
            return false
        }
    }

    private func connectRemote(preservePending: Bool,
                               prepare: () async throws -> PreparedRemoteConnection) async -> Bool {
        guard !isChangingStorage, !isSavingConfiguration, await waitForFileOperation() else { return false }
        isChangingStorage = true
        defer { isChangingStorage = false }
        var prepared: PreparedRemoteConnection?
        do {
            let candidate = try await prepare()
            prepared = candidate
            let session = try WorkspaceSession(connection: candidate.connection, cacheDirectory: storageCacheDirectory,
                                               remote: candidate.backend)
            try await session.initialize()
            let snapshot = try await session.snapshot()
            let replacement = try await prepareStorageReplacement(preservePending: preservePending)
            try Task.checkCancellation()
            try validateStorageReplacement(replacement)
            let previous = storageConnection
            connectionDefaults.set(try JSONEncoder().encode(candidate.connection), forKey: Self.storageConnectionKey)
            connectionDefaults.removeObject(forKey: "workspaceFolderBookmark")
            activateSession(session, connection: candidate.connection, snapshot: snapshot, folderURL: nil)
            if let retiredSession = replacement.retiredSession {
                do { try await retiredSession.retireAfterArchiving() }
                catch { reportStorageError(error) }
            }
            if let previous, previous.credentialKey != candidate.connection.credentialKey {
                try? CloudConnectionFactory.removeCredentials(for: previous)
            }
            await waitForWorkspaceIndex()
            return true
        } catch {
            if let prepared, prepared.connection.credentialKey != storageConnection?.credentialKey {
                try? CloudConnectionFactory.removeCredentials(for: prepared.connection)
            }
            if !(error is CancellationError) { reportStorageError(error) }
            return false
        }
    }

    func disconnectStorage(preservePending: Bool = false) async -> Bool {
        let previous = storageConnection
        let local = Self.localWorkspaceURL
        do { try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true) }
        catch { reportStorageError(error); return false }
        await connectFolder(local, remember: false, defaults: connectionDefaults, preservePending: preservePending)
        guard storageConnection?.rootID == local.resolvingSymlinksInPath().standardizedFileURL.path,
              storageConnection?.provider == .local else { return false }
        connectionDefaults.removeObject(forKey: Self.storageConnectionKey)
        connectionDefaults.removeObject(forKey: "workspaceFolderBookmark")
        if let previous { try? CloudConnectionFactory.removeCredentials(for: previous) }
        return true
    }

    private func prepareStorageReplacement(preservePending: Bool) async throws -> StorageReplacement {
        guard await waitForFileOperation() else { throw CancellationError() }
        isSynchronizing = true
        defer { isSynchronizing = false }
        await persistFileEdits()
        guard dirtyFilePaths.isEmpty else { throw StorageError.configuration(String(localized: "Save changes on this device before replacing this connection.")) }
        guard hasPendingStorageChanges else {
            return StorageReplacement(retiredSession: nil, generation: storageContentGeneration, sessionID: workspaceFileSessionID)
        }
        if !preservePending {
            isSynchronizing = false
            await synchronizeFiles()
            isSynchronizing = true
            guard !hasPendingStorageChanges else {
                throw StorageError.configuration(String(localized: "Sync pending edits first, or keep a local copy before changing storage."))
            }
        } else if let workspaceSession {
            let originalDocuments = documents
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Unsaved Edits", isDirectory: true)
                .appendingPathComponent("\(Int(Date.now.timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
            try await workspaceSession.archiveUnsynced(to: root)
            guard dirtyFilePaths.isEmpty, documents == originalDocuments else {
                throw StorageError.configuration(String(localized: "The workspace changed while keeping a copy. Finish editing and try again."))
            }
            return StorageReplacement(retiredSession: workspaceSession, generation: storageContentGeneration, sessionID: workspaceFileSessionID)
        }
        return StorageReplacement(retiredSession: nil, generation: storageContentGeneration, sessionID: workspaceFileSessionID)
    }

    private func validateStorageReplacement(_ replacement: StorageReplacement) throws {
        guard replacement.generation == storageContentGeneration,
              replacement.sessionID == workspaceFileSessionID, dirtyFilePaths.isEmpty else {
            throw StorageError.configuration(String(localized: "The workspace changed while keeping a copy. Finish editing and try again."))
        }
    }

    private func activateSession(_ session: WorkspaceSession, connection: StorageConnection,
                                 snapshot: WorkspaceSessionSnapshot, folderURL: URL?) {
        folderAccessURL?.stopAccessingSecurityScopedResource()
        folderAccessURL = folderURL
        fileSaveTask?.cancel()
        fileSaveTask = nil
        workspaceFileSessionID = UUID()
        fileStore = session
        workspaceSession = session
        appliedStorageRevision = 0
        storageConnection = connection
        isFolderConnected = true
        usesEmacsConfiguration = false
        hasWorkspaceConfiguration = true
        configuration = .standard
        configurationDocument = ConfigurationDocument(configuration: .standard)
        configurationSource = nil
        configurationError = nil
        configurationRevision &+= 1
        workspaceName = connection.displayName
        workspaceLocation = connection.provider.isRemote ? connection.provider.title :
            (connection.provider == .iCloud ? String(localized: "iCloud Drive folder") : String(localized: "Connected folder"))
        fileUndo = nil
        recentlyDeleted = []
        demoDeletedFiles = [:]
        fileSaveErrors = [:]
        fileSyncError = nil
        automaticSyncRetryAt = nil
        serverSyncRetryAt = nil
        syncFailureCount = 0
        dirtyFilePaths = []
        externalDocumentRevisions = [:]
        resetWorkspaceIndex()
        documents = []
        items = []
        journalEntries = []
        applyStorageSnapshot(snapshot)
        scheduleWorkspaceParse()
    }

    func applyStorageSnapshot(_ snapshot: WorkspaceSessionSnapshot) {
        guard snapshot.revision >= appliedStorageRevision else { return }
        appliedStorageRevision = snapshot.revision
        pendingUploadPaths = snapshot.pendingPaths
        hasPendingStorageOperation = snapshot.hasPendingOperation
        syncConflicts = snapshot.conflicts
        lastFileSync = snapshot.lastSync
        // This baseline describes the local durable copy, not cloud contents.
        let previousBaseline = persistedContents
        persistedContents = Dictionary(uniqueKeysWithValues: snapshot.documents.filter { $0.kind != .folder }.map { ($0.path, $0.contents) })
        // An editor's uncommitted bytes still belong to the baseline it saw.
        // Advancing that baseline would authorize overwriting an unseen update
        // on the next save retry. Session.write records this race as a conflict.
        for path in dirtyFilePaths { persistedContents[path] = previousBaseline[path] }
        pendingFileCount = dirtyFilePaths.union(pendingUploadPaths).count
        let configChanged = acceptConfiguration(snapshot.documents.first { $0.path == "config.json" }?.contents)
        acceptDiskDocuments(snapshot.documents)
        if configChanged { scheduleWorkspaceParse() }
        if !syncConflicts.isEmpty { syncState = .conflict(syncConflicts.count) }
        else if !dirtyFilePaths.isEmpty { syncState = .saving }
        else if !pendingUploadPaths.isEmpty { syncState = .pending(pendingUploadPaths.count) }
        else { syncState = storageConnection?.provider.isRemote == true ? .synced : .folderUpdated }
    }

    func queueFileSave(paths: Set<String>) {
        guard isWorkspaceReady else { return }
        for path in paths {
            if let document = documents.first(where: { $0.path == path }), document.kind != .folder,
               !document.contents.utf8.elementsEqual((persistedContents[path] ?? "").utf8) || persistedContents[path] == nil {
                dirtyFilePaths.insert(path)
            }
        }
        pendingFileCount = dirtyFilePaths.union(pendingUploadPaths).count
        guard !dirtyFilePaths.isEmpty else { return }
        syncState = .saving
        fileSaveTask?.cancel()
        fileSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.persistFileEdits()
            guard !Task.isCancelled else { return }
            await self?.synchronizeFiles(automatic: true)
        }
    }

    /// Local commits are independent of network synchronization. Actor
    /// reentrancy lets a new edit be saved even while an upload is in flight.
    func persistFileEdits() async {
        while isPersistingEdits {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
        }
        guard let fileStore, !dirtyFilePaths.isEmpty else { return }
        isPersistingEdits = true
        defer { isPersistingEdits = false }
        let identity = workspaceFileSessionID
        for path in dirtyFilePaths.sorted() {
            guard let contents = documents.first(where: { $0.path == path })?.contents else { continue }
            do {
                try await fileStore.write(path: path, contents: contents, expectedContents: persistedContents[path])
                guard identity == workspaceFileSessionID else { return }
                persistedContents[path] = contents
                fileSaveErrors.removeValue(forKey: path)
                if documents.first(where: { $0.path == path })?.contents.utf8.elementsEqual(contents.utf8) == true {
                    dirtyFilePaths.remove(path)
                }
            } catch {
                guard identity == workspaceFileSessionID else { return }
                fileSaveErrors[path] = error.localizedDescription
                fileSyncError = error.localizedDescription
                syncState = .failed(error.localizedDescription)
                try? await Self.preserveUnsaved(contents, path: path, workspaceIdentity: fileStore.recoveryIdentity)
            }
        }
        if let workspaceSession, let snapshot = try? await workspaceSession.snapshot(), identity == workspaceFileSessionID {
            applyStorageSnapshot(snapshot)
        }
        pendingFileCount = dirtyFilePaths.union(pendingUploadPaths).count
    }

    func synchronizeFiles(automatic: Bool = false) async {
        await persistFileEdits()
        guard !isSynchronizing, let fileStore, !Task.isCancelled else { return }
        if automatic && isChangingStorage { return }
        if let serverSyncRetryAt, serverSyncRetryAt > .now { return }
        if automatic, let automaticSyncRetryAt, automaticSyncRetryAt > .now { return }
        isSynchronizing = true
        let identity = workspaceFileSessionID
        defer { if identity == workspaceFileSessionID { isSynchronizing = false } }
        syncState = .syncing
        var failure: Error?
        do {
            if let workspaceSession {
                try await workspaceSession.synchronize()
                guard identity == workspaceFileSessionID else { return }
                applyStorageSnapshot(try await workspaceSession.snapshot())
            } else {
                let loaded = try await fileStore.load()
                guard identity == workspaceFileSessionID else { return }
                persistedContents = Dictionary(uniqueKeysWithValues: loaded.filter { $0.kind != .folder }.map { ($0.path, $0.contents) })
                acceptDiskDocuments(loaded)
                lastFileSync = .now
                syncState = .folderUpdated
            }
        } catch { failure = error }
        guard identity == workspaceFileSessionID else { return }
        if let workspaceSession, let snapshot = try? await workspaceSession.snapshot() { applyStorageSnapshot(snapshot) }
        if let failure {
            syncFailureCount = min(syncFailureCount + 1, 8)
            let delay = min(300, pow(2, Double(syncFailureCount)) * 2)
            automaticSyncRetryAt = .now.addingTimeInterval(delay)
            reportStorageError(failure)
        }
        else if !syncConflicts.isEmpty { fileSyncError = String(localized: "Resolve the conflicting files to finish syncing.") }
        else {
            syncFailureCount = 0
            automaticSyncRetryAt = nil
            serverSyncRetryAt = nil
            fileSyncError = fileSaveErrors.values.first
        }
        if fileSyncError != nil {
            for path in dirtyFilePaths.union(pendingUploadPaths) {
                if let contents = documents.first(where: { $0.path == path })?.contents {
                    try? await Self.preserveUnsaved(contents, path: path, workspaceIdentity: recoveryWorkspaceIdentity)
                }
            }
        }
    }

    var recoveryWorkspaceIdentity: String {
        guard let connection = storageConnection else { return fileStore?.recoveryIdentity ?? "workspace" }
        return connection.provider.isRemote ? connection.identity : connection.rootID
    }

    func resolveSyncConflict(path: String, resolution: WorkspaceConflictResolution,
                             expectedConflict: WorkspaceConflict? = nil) async {
        await persistFileEdits()
        guard let workspaceSession, await waitForFileOperation() else { return }
        if let expectedConflict, syncConflicts.first(where: { $0.path == path }) != expectedConflict {
            reportStorageError(StorageError.conflict(path))
            return
        }
        let identity = workspaceFileSessionID
        isSynchronizing = true
        defer { if identity == workspaceFileSessionID { isSynchronizing = false } }
        do {
            try await workspaceSession.resolveConflict(path: path, resolution: resolution)
            guard identity == workspaceFileSessionID else { return }
            applyStorageSnapshot(try await workspaceSession.snapshot())
            fileSyncError = syncConflicts.isEmpty ? nil : String(localized: "Resolve the conflicting files to finish syncing.")
            await waitForWorkspaceIndex()
        } catch {
            guard identity == workspaceFileSessionID else { return }
            if let snapshot = try? await workspaceSession.snapshot() { applyStorageSnapshot(snapshot) }
            reportStorageError(error)
        }
    }

    @discardableResult
    func adoptFolderVersions() async -> Bool {
        await persistFileEdits()
        for path in dirtyFilePaths.union(pendingUploadPaths) {
            if let document = documents.first(where: { $0.path == path }) {
                do { try await Self.preserveUnsaved(document.contents, path: path, workspaceIdentity: recoveryWorkspaceIdentity) }
                catch { reportStorageError(error); return false }
            }
        }
        await synchronizeFiles()
        guard let workspaceSession, dirtyFilePaths.isEmpty, await waitForFileOperation() else { return false }
        if syncConflicts.isEmpty { return pendingUploadPaths.isEmpty && fileSyncError == nil }
        for conflict in syncConflicts {
            await resolveSyncConflict(path: conflict.path, resolution: .useRemote)
        }
        if let snapshot = try? await workspaceSession.snapshot() { applyStorageSnapshot(snapshot) }
        return !hasPendingStorageChanges && fileSyncError == nil
    }

    func reportStorageError(_ error: Error) {
        fileSyncError = error.localizedDescription
        switch error {
        case StorageError.authenticationRequired: syncState = .authenticationRequired
        case StorageError.offline: syncState = .offline
        case StorageError.throttled(let delay):
            serverSyncRetryAt = .now.addingTimeInterval(delay)
            syncState = .failed(error.localizedDescription)
        case let url as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost].contains(url.code):
            syncState = .offline
        default: syncState = syncConflicts.isEmpty ? .failed(error.localizedDescription) : .conflict(syncConflicts.count)
        }
    }
}

private struct StorageReplacement {
    let retiredSession: WorkspaceSession?
    let generation: UInt64
    let sessionID: UUID
}

/// Cached data remains accessible even when its login configuration is missing.
private struct UnavailableStorageBackend: RemoteWorkspaceBackend {
    let reason: StorageError
    func scan(cursor: String?) async throws -> RemoteScan { throw reason }
    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload { throw reason }
    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile { throw reason }
    func createDirectory(path: String) async throws -> RemoteFile { throw reason }
    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile { throw reason }
}
