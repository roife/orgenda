import CryptoKit
import Foundation

/// A durable local workspace, optionally connected to a remote service. UI
/// edits never require a network request; only synchronize performs uploads.
actor WorkspaceSession: WorkspaceFileAccess {
    nonisolated let recoveryIdentity: String
    nonisolated let connection: StorageConnection
    let directory: URL
    let recoveryDirectory: URL
    var folder: WorkspaceFileStore?
    var remote: (any RemoteWorkspaceBackend)?
    var manifest: SyncManifest
    var isSynchronizing = false
    var isPerformingFileOperation = false
    var lastBlobCleanup: Date?
    var commitsSinceBlobCleanup = 0
    let textLimit = 64 * 1024 * 1024

    init(connection: StorageConnection, cacheDirectory: URL,
         folder: WorkspaceFileStore? = nil, remote: (any RemoteWorkspaceBackend)? = nil,
         recoveryDirectory: URL? = nil) throws {
        self.connection = connection
        self.recoveryIdentity = connection.identity
        self.directory = cacheDirectory.appendingPathComponent(connection.id.uuidString, isDirectory: true)
        self.recoveryDirectory = recoveryDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unsaved Edits", isDirectory: true)
        self.folder = folder
        self.remote = remote
        guard (folder != nil) != (remote != nil) else {
            throw StorageError.configuration("A workspace needs exactly one storage source.")
        }
        let url = directory.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let saved = try JSONDecoder().decode(SyncManifest.self, from: Data(contentsOf: url))
            guard saved.version == 1, saved.identity == connection.identity else {
                throw StorageError.configuration("The workspace cache belongs to a different connection.")
            }
            manifest = saved
        } else {
            manifest = SyncManifest(identity: connection.identity)
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("blobs"), withIntermediateDirectories: true)
    }

    func initialize() async throws {
        try await synchronize()
    }

    func replaceRemoteBackend(_ backend: any RemoteWorkspaceBackend) throws {
        guard connection.provider.isRemote, folder == nil else { throw StorageError.configuration("A folder connection cannot use a cloud backend.") }
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        remote = backend
    }

    func replaceFolderBackend(_ backend: WorkspaceFileStore) throws {
        guard !connection.provider.isRemote, backend.recoveryIdentity == connection.rootID else {
            throw StorageError.configuration("Choose the original workspace folder to recover these pending edits.")
        }
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        folder = backend
        remote = nil
    }

    func snapshot() throws -> WorkspaceSessionSnapshot {
        guard manifest.initialized else { throw StorageError.rootUnavailable }
        return WorkspaceSessionSnapshot(documents: try load(), pendingPaths: Set(manifest.pending.keys),
            conflicts: manifest.conflicts.values.sorted { $0.path < $1.path }, lastSync: manifest.lastSync,
            hasPendingOperation: manifest.fileOperation != nil, revision: manifest.commitSequence ?? 0)
    }

    func load() throws -> [WorkspaceDocument] {
        var documents: [String: WorkspaceDocument] = [:]
        for (path, entry) in manifest.entries where Self.isVisible(path) {
            if entry.file.isDirectory {
                documents[path] = Self.document(path: path, contents: "", kind: .folder)
            } else if let kind = Self.documentKind(path), let blob = entry.blob {
                documents[path] = Self.document(path: path, contents: try text(blob), kind: kind)
            }
        }
        for (path, pending) in manifest.pending {
            guard let kind = Self.documentKind(path) else { continue }
            documents[path] = Self.document(path: path, contents: try text(pending.blob), kind: kind)
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if documents[parent] == nil { documents[parent] = Self.document(path: parent, contents: "", kind: .folder) }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return documents.values.sorted { $0.path < $1.path }
    }

    func write(path: String, contents: String, expectedContents: String?) throws {
        try Self.validateVisibleDocument(path)
        let folded = path.precomposedStringWithCanonicalMapping.lowercased()
        guard !Set(manifest.entries.keys).union(manifest.pending.keys).contains(where: {
            $0 != path && $0.precomposedStringWithCanonicalMapping.lowercased() == folded
        }), manifest.entries[path]?.file.isDirectory != true else { throw StorageError.conflict(path) }
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty {
            guard manifest.pending[parent] == nil, manifest.entries[parent]?.file.isDirectory != false else {
                throw StorageError.conflict(parent)
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
        let current = try localData(path)
        let bytes = Data(contents.utf8)
        if current == bytes { return }
        let expected = expectedContents.map { Data($0.utf8) }
        if current != expected {
            // A remote refresh can finish while the UI still holds an edit
            // based on the preceding snapshot. Save that edit durably, but do
            // not silently rebase it onto the unseen remote version.
            guard manifest.pending[path] == nil else { throw StorageError.conflict(path) }
            let blob = try storeBlob(bytes)
            let baselineBlob = try expected.map { try storeBlob($0) }
            var next = manifest
            var pending = SyncPendingWrite(blob: blob, base: next.entries[path]?.file, baseBlob: baselineBlob)
            pending.requiresResolution = true
            next.pending[path] = pending
            let existing = next.entries[path]
            next.conflicts[path] = WorkspaceConflict(path: path, localContents: contents,
                remoteContents: try existing?.blob.map { try text($0) }, remoteRevision: existing?.file.revision,
                detectedAt: .now, remoteModifiedAt: existing?.file.modifiedAt)
            try commit(next)
            return
        }
        let blob = try storeBlob(bytes)
        var next = manifest
        if var pending = next.pending[path] {
            pending.blob = blob
            pending.generation = UUID()
            next.pending[path] = pending
        } else {
            let baseline = next.entries[path]
            next.pending[path] = SyncPendingWrite(blob: blob, base: baseline?.file, baseBlob: baseline?.blob)
        }
        if var conflict = next.conflicts[path] {
            conflict.localContents = contents
            next.conflicts[path] = conflict
        }
        try commit(next)
    }

    func archiveUnsynced(to destination: URL) throws {
        guard !manifest.pending.isEmpty || !manifest.conflicts.isEmpty || manifest.fileOperation != nil else { return }
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
        for conflict in manifest.conflicts.values {
            guard let remoteContents = conflict.remoteContents else { continue }
            try StorageError.validate(path: conflict.path)
            let url = archive.appendingPathComponent("Remote Versions", isDirectory: true).appendingPathComponent(conflict.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(remoteContents.utf8).write(to: url, options: .atomic)
        }
        struct RecoveryInfo: Codable {
            var provider: String
            var displayName: String
            var rootID: String
            var pendingPaths: [String]
            var conflicts: [WorkspaceConflict]
            var operation: SyncFileOperation?
        }
        let info = RecoveryInfo(provider: connection.provider.rawValue, displayName: connection.displayName,
            rootID: connection.rootID, pendingPaths: manifest.pending.keys.sorted(),
            conflicts: Array(manifest.conflicts.values), operation: manifest.fileOperation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: archive.appendingPathComponent("recovery.json"), options: .atomic)
    }

    /// Called only after a verified recovery export and successful activation
    /// of the replacement connection. Immutable blobs and exports are retained.
    func retireAfterArchiving() throws {
        guard !isSynchronizing, !isPerformingFileOperation else { throw StorageError.busy }
        var next = manifest
        next.pending.removeAll()
        next.conflicts.removeAll()
        next.fileOperation = nil
        try commit(next)
    }

    func commit(_ updated: SyncManifest) throws {
        var next = updated
        let sequence = manifest.commitSequence ?? 0
        guard sequence < UInt64.max else { throw StorageError.configuration("The workspace revision counter is exhausted.") }
        next.commitSequence = sequence + 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(next).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        manifest = next
        commitsSinceBlobCleanup += 1
    }

    /// Exported recovery copies are independent files. Only unreachable cache
    /// blobs are collected, and only after the complete workspace is synced.
    func collectUnreferencedBlobsIfNeeded() throws {
        guard manifest.initialized, manifest.pending.isEmpty, manifest.conflicts.isEmpty,
              manifest.fileOperation == nil else { return }
        let now = Date.now
        guard lastBlobCleanup == nil || (commitsSinceBlobCleanup >= 32 &&
            now.timeIntervalSince(lastBlobCleanup ?? .distantPast) >= 15) else { return }
        let referenced = Set(manifest.entries.values.compactMap(\.blob))
            .union(manifest.attachments.values.map(\.blob))
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
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return hash
    }

    func data(_ blob: String) throws -> Data {
        guard blob.count == 64, blob.allSatisfy({ $0.isHexDigit }) else { throw StorageError.invalidResponse }
        let value = try Data(contentsOf: directory.appendingPathComponent("blobs").appendingPathComponent(blob))
        guard Self.digest(value) == blob else { throw StorageError.invalidResponse }
        return value
    }

    func text(_ blob: String) throws -> String {
        guard let string = String(data: try data(blob), encoding: .utf8) else { throw StorageError.invalidResponse }
        return string
    }

    func localData(_ path: String) throws -> Data? {
        if let pending = manifest.pending[path] { return try data(pending.blob) }
        if let blob = manifest.entries[path]?.blob { return try data(blob) }
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

    static func documentKind(_ path: String) -> WorkspaceDocument.Kind? {
        if path == "config.json" { return .configuration }
        return switch (path as NSString).pathExtension.lowercased() {
        case "org", "org_archive": .org
        case "md", "markdown": .markdown
        default: nil
        }
    }

    static func isVisible(_ path: String) -> Bool {
        !path.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    static func validateVisibleDocument(_ path: String) throws {
        try StorageError.validate(path: path)
        guard isVisible(path), documentKind(path) != nil else { throw StorageError.unsafePath(path) }
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
