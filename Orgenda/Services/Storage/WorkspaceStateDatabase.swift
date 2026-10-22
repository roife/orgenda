import Foundation
import GRDB

/// Owned exclusively by LocalStore. Immutable blobs are written before COMMIT;
/// COMMIT is the only point at which new drafts or operations become visible.
final class WorkspaceStateDatabase {
    private var queue: DatabaseQueue?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(2.5)
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("state.sqlite").path,
                                      configuration: configuration)
        // Configure outside a transaction; changing journal mode requires it.
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA synchronous=FULL")
        }
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS files (file_id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, remote_path TEXT NOT NULL UNIQUE, folded_path TEXT NOT NULL UNIQUE, payload BLOB)")
            for table in ["drafts", "conflicts", "ops", "trash", "attachments", "meta"] {
                try db.execute(sql: "CREATE TABLE IF NOT EXISTS \(table) (record_key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
            }
        }
        self.queue = queue
    }

    func close() {
        // GRDB closes its connection when this last owner releases the queue.
        queue = nil
    }

    private struct Meta: Codable {
        var identity: String
        var initialized: Bool
        var revision: UInt64
        var lastSync: Date?
    }

    func load(identity: String, text: (String) throws -> String) throws -> WorkspaceState {
        guard let queue else { throw StorageError.configuration("The workspace state database is closed.") }
        return try queue.read { db in
            var state = WorkspaceState(identity: identity)
            if let bytes = try records(db, "meta")["workspace"] {
                let saved = try decoder.decode(Meta.self, from: bytes)
                guard saved.identity == identity else { throw StorageError.configuration("The workspace cache belongs to a different connection.") }
                state.initialized = saved.initialized
                state.commitSequence = saved.revision
                state.lastSync = saved.lastSync
            }
            var pathsByID: [String: String] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT file_id, remote_path, payload FROM files")
            while let row = try rows.next() {
                let id: String = row["file_id"]
                let path: String = row["remote_path"]
                pathsByID[id] = path
                if let payload: Data = row["payload"] {
                    state.entries[path] = try decoder.decode(WorkspaceFileRecord.self, from: payload)
                }
            }
            for (id, bytes) in try records(db, "drafts") {
                guard let path = pathsByID[id] else { throw StorageError.invalidResponse }
                state.pending[path] = try decoder.decode(WorkspaceDraft.self, from: bytes)
            }
            for (key, bytes) in try records(db, "conflicts") {
                let path: String
                if key.hasPrefix("path:") { path = String(key.dropFirst(5)) }
                else if let associated = pathsByID[key] { path = associated }
                else { throw StorageError.invalidResponse }
                state.conflicts[path] = try decoder.decode(StoredConflict.self, from: bytes).hydrate(path: path, text: text)
            }
            state.operations = try records(db, "ops").values.map {
                try decoder.decode(StoredOperation.self, from: $0).hydrate(text: text)
            }.sorted { $0.sequence < $1.sequence }
            state.trash = try records(db, "trash").values.map { try decoder.decode(WorkspaceTrashEntry.self, from: $0) }
                .sorted { $0.deletedAt > $1.deletedAt }
            state.attachments = try records(db, "attachments").mapValues { try decoder.decode(CachedWorkspaceAttachment.self, from: $0) }
            return state
        }
    }

    /// With explicit paths, ordinary saves touch only those rows and one small
    /// metadata row. Bulk refreshes compare metadata without re-encoding text.
    func save(_ next: WorkspaceState, previous: WorkspaceState, paths: Set<String>?,
              storeText: (String) throws -> String) throws {
        guard let queue else { throw StorageError.configuration("The workspace state database is closed.") }
        // GRDB's write transaction uses BEGIN IMMEDIATE and rolls back on error.
        try queue.write { db in
            if let saved = try records(db, "meta")["workspace"] {
                let current = try decoder.decode(Meta.self, from: saved)
                guard current.revision == previous.commitSequence else {
                    throw StorageError.configuration("Another local session changed this workspace. Reopen it before saving.")
                }
            }
            let touched = paths ?? Set(previous.entries.keys).union(next.entries.keys)
                .union(previous.pending.keys).union(next.pending.keys)
            for path in touched where next.entries[path] == nil && next.pending[path] == nil {
                try db.execute(sql: "DELETE FROM files WHERE remote_path = ?", arguments: [path])
                if let old = previous.pending[path] { try remove(db, "drafts", key: old.fileID.uuidString) }
            }
            // Free logical destinations before reassigning any paths. This
            // handles an aborted move restoring its source while retaining a
            // draft at the intended destination, independent of Set order.
            for path in touched {
                guard next.entries[path] != nil || next.pending[path] != nil,
                      LocalStore.projectedPath(path, in: next) != LocalStore.projectedPath(path, in: previous),
                      let id = previous.entries[path]?.fileID ?? previous.pending[path]?.fileID else { continue }
                let temporary = ".orgenda-state-" + UUID().uuidString
                try db.execute(sql: "UPDATE files SET path = ?, folded_path = ? WHERE file_id = ?", arguments: [temporary, temporary, id.uuidString])
            }
            for path in touched {
                let entry = next.entries[path]
                let pending = next.pending[path]
                guard let id = entry?.fileID ?? pending?.fileID else { continue }
                let localPath = LocalStore.projectedPath(path, in: next)
                let previousPath = LocalStore.projectedPath(path, in: previous)
                if entry != previous.entries[path] || pending?.fileID != previous.pending[path]?.fileID || localPath != previousPath {
                    let payload = try entry.map { try encoder.encode($0) }
                    try db.execute(sql: "DELETE FROM files WHERE remote_path = ? AND file_id <> ?", arguments: [path, id.uuidString])
                    try db.execute(sql: "INSERT INTO files (file_id,path,remote_path,folded_path,payload) VALUES (?,?,?,?,?) ON CONFLICT(file_id) DO UPDATE SET path=excluded.path,remote_path=excluded.remote_path,folded_path=excluded.folded_path,payload=excluded.payload",
                        arguments: [id.uuidString, localPath, path, LocalStore.fold(localPath), payload])
                }
                if pending != previous.pending[path] {
                    if let pending { try put(db, "drafts", key: id.uuidString, value: pending) }
                    else { try remove(db, "drafts", key: id.uuidString) }
                }
            }
            // Remove drafts for deleted files; moved IDs retain their drafts.
            if paths == nil {
                let retained = Set(next.pending.values.map(\.fileID))
                for draft in previous.pending.values where !retained.contains(draft.fileID) { try remove(db, "drafts", key: draft.fileID.uuidString) }
            }
            func conflictKey(_ state: WorkspaceState, path: String) -> String {
                (state.entries[path]?.fileID ?? state.pending[path]?.fileID)?.uuidString ?? "path:" + path
            }
            let conflictPaths = paths ?? Set(previous.conflicts.keys).union(next.conflicts.keys)
            let retainedConflicts = Set(next.conflicts.keys.map { conflictKey(next, path: $0) })
            let oldConflicts = Dictionary(previous.conflicts.map { (conflictKey(previous, path: $0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
            for path in conflictPaths {
                let oldKey = conflictKey(previous, path: path), newKey = conflictKey(next, path: path)
                if previous.conflicts[path] != nil && !retainedConflicts.contains(oldKey) { try remove(db, "conflicts", key: oldKey) }
                if let conflict = next.conflicts[path] {
                    // Renames update the associated files row; the conflict
                    // payload has no duplicated mutable path.
                    var old = oldConflicts[newKey]
                    old?.path = path
                    if old != conflict {
                        try put(db, "conflicts", key: newKey, value: StoredConflict(conflict, storeText: storeText))
                    }
                }
            }
            if paths == nil && next.operations != previous.operations {
                let retained = Set(next.operations.map(\.id))
                for operation in previous.operations where !retained.contains(operation.id) { try remove(db, "ops", key: operation.id.uuidString) }
                let old = Dictionary(uniqueKeysWithValues: previous.operations.map { ($0.id, $0) })
                for operation in next.operations where old[operation.id] != operation {
                    try put(db, "ops", key: operation.id.uuidString, value: StoredOperation(operation, storeText: storeText))
                }
            }
            if next.trash != previous.trash {
                try db.execute(sql: "DELETE FROM trash")
                for entry in next.trash { try put(db, "trash", key: entry.id.uuidString, value: entry) }
            }
            if next.attachments != previous.attachments {
                for path in Set(previous.attachments.keys).union(next.attachments.keys) where previous.attachments[path] != next.attachments[path] {
                    if let value = next.attachments[path] { try put(db, "attachments", key: path, value: value) }
                    else { try remove(db, "attachments", key: path) }
                }
            }
            try put(db, "meta", key: "workspace", value: Meta(identity: next.identity,
                initialized: next.initialized, revision: next.commitSequence, lastSync: next.lastSync))
        }
    }

    private func put<T: Encodable>(_ db: Database, _ table: String, key: String, value: T) throws {
        try db.execute(sql: "INSERT INTO \(table) (record_key,payload) VALUES (?,?) ON CONFLICT(record_key) DO UPDATE SET payload=excluded.payload",
                       arguments: [key, try encoder.encode(value)])
    }

    private func remove(_ db: Database, _ table: String, key: String) throws {
        try db.execute(sql: "DELETE FROM \(table) WHERE record_key = ?", arguments: [key])
    }

    private func records(_ db: Database, _ table: String) throws -> [String: Data] {
        let rows = try Row.fetchCursor(db, sql: "SELECT record_key,payload FROM \(table)")
        var result: [String: Data] = [:]
        while let row = try rows.next() { result[row["record_key"]] = row["payload"] }
        return result
    }
}

private struct StoredConflict: Codable {
    var localBlob: String
    var remoteBlob: String?
    var remoteRevision: String?
    var detectedAt: Date
    var remoteModifiedAt: Date?
    var isOperation: Bool

    init(_ value: WorkspaceConflict, storeText: (String) throws -> String) throws {
        localBlob = try storeText(value.localContents)
        remoteBlob = try value.remoteContents.map(storeText)
        remoteRevision = value.remoteRevision
        detectedAt = value.detectedAt
        remoteModifiedAt = value.remoteModifiedAt
        isOperation = value.isOperation
    }

    func hydrate(path: String, text: (String) throws -> String) throws -> WorkspaceConflict {
        WorkspaceConflict(path: path, localContents: try text(localBlob), remoteContents: try remoteBlob.map(text),
            remoteRevision: remoteRevision, detectedAt: detectedAt, remoteModifiedAt: remoteModifiedAt, isOperation: isOperation)
    }
}

private struct StoredOperation: Codable {
    struct Document: Codable {
        var path: String
        var kind: WorkspaceDocument.Kind
        var blob: String?
        var fileID: UUID?
    }
    var operation: WorkspaceOperation
    var documents: [Document]

    init(_ value: WorkspaceOperation, storeText: (String) throws -> String) throws {
        operation = value
        operation.expected = []
        documents = try value.expected.map { Document(path: $0.path, kind: $0.kind, blob: try $0.kind == .folder ? nil : storeText($0.contents), fileID: $0.fileID) }
    }

    func hydrate(text: (String) throws -> String) throws -> WorkspaceOperation {
        var value = operation
        value.expected = try documents.map {
            var document = LocalStore.document(path: $0.path, contents: try $0.blob.map(text) ?? "", kind: $0.kind)
            document.fileID = $0.fileID
            return document
        }
        return value
    }
}
