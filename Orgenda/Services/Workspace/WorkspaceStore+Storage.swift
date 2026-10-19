import Foundation
import UIKit

extension WorkspaceStore {
    static let storageConnectionKey = "storageConnection.v1"

    func finishStorageBeforeSuspending() async {
        guard isWorkspaceReady, let localStore else { return }
        let engine = engineForCurrentSession(localStore)
        let finishing = Task { await synchronizeFiles(pushOnly: true) }
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "Save workspace") {
            finishing.cancel()
            Task { await engine.cancelCurrent() }
        }
        await withTaskCancellationHandler {
            await finishing.value
        } onCancel: {
            finishing.cancel()
            Task { await engine.cancelCurrent() }
        }
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }

    func restoreConfiguredStorage(defaults: UserDefaults, localURL: URL) async {
        connectionDefaults = defaults
        if let data = defaults.data(forKey: Self.storageConnectionKey) {
            do {
                let connection = try JSONDecoder().decode(StorageConnection.self, from: data)
                if connection.provider.isRemote {
                    let backend: any RemoteWorkspaceBackend
                    do { backend = try await WebDAVConnectionFactory.restore(connection) }
                    catch { backend = UnavailableStorageBackend(reason: (error as? StorageError) ?? .configuration(error.localizedDescription)) }
                    let session = try LocalStore(connection: connection, cacheDirectory: storageCacheDirectory, remote: backend)
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
                        let session = try LocalStore(connection: connection, cacheDirectory: storageCacheDirectory, remote: unavailable)
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
                        let session = try LocalStore(connection: restored, cacheDirectory: storageCacheDirectory, folder: folder)
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
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            }.value
            try Task.checkCancellation()
            await connectFolder(localURL, remember: false, defaults: defaults)
        } catch { if !(error is CancellationError) { reportStorageError(error) } }
    }

    private func restoreSession(_ session: LocalStore, connection: StorageConnection, folderURL: URL?) async throws {
        if let cached = try? await session.snapshot() {
            try Task.checkCancellation()
            activateSession(session, connection: connection, snapshot: cached, folderURL: folderURL)
            // Offline startup is ready immediately. The scene's foreground
            // sync task validates the provider without blocking initial UI.
        } else {
            try await session.synchronize()
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
               let localStore {
                await persistFileEdits()
                try await localStore.replaceFolderBackend(WorkspaceFileStore(rootURL: url))
                if remember {
                    connection.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    defaults.set(try JSONEncoder().encode(connection), forKey: Self.storageConnectionKey)
                }
                folderAccessURL?.stopAccessingSecurityScopedResource()
                folderAccessURL = access ? url : nil
                storageConnection = connection
                await synchronizeFiles()
                return
            }
            let cloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            let digest = LocalStore.digest(Data(root.utf8))
            let hex = Array(digest.prefix(32))
            let uuidString = String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16])
                + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
            var connection = StorageConnection(id: UUID(uuidString: uuidString)!, provider: cloud ? .iCloud : .local,
                displayName: url.lastPathComponent == "Workspace" ? String(localized: "Org Workspace") : url.lastPathComponent,
                rootID: root)
            if remember {
                connection.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            let session = try LocalStore(connection: connection, cacheDirectory: storageCacheDirectory,
                                               folder: WorkspaceFileStore(rootURL: url))
            let previous = try await replaceStorageSession(session, connection: connection,
                folderURL: access ? url : nil, defaults: defaults, remember: remember,
                preservePending: preservePending)
            if let previous, previous.id != connection.id, previous.provider.isRemote {
                try? WebDAVConnectionFactory.removeCredentials(for: previous)
            }
            await waitForWorkspaceIndex()
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            if !(error is CancellationError) { reportStorageError(error) }
        }
    }

    func connectWebDAV(_ configuration: WebDAVConfiguration, preservePending: Bool = false) async -> Bool {
        await connectRemote(preservePending: preservePending) {
            try await WebDAVConnectionFactory.prepare(configuration: configuration)
        }
    }

    /// Renew access to the same account and root without rebinding its outbox.
    func reconnectStorage(webDAVPassword: String) async -> Bool {
        guard !isChangingStorage, !isSavingConfiguration, let original = storageConnection, original.provider.isRemote,
              let localStore else { return false }
        isChangingStorage = true
        defer { isChangingStorage = false }
        let identity = workspaceFileSessionID
        var candidate: PreparedRemoteConnection?
        do {
            let refreshed = try await WebDAVConnectionFactory.reauthenticate(original, password: webDAVPassword)
            candidate = refreshed
            guard identity == workspaceFileSessionID, refreshed.connection.identity == original.identity,
                  await waitForFileOperation() else { throw StorageError.rootUnavailable }
            await persistFileEdits()
            guard identity == workspaceFileSessionID else { throw StorageError.rootUnavailable }
            try await localStore.replaceRemoteBackend(refreshed.backend)
            connectionDefaults.set(try JSONEncoder().encode(refreshed.connection), forKey: Self.storageConnectionKey)
            storageConnection = refreshed.connection
            if original.credentialKey != refreshed.connection.credentialKey {
                try? WebDAVConnectionFactory.removeCredentials(for: original)
            }
            fileSyncError = nil
            await synchronizeFiles()
            return true
        } catch {
            if let candidate, candidate.connection.credentialKey != storageConnection?.credentialKey {
                try? WebDAVConnectionFactory.removeCredentials(for: candidate.connection)
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
            let session = try LocalStore(connection: candidate.connection, cacheDirectory: storageCacheDirectory,
                                               remote: candidate.backend)
            let previous = try await replaceStorageSession(session, connection: candidate.connection,
                                                           preservePending: preservePending)
            if let previous, previous.credentialKey != candidate.connection.credentialKey {
                try? WebDAVConnectionFactory.removeCredentials(for: previous)
            }
            await waitForWorkspaceIndex()
            return true
        } catch {
            if let prepared, prepared.connection.credentialKey != storageConnection?.credentialKey {
                try? WebDAVConnectionFactory.removeCredentials(for: prepared.connection)
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
        if let previous { try? WebDAVConnectionFactory.removeCredentials(for: previous) }
        return true
    }

    /// Both folder and WebDAV connections validate and preserve the old workspace
    /// before making the new session active. Credential cleanup stays with the caller.
    private func replaceStorageSession(
        _ session: LocalStore, connection: StorageConnection, folderURL: URL? = nil,
        defaults: UserDefaults? = nil, remember: Bool = true, preservePending: Bool
    ) async throws -> StorageConnection? {
        try await session.synchronize()
        let snapshot = try await session.snapshot()
        let replacement = try await prepareStorageReplacement(preservePending: preservePending)
        try Task.checkCancellation()
        try validateStorageReplacement(replacement)
        let previous = storageConnection
        let defaults = defaults ?? connectionDefaults
        if remember {
            defaults.set(try JSONEncoder().encode(connection), forKey: Self.storageConnectionKey)
        }
        connectionDefaults = defaults
        activateSession(session, connection: connection, snapshot: snapshot, folderURL: folderURL)
        if let retiredSession = replacement.retiredSession {
            do { try await retiredSession.retireAfterArchiving() }
            catch { reportStorageError(error) }
        }
        return previous
    }

    private func prepareStorageReplacement(preservePending: Bool) async throws -> StorageReplacement {
        guard await waitForFileOperation() else { throw CancellationError() }
        await persistFileEdits()
        guard dirtyFilePaths.isEmpty else { throw StorageError.configuration(String(localized: "Save changes on this device before replacing this connection.")) }
        guard hasPendingStorageChanges else {
            return StorageReplacement(retiredSession: nil, generation: storageContentGeneration, sessionID: workspaceFileSessionID)
        }
        if !preservePending {
            await synchronizeFiles()
            guard !hasPendingStorageChanges else {
                throw StorageError.configuration(String(localized: "Sync pending edits first, or keep a local copy before changing storage."))
            }
        } else if let localStore {
            let originalDocuments = documents
            try await localStore.archiveUnsynced()
            guard dirtyFilePaths.isEmpty, documents == originalDocuments else {
                throw StorageError.configuration(String(localized: "The workspace changed while keeping a copy. Finish editing and try again."))
            }
            return StorageReplacement(retiredSession: localStore, generation: storageContentGeneration, sessionID: workspaceFileSessionID)
        }
        return StorageReplacement(retiredSession: nil, generation: storageContentGeneration, sessionID: workspaceFileSessionID)
    }

    private func validateStorageReplacement(_ replacement: StorageReplacement) throws {
        guard replacement.generation == storageContentGeneration,
              replacement.sessionID == workspaceFileSessionID, dirtyFilePaths.isEmpty else {
            throw StorageError.configuration(String(localized: "The workspace changed while keeping a copy. Finish editing and try again."))
        }
    }

    private func activateSession(_ session: LocalStore, connection: StorageConnection,
                                 snapshot: WorkspaceSnapshot, folderURL: URL?) {
        folderAccessURL?.stopAccessingSecurityScopedResource()
        folderAccessURL = folderURL
        fileSaveTask?.cancel()
        fileSaveTask = nil
        workspaceFileSessionID = UUID()
        localStore = session
        appliedStorageRevision = 0
        storageConnection = connection
        isFolderConnected = true
        let shortcuts = connectionDefaults.dictionary(forKey: "workspaceFileShortcuts.\(connection.id)") as? [String: [String]] ?? [:]
        pinnedDocumentIDs = shortcuts["pinned"] ?? []
        recentDocumentIDs = shortcuts["recent"] ?? []
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
        storageObservationTask?.cancel()
        syncStatusTask?.cancel()
        folderMonitor?.stop()
        if let previousEngine = syncEngine { Task { await previousEngine.stop() } }
        syncEngine = nil
        syncRetryAt = nil
        let engine = engineForCurrentSession(session)
        Task { await engine.setForeground(self.isStorageForeground) }
        dirtyFilePaths = []
        externalDocumentRevisions = [:]
        resetWorkspaceIndex()
        documents = []
        items = []
        journalEntries = []
        applyStorageSnapshot(snapshot)
        scheduleWorkspaceParse()
    }

    func applyStorageSnapshot(_ snapshot: WorkspaceSnapshot) {
        guard snapshot.revision >= appliedStorageRevision else { return }
        appliedStorageRevision = snapshot.revision
        pendingUploadPaths = snapshot.pendingPaths
        pathSyncErrors = snapshot.uploadErrors
        hasPendingStorageOperation = snapshot.hasPendingOperation
        syncConflicts = snapshot.conflicts
        lastFileSync = snapshot.lastSync
        // This baseline describes the local durable copy, not cloud contents.
        let previousBaseline = Dictionary(uniqueKeysWithValues: dirtyFilePaths.compactMap { path in persistedBlobs[path].map { (path, $0) } })
        let retired = snapshot.isComplete ? Set(documentsByPath.keys).subtracting(snapshot.documents.map(\.path)) : snapshot.removedPaths
        for path in retired { retiredBlobs[path] = persistedBlobs[path] }
        if snapshot.isComplete { persistedBlobs = snapshot.blobHashes }
        else {
            for path in snapshot.removedPaths { persistedBlobs.removeValue(forKey: path) }
            persistedBlobs.merge(snapshot.blobHashes) { _, new in new }
        }
        // An editor's uncommitted bytes still belong to the baseline it saw.
        // Advancing that baseline would authorize overwriting an unseen update
        // on the next save retry. Session.write records this race as a conflict.
        for path in dirtyFilePaths { persistedBlobs[path] = previousBaseline[path] }
        let hasConfiguration = snapshot.isComplete || snapshot.removedPaths.contains("config.json") || snapshot.documents.contains { $0.path == "config.json" }
        let configChanged = hasConfiguration && acceptConfiguration(snapshot.documents.first { $0.path == "config.json" }?.contents)
        if snapshot.isComplete { acceptDiskDocuments(snapshot.documents) }
        else { acceptStorageDelta(snapshot) }
        // Newly saved documents acquire their persistent file ID.
        pinnedDocumentIDs = pinnedDocumentIDs.map { documentsByPath[$0]?.id ?? $0 }
        recentDocumentIDs = recentDocumentIDs.map { documentsByPath[$0]?.id ?? $0 }
        saveFileShortcuts()
        if configChanged { scheduleWorkspaceParse() }
        if !syncConflicts.isEmpty { syncState = .conflict(syncConflicts.count) }
        else if !dirtyFilePaths.isEmpty { syncState = .saving }
        else if !pendingUploadPaths.isEmpty || hasPendingStorageOperation { syncState = .pending(max(1, pendingUploadPaths.count)) }
        else { syncState = storageConnection?.provider.isRemote == true ? .synced : .folderUpdated }
    }

    func queueFileSave(paths: Set<String>) {
        guard isWorkspaceReady else { return }
        for path in paths {
            if let document = documentsByPath[path], document.kind != .folder,
               LocalStore.digest(Data(document.contents.utf8)) != persistedBlobs[path] {
                dirtyFilePaths.insert(path)
            }
        }
        guard !dirtyFilePaths.isEmpty else { return }
        syncState = .saving
        fileSaveTask?.cancel()
        fileSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.persistFileEdits()
            guard !Task.isCancelled else { return }
            await self?.synchronizeFiles(automatic: true, pushOnly: true)
        }
    }

    /// Local commits are independent of network synchronization. Actor
    /// reentrancy lets a new edit be saved even while an upload is in flight.
    func persistFileEdits() async {
        if let persistenceTask { await persistenceTask.value; return }
        let barrier = Task { [weak self] in
            guard let self else { return }
            await self.commitFileEdits()
        }
        persistenceTask = barrier
        await barrier.value
        persistenceTask = nil
    }

    private func commitFileEdits() async {
        guard let localStore, !dirtyFilePaths.isEmpty else { return }
        let identity = workspaceFileSessionID
        for path in dirtyFilePaths.sorted() {
            guard let contents = documentsByPath[path]?.contents else { continue }
            do {
                try await localStore.write(path: path, contents: contents, expectedBlob: persistedBlobs[path])
                guard identity == workspaceFileSessionID else { return }
                persistedBlobs[path] = LocalStore.digest(Data(contents.utf8))
                fileSaveErrors.removeValue(forKey: path)
                if documentsByPath[path]?.contents.utf8.elementsEqual(contents.utf8) == true {
                    dirtyFilePaths.remove(path)
                }
            } catch {
                guard identity == workspaceFileSessionID else { return }
                fileSaveErrors[path] = error.localizedDescription
                fileSyncError = error.localizedDescription
                syncState = .failed(error.localizedDescription)
                try? await localStore.preserveUnsaved(contents, path: path)
            }
        }
        if let snapshot = try? await localStore.snapshot(since: appliedStorageRevision), identity == workspaceFileSessionID {
            applyStorageSnapshot(snapshot)
        }
    }

    func synchronizeFiles(automatic: Bool = false, pushOnly: Bool = false) async {
        await persistFileEdits()
        guard let localStore, !Task.isCancelled else { return }
        if automatic && isChangingStorage { return }
        let engine = engineForCurrentSession(localStore)
        let identity = workspaceFileSessionID
        do {
            try await engine.request(pushOnly ? .push : .full, automatic: automatic)
            guard identity == workspaceFileSessionID else { return }
            applyStorageSnapshot(try await localStore.snapshot(since: appliedStorageRevision))
            fileSyncError = fileSaveErrors.values.first
        } catch {
            guard identity == workspaceFileSessionID else { return }
            if let snapshot = try? await localStore.snapshot(since: appliedStorageRevision) { applyStorageSnapshot(snapshot) }
            reportStorageError(error)
        }
    }

    func engineForCurrentSession(_ session: LocalStore) -> SyncEngine {
        if let syncEngine { return syncEngine }
        let engine = SyncEngine(store: session)
        syncEngine = engine
        observeStorage(session, engine: engine)
        return engine
    }

    private func observeStorage(_ session: LocalStore, engine: SyncEngine) {
        let identity = workspaceFileSessionID
        storageObservationTask = Task { [weak self] in
            for await _ in await session.deltas() {
                guard !Task.isCancelled, let self, identity == self.workspaceFileSessionID else { return }
                if let delta = try? await session.snapshot(since: self.appliedStorageRevision) { self.applyStorageSnapshot(delta) }
            }
        }
        syncStatusTask = Task { [weak self] in
            await engine.start()
            for await status in await engine.updates() {
                guard !Task.isCancelled, let self, identity == self.workspaceFileSessionID else { return }
                self.isSynchronizing = status.isSynchronizing
                self.syncRetryAt = status.retryAt
                if status.isSynchronizing { self.syncState = .syncing }
                else if let error = status.storageError { self.reportStorageError(error) }
                else if let message = status.error { self.fileSyncError = message; self.syncState = .failed(message) }
                else if let snapshot = try? await session.snapshot(since: self.appliedStorageRevision) {
                    self.applyStorageSnapshot(snapshot)
                    self.fileSyncError = self.fileSaveErrors.values.first
                }
            }
        }
        if let url = folderAccessURL ?? (storageConnection?.provider.isRemote == false ? URL(fileURLWithPath: session.connection.rootID) : nil) {
            folderMonitor = WorkspaceFolderMonitor(root: url, ubiquitous: session.connection.provider == .iCloud) { [weak engine] paths in
                Task { try? await engine?.sourceChanged(paths: paths) }
            }
        }
    }

    func setStorageForeground(_ active: Bool) async {
        isStorageForeground = active
        guard let localStore else { return }
        await engineForCurrentSession(localStore).setForeground(active)
    }

    func stopStorageObservation() async {
        fileSaveTask?.cancel()
        storageObservationTask?.cancel()
        syncStatusTask?.cancel()
        folderMonitor?.stop()
        folderMonitor = nil
        await syncEngine?.stop()
        await localStore?.close()
    }

    func resolveSyncConflict(path: String, resolution: WorkspaceConflictResolution,
                             expectedConflict: WorkspaceConflict? = nil) async {
        await persistFileEdits()
        guard let localStore, await waitForFileOperation() else { return }
        if let expectedConflict, syncConflicts.first(where: { $0.path == path }) != expectedConflict {
            reportStorageError(StorageError.conflict(path))
            return
        }
        let identity = workspaceFileSessionID
        do {
            try await engineForCurrentSession(localStore).resolveConflict(path: path, resolution: resolution)
            guard identity == workspaceFileSessionID else { return }
            applyStorageSnapshot(try await localStore.snapshot(since: appliedStorageRevision))
            fileSyncError = syncConflicts.isEmpty ? nil : String(localized: "Resolve the conflicting files to finish syncing.")
            await waitForWorkspaceIndex()
        } catch {
            guard identity == workspaceFileSessionID else { return }
            if let snapshot = try? await localStore.snapshot(since: appliedStorageRevision) { applyStorageSnapshot(snapshot) }
            reportStorageError(error)
        }
    }

    @discardableResult
    func adoptFolderVersions() async -> Bool {
        await persistFileEdits()
        guard let localStore else { return false }
        for path in dirtyFilePaths.union(pendingUploadPaths) {
            if let document = documentsByPath[path] {
                do { try await localStore.preserveUnsaved(document.contents, path: path) }
                catch { reportStorageError(error); return false }
            }
        }
        await synchronizeFiles()
        guard dirtyFilePaths.isEmpty, await waitForFileOperation() else { return false }
        if syncConflicts.isEmpty { return pendingUploadPaths.isEmpty && fileSyncError == nil }
        for conflict in syncConflicts {
            await resolveSyncConflict(path: conflict.path, resolution: .useRemote)
        }
        if let snapshot = try? await localStore.snapshot(since: appliedStorageRevision) { applyStorageSnapshot(snapshot) }
        return !hasPendingStorageChanges && fileSyncError == nil
    }

    func reportStorageError(_ error: Error) {
        fileSyncError = error.localizedDescription
        switch error {
        case StorageError.authenticationRequired: syncState = .authenticationRequired
        case StorageError.offline: syncState = .offline
        case StorageError.throttled:
            syncState = .failed(error.localizedDescription)
        case let url as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost].contains(url.code):
            syncState = .offline
        default: syncState = syncConflicts.isEmpty ? .failed(error.localizedDescription) : .conflict(syncConflicts.count)
        }
    }
}

private struct StorageReplacement {
    let retiredSession: LocalStore?
    let generation: UInt64
    let sessionID: UUID
}

/// Cached data remains accessible even when credentials or folder access are unavailable.
private struct UnavailableStorageBackend: RemoteWorkspaceBackend {
    let reason: StorageError
    func scan() async throws -> RemoteScan { throw reason }
    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload { throw reason }
    func upload(path: String, data: Data, existing: RemoteFile?) async throws -> RemoteFile { throw reason }
    func createDirectory(path: String) async throws -> RemoteFile { throw reason }
    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile { throw reason }
}
