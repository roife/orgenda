import CryptoKit
import Foundation

/// A durable local workspace, optionally connected to a remote service. UI
/// edits never require a network request; only synchronize performs uploads.
actor LocalStore {
    nonisolated let connection: StorageConnection
    let directory: URL
    let recoveryDirectory: URL
    enum Source: Sendable {
        case folder(WorkspaceFileStore)
        case remote(any RemoteWorkspaceBackend)
    }

    private(set) var source: Source
    var state: WorkspaceState
    let database: WorkspaceStateDatabase
    var isSynchronizing = false
    var minimumSyncInterval: TimeInterval = 30
    var isPerformingFileOperation = false
    var lastBlobCleanup: Date?
    var commitsSinceBlobCleanup = 0
    var uploadErrors: [String: String] = [:]
    var sourceErrors: [String: String] = [:]
    var view: [String: WorkspaceViewEntry] = [:]
    var foldedPaths: [String: String] = [:]
    var filePathsByID: [UUID: String] = [:]
    var changes: [(revision: UInt64, paths: Set<String>)] = []
    var deltaListeners: [UUID: AsyncStream<WorkspaceDelta>.Continuation] = [:]
    let blobCache: WorkspaceBlobCache
    let textLimit = 64 * 1024 * 1024

    init(connection: StorageConnection, cacheDirectory: URL, folder: WorkspaceFileStore,
         recoveryDirectory: URL? = nil) throws {
        try self.init(connection: connection, cacheDirectory: cacheDirectory,
                      source: .folder(folder), recoveryDirectory: recoveryDirectory)
    }

    init(connection: StorageConnection, cacheDirectory: URL, remote: any RemoteWorkspaceBackend,
         recoveryDirectory: URL? = nil) throws {
        try self.init(connection: connection, cacheDirectory: cacheDirectory,
                      source: .remote(remote), recoveryDirectory: recoveryDirectory)
    }

    private init(connection: StorageConnection, cacheDirectory: URL, source: Source,
                 recoveryDirectory: URL?) throws {
        self.connection = connection
        self.directory = cacheDirectory.appendingPathComponent(connection.id.uuidString, isDirectory: true)
        self.recoveryDirectory = recoveryDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unsaved Edits", isDirectory: true)
        self.source = source
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        database = try WorkspaceStateDatabase(directory: directory)
        let blobs = directory.appendingPathComponent("blobs")
        let cache = WorkspaceBlobCache()
        blobCache = cache
        state = try database.load(identity: connection.identity) { hash in
            if let cached = cache[hash]?.text { return cached }
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw StorageError.invalidResponse }
            let data = try Data(contentsOf: blobs.appendingPathComponent(hash))
            guard Self.digest(data) == hash, let value = String(data: data, encoding: .utf8) else { throw StorageError.invalidResponse }
            cache[hash] = CachedWorkspaceBlob(text: value)
            return value
        }
        view = Self.makeView(state)
        filePathsByID = Self.filePaths(state)
        foldedPaths = Dictionary(view.keys.map { (Self.fold($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    func replaceRemoteBackend(_ backend: any RemoteWorkspaceBackend) throws {
        guard connection.provider.isRemote, case .remote = source else {
            throw StorageError.configuration("A folder connection cannot use a WebDAV backend.")
        }
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        source = .remote(backend)
    }

    func replaceFolderBackend(_ backend: WorkspaceFileStore) throws {
        guard !connection.provider.isRemote, backend.recoveryIdentity == connection.rootID else {
            throw StorageError.configuration("Choose the original workspace folder to recover these pending edits.")
        }
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        source = .folder(backend)
    }

    func snapshot(since revision: UInt64? = nil) throws -> WorkspaceSnapshot {
        guard state.initialized else { throw StorageError.rootUnavailable }
        let complete = revision == nil || revision! > state.commitSequence ||
            (revision! < state.commitSequence && (changes.first?.revision ?? .max) > revision! + 1)
        let paths = complete ? Set(view.keys) : Set(changes.filter { $0.revision > revision! }.flatMap(\.paths))
        let documents = try paths.sorted().compactMap { try document(at: $0) }
        return WorkspaceSnapshot(documents: documents, pendingPaths: Set(state.pending.keys.map { self.visiblePath($0) }),
            conflicts: state.conflicts.values.map { conflict in
                var value = conflict; value.path = self.visiblePath(value.path); return value
            }.sorted { $0.path < $1.path }, lastSync: state.lastSync,
            hasPendingOperation: !state.operations.isEmpty, revision: state.commitSequence,
            blobHashes: Dictionary(uniqueKeysWithValues: paths.compactMap { path in view[path]?.blob.map { (path, $0) } }),
            removedPaths: Set(paths.filter { view[$0] == nil }), isComplete: complete, uploadErrors: uploadErrors.merging(sourceErrors) { _, new in new })
    }

    func deltas() -> AsyncStream<WorkspaceDelta> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            deltaListeners[id] = continuation
            continuation.yield(WorkspaceDelta(revision: state.commitSequence, changedPaths: [], removedPaths: [], blobHashes: [:]))
            continuation.onTermination = { [weak self] _ in Task { await self?.removeDeltaListener(id) } }
        }
    }

    private func removeDeltaListener(_ id: UUID) { deltaListeners.removeValue(forKey: id) }

    func close() {
        for listener in deltaListeners.values { listener.finish() }
        deltaListeners.removeAll()
        database.close()
    }

    func load() throws -> [WorkspaceDocument] {
        try snapshot().documents
    }

    func document(at path: String) throws -> WorkspaceDocument? {
        guard let entry = view[path] else { return nil }
        return try document(path: path, entry: entry)
    }

    func document(path: String, entry: WorkspaceViewEntry) throws -> WorkspaceDocument {
        var document = Self.document(path: path, contents: try entry.blob.map { try text($0) } ?? "", kind: entry.kind)
        document.fileID = entry.fileID
        return document
    }

    func write(path: String, contents: String, expectedContents: String?) throws {
        try write(path: path, contents: contents, expectedBlob: expectedContents.map { Self.digest(Data($0.utf8)) })
    }

    func write(path visiblePath: String, contents: String, expectedBlob: String?) throws {
        try Self.validateVisibleDocument(visiblePath)
        let path = underlyingPath(visiblePath)
        let folded = Self.fold(visiblePath)
        guard foldedPaths[folded] == nil || foldedPaths[folded] == visiblePath,
              state.entries[path]?.file.isDirectory != true else { throw StorageError.conflict(path) }
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty {
            guard state.pending[parent] == nil, state.entries[parent]?.file.isDirectory != false else {
                throw StorageError.conflict(parent)
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
        let current = state.pending[path]?.blob ?? state.entries[path]?.blob
        let bytes = Data(contents.utf8)
        let hash = Self.digest(bytes)
        if current == hash { return }
        if current != expectedBlob {
            // A remote refresh can finish while the UI still holds an edit
            // based on the preceding snapshot. Save that edit durably, but do
            // not silently rebase it onto the unseen remote version.
            guard state.pending[path] == nil else { throw StorageError.conflict(path) }
            let blob = try storeBlob(bytes)
            let baselineBlob = expectedBlob
            let existing = state.entries[path]
            var pending = WorkspaceDraft(blob: blob, base: existing?.file, baseBlob: baselineBlob)
            pending.fileID = existing?.fileID ?? UUID()
            pending.requiresResolution = true
            let conflict = WorkspaceConflict(path: path, localContents: contents,
                remoteContents: try existing?.blob.map { try text($0) }, remoteRevision: existing?.file.revision,
                detectedAt: .now, remoteModifiedAt: existing?.file.modifiedAt)
            try commitFile(path: path, file: existing, draft: pending, conflict: conflict)
            return
        }
        let blob = try storeBlob(bytes)
        let existing = state.entries[path]
        var pending = state.pending[path] ?? WorkspaceDraft(blob: blob, base: existing?.file, baseBlob: existing?.blob)
        pending.fileID = state.pending[path]?.fileID ?? existing?.fileID ?? UUID()
        pending.blob = blob
        pending.generation = UUID()
        var conflict = state.conflicts[path]
        if state.operations.contains(where: { $0.kind == .trash && WorkspaceFileTransfer.contains(visiblePath, in: $0.sourcePath) }) {
            pending.requiresResolution = true
            conflict = WorkspaceConflict(path: path, localContents: contents, remoteContents: nil,
                remoteRevision: nil, detectedAt: .now, remoteModifiedAt: nil)
        } else { conflict?.localContents = contents }
        try commitFile(path: path, file: existing, draft: pending, conflict: conflict)
    }

    func archiveUnsynced(to destination: URL) throws {
        guard !state.pending.isEmpty || !state.conflicts.isEmpty || !state.operations.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let permitted = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let safeName = String(connection.displayName.unicodeScalars.map { permitted.contains($0) ? Character(String($0)) : "_" }.prefix(60))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = formatter.string(from: .now) + " " + (safeName.isEmpty ? "Workspace" : safeName) + " " + String(UUID().uuidString.prefix(8))
        let archive = destination.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        // Include the readable context around pending edits. This is a portable
        // recovery copy, never an account capable of continuing background sync.
        for document in try load() where document.kind != .folder {
            let url = archive.appendingPathComponent("Local Files", isDirectory: true).appendingPathComponent(document.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(document.contents.utf8).write(to: url, options: .atomic)
        }
        for conflict in state.conflicts.values {
            guard let remoteContents = conflict.remoteContents else { continue }
            try StorageError.validate(path: conflict.path)
            let url = archive.appendingPathComponent("Remote Versions", isDirectory: true).appendingPathComponent(conflict.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(remoteContents.utf8).write(to: url, options: .atomic)
        }
        for (path, draft) in state.pending {
            try StorageError.validate(path: path)
            let url = archive.appendingPathComponent("Pending Files", isDirectory: true).appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data(draft.blob).write(to: url, options: .atomic)
        }
        struct RecoveryInfo: Codable {
            var provider: String
            var displayName: String
            var rootID: String
            var pendingPaths: [String]
            var conflicts: [WorkspaceConflict]
            var operations: [WorkspaceOperation]
        }
        let info = RecoveryInfo(provider: connection.provider.rawValue, displayName: connection.displayName,
            rootID: connection.rootID, pendingPaths: state.pending.keys.sorted(),
            conflicts: Array(state.conflicts.values), operations: state.operations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: archive.appendingPathComponent("recovery.json"), options: .atomic)
    }

    func archiveUnsynced() throws {
        let destination = recoveryDirectory.appendingPathComponent(
            "\(Int(Date.now.timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        try archiveUnsynced(to: destination)
    }

    /// Content addressing retains every distinct draft without duplicating an
    /// unchanged conflict on each refresh or colliding across workspaces.
    func preserveUnsaved(_ contents: String, path: String) throws {
        let identity = connection.provider.isRemote ? connection.identity : connection.rootID
        let recovery = recoveryDirectory.appendingPathComponent(Self.digest(Data(identity.utf8)), isDirectory: true)
        let name = Self.digest(Data(path.utf8)) + "-" + Self.digest(Data(contents.utf8))
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: recovery.appendingPathComponent(name + ".txt"), options: .atomic)
        let metadata = ["workspace": identity, "path": path]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: recovery.appendingPathComponent(name + ".json"), options: .atomic)
    }

    /// Called only after a verified recovery export and successful activation
    /// of the replacement connection. Immutable blobs and exports are retained.
    func retireAfterArchiving() throws {
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        var next = state
        next.pending.removeAll()
        next.conflicts.removeAll()
        next.operations.removeAll()
        try commit(next)
    }

    func commit(_ updated: WorkspaceState, changedPaths: Set<String>? = nil) throws {
        var next = updated
        next.commitSequence = state.commitSequence + 1
        try database.save(next, previous: state, paths: changedPaths) { try storeBlob(Data($0.utf8)) }
        state = next
        if changedPaths == nil { filePathsByID = Self.filePaths(state) }
        updateView(changedPaths: changedPaths)
        commitsSinceBlobCleanup += 1
    }

    /// Ordinary edits and acknowledgements use a one-file transaction. Keeping
    /// the transaction patch separate avoids copying the entire files/drafts
    /// dictionary through Swift's copy-on-write storage on each save.
    func commitFile(path: String, file: WorkspaceFileRecord?, draft: WorkspaceDraft?, conflict: WorkspaceConflict?) throws {
        var previous = WorkspaceState(identity: state.identity)
        previous.initialized = state.initialized
        previous.commitSequence = state.commitSequence
        previous.lastSync = state.lastSync
        previous.operations = state.operations
        previous.entries[path] = state.entries[path]
        previous.pending[path] = state.pending[path]
        previous.conflicts[path] = state.conflicts[path]
        var next = previous
        next.entries[path] = file
        next.pending[path] = draft
        next.conflicts[path] = conflict
        next.commitSequence += 1
        try database.save(next, previous: previous, paths: [path]) { try storeBlob(Data($0.utf8)) }
        if let oldID = state.entries[path]?.fileID ?? state.pending[path]?.fileID { filePathsByID.removeValue(forKey: oldID) }
        if let id = file?.fileID ?? draft?.fileID { filePathsByID[id] = path }
        state.entries[path] = file
        state.pending[path] = draft
        state.conflicts[path] = conflict
        state.commitSequence = next.commitSequence
        updateView(changedPaths: [path])
        commitsSinceBlobCleanup += 1
    }

    /// Exported recovery copies are independent files. Only unreachable cache
    /// blobs are collected, and only after the complete workspace is synced.
    func collectUnreferencedBlobsIfNeeded() throws {
        guard state.initialized, state.pending.isEmpty, state.conflicts.isEmpty,
              state.operations.isEmpty else { return }
        let now = Date.now
        guard lastBlobCleanup == nil || (commitsSinceBlobCleanup >= 32 &&
            now.timeIntervalSince(lastBlobCleanup ?? .distantPast) >= 15) else { return }
        let referenced = Set(state.entries.values.compactMap(\.blob))
            .union(state.attachments.values.map(\.blob))
        let blobs = directory.appendingPathComponent("blobs", isDirectory: true)
        for file in try FileManager.default.contentsOfDirectory(at: blobs,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            let name = file.lastPathComponent
            guard name.count == 64, name.allSatisfy({ $0.isHexDigit }), !referenced.contains(name) else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true { try FileManager.default.removeItem(at: file) }
        }
        lastBlobCleanup = now
        commitsSinceBlobCleanup = 0
    }

    func storeBlob(_ data: Data) throws -> String {
        let hash = Self.digest(data)
        let url = directory.appendingPathComponent("blobs").appendingPathComponent(hash)
        var needsWrite = true
        if FileManager.default.fileExists(atPath: url.path) {
            // A matching filename does not prove an earlier blob is intact.
            // Verify its bytes before acknowledging a new durable reference.
            let existing = try Data(contentsOf: url)
            needsWrite = existing != data
        }
        if needsWrite {
            try data.write(to: url, options: .atomic)
        }
        cacheBlob(data, hash: hash)
        return hash
    }

    func data(_ blob: String) throws -> Data {
        guard blob.count == 64, blob.allSatisfy({ $0.isHexDigit }) else { throw StorageError.invalidResponse }
        if let cached = blobCache[blob] {
            if let data = cached.data { return data }
            return Data((cached.text ?? "").utf8)
        }
        let value = try Data(contentsOf: directory.appendingPathComponent("blobs").appendingPathComponent(blob))
        guard Self.digest(value) == blob else { throw StorageError.invalidResponse }
        cacheBlob(value, hash: blob)
        return value
    }

    func text(_ blob: String) throws -> String {
        if let cached = blobCache[blob]?.text {
            return cached
        }
        guard let string = String(data: try data(blob), encoding: .utf8) else { throw StorageError.invalidResponse }
        blobCache[blob] = CachedWorkspaceBlob(text: string)
        return string
    }

    func cacheBlob(_ data: Data, hash: String) {
        blobCache[hash] = CachedWorkspaceBlob(data: data)
    }

    static func filePaths(_ state: WorkspaceState) -> [UUID: String] {
        var result = Dictionary(state.entries.map { ($0.value.fileID, $0.key) }, uniquingKeysWith: { first, _ in first })
        for (path, draft) in state.pending { result[draft.fileID] = path }
        return result
    }

    static func fold(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }

    func underlyingPath(_ path: String) -> String {
        var result = path
        for operation in state.operations.reversed() {
            if WorkspaceFileTransfer.contains(result, in: operation.destinationPath) {
                result = operation.sourcePath + result.dropFirst(operation.destinationPath.count)
            }
        }
        return result
    }

    func visiblePath(_ path: String) -> String { Self.projectedPath(path, in: state) }

    static func projectedPath(_ path: String, in state: WorkspaceState) -> String {
        if state.pending[path]?.requiresResolution == true,
           state.operations.contains(where: { $0.kind == .trash && WorkspaceFileTransfer.contains(path, in: $0.sourcePath) }) { return path }
        var result = path
        for operation in state.operations {
            if WorkspaceFileTransfer.contains(result, in: operation.sourcePath) {
                result = operation.destinationPath(for: result)
            }
        }
        return result
    }

    static func projectedRecords(_ state: WorkspaceState) -> [String: WorkspaceViewEntry] {
        var result: [String: WorkspaceViewEntry] = [:]
        for (path, entry) in state.entries {
            if entry.file.isDirectory { result[path] = WorkspaceViewEntry(kind: .folder, blob: nil, fileID: entry.fileID) }
            else if let kind = WorkspaceDocument.Kind(path: path) ?? state.trash.first(where: { $0.storagePath == path })?.kind ?? state.operations.compactMap(\.trashEntry).first(where: { $0.storagePath == path })?.kind,
                    let blob = entry.blob { result[path] = WorkspaceViewEntry(kind: kind, blob: blob, fileID: entry.fileID) }
        }
        for (path, pending) in state.pending {
            if let kind = WorkspaceDocument.Kind(path: path) ?? result[path]?.kind {
                result[path] = WorkspaceViewEntry(kind: kind, blob: pending.blob, fileID: pending.fileID)
            }
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if result[parent] == nil { result[parent] = WorkspaceViewEntry(kind: .folder, blob: nil) }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        for operation in state.operations {
            for expected in operation.expected {
                let physical = expected.path
                if state.pending[physical] == nil {
                    result[physical] = WorkspaceViewEntry(kind: expected.kind,
                        blob: expected.kind == .folder ? nil : digest(Data(expected.contents.utf8)), fileID: expected.fileID)
                }
            }
            let moved = result.filter { WorkspaceFileTransfer.contains($0.key, in: operation.sourcePath) }
            for (path, record) in moved {
                result.removeValue(forKey: path)
                result[operation.destinationPath(for: path)] = record
            }
        }
        for (path, pending) in state.pending where pending.requiresResolution {
            if let kind = WorkspaceDocument.Kind(path: path) {
                result[path] = WorkspaceViewEntry(kind: kind, blob: pending.blob, fileID: pending.fileID)
            }
        }
        return result
    }

    static func makeView(_ state: WorkspaceState) -> [String: WorkspaceViewEntry] {
        projectedRecords(state).filter { isVisible($0.key) }
    }

    func updateView(changedPaths: Set<String>?) {
        var changed: Set<String> = []
        if let changedPaths {
            for path in changedPaths {
                let entry = state.entries[path]
                let blob = state.pending[path]?.blob ?? entry?.blob
                let effective = visiblePath(path)
                let kind: WorkspaceDocument.Kind? = entry?.file.isDirectory == true ? .folder : WorkspaceDocument.Kind(path: effective)
                let value = kind.flatMap { kind in Self.isVisible(effective) && (blob != nil || kind == .folder) ? WorkspaceViewEntry(kind: kind, blob: blob, fileID: state.pending[path]?.fileID ?? entry?.fileID) : nil }
                if value != view[effective] { changed.insert(effective); view[effective] = value }
                if value != nil { foldedPaths[Self.fold(effective)] = effective }
                else { foldedPaths.removeValue(forKey: Self.fold(effective)) }
                var parent = (effective as NSString).deletingLastPathComponent
                while !parent.isEmpty {
                    if view[parent] == nil {
                        view[parent] = WorkspaceViewEntry(kind: .folder, blob: nil)
                        foldedPaths[Self.fold(parent)] = parent
                        changed.insert(parent)
                    }
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
        } else {
            let next = Self.makeView(state)
            changed = Set(view.keys).union(next.keys).filter { view[$0] != next[$0] }
            view = next
            foldedPaths = Dictionary(view.keys.map { (Self.fold($0), $0) }, uniquingKeysWith: { first, _ in first })
        }
        changes.append((state.commitSequence, changed))
        if changes.count > 128 { changes.removeFirst(changes.count - 128) }
        let delta = WorkspaceDelta(revision: state.commitSequence, changedPaths: changed,
            removedPaths: Set(changed.filter { view[$0] == nil }),
            blobHashes: Dictionary(uniqueKeysWithValues: changed.compactMap { path in view[path]?.blob.map { (path, $0) } }))
        for listener in deltaListeners.values { listener.yield(delta) }
    }

    func localData(_ path: String) throws -> Data? {
        if let pending = state.pending[path] { return try data(pending.blob) }
        if let blob = state.entries[path]?.blob { return try data(blob) }
        return nil
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func document(path: String, contents: String, kind: WorkspaceDocument.Kind) -> WorkspaceDocument {
        WorkspaceDocument(path: path,
            title: kind == .folder ? (path as NSString).lastPathComponent : ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
            contents: contents, kind: kind)
    }

    static func isVisible(_ path: String) -> Bool {
        !path.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    static func validateVisibleDocument(_ path: String) throws {
        try StorageError.validate(path: path)
        guard isVisible(path), WorkspaceDocument.Kind(path: path) != nil else { throw StorageError.unsafePath(path) }
    }

    static func isUnavailable(_ error: Error) -> Bool {
        if let error = error as? StorageError {
            switch error { case .offline, .rootUnavailable, .authenticationRequired: return true; default: break }
        }
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed].contains(error.code)
        }
        return (error as? WorkspaceFileStore.Failure) == .unavailableRoot
    }
}

struct WorkspaceDelta: Sendable {
    var revision: UInt64
    var changedPaths: Set<String>
    var removedPaths: Set<String>
    var blobHashes: [String: String]
}

struct WorkspaceViewEntry: Equatable, Sendable {
    var kind: WorkspaceDocument.Kind
    var blob: String?
    var fileID: UUID? = nil
}
