import Foundation
import SQLite3

/// Owned exclusively by LocalStore. Immutable blobs are written before COMMIT;
/// COMMIT is the only point at which new drafts or operations become visible.
final class WorkspaceStateDatabase {
    private var handle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open_v2(directory.appendingPathComponent("state.sqlite").path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw StorageError.configuration("The workspace state database could not be opened.")
        }
        do {
            sqlite3_busy_timeout(handle, 2500)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS files (file_id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, remote_path TEXT NOT NULL UNIQUE, folded_path TEXT NOT NULL UNIQUE, payload BLOB)")
            try execute("CREATE TABLE IF NOT EXISTS drafts (record_key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
            for table in ["conflicts", "ops", "trash", "attachments", "meta"] {
                try execute("CREATE TABLE IF NOT EXISTS \(table) (record_key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
            }
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }

    private struct Meta: Codable {
        var identity: String
        var initialized: Bool
        var revision: UInt64
        var lastSync: Date?
    }

    func load(identity: String, text: (String) throws -> String) throws -> WorkspaceState {
        var state = WorkspaceState(identity: identity)
        if let bytes = try records("meta")["workspace"] {
            let saved = try decoder.decode(Meta.self, from: bytes)
            guard saved.identity == identity else { throw StorageError.configuration("The workspace cache belongs to a different connection.") }
            state.initialized = saved.initialized
            state.commitSequence = saved.revision
            state.lastSync = saved.lastSync
        }
        var pathsByID: [String: String] = [:]
        try query("SELECT file_id, remote_path, payload FROM files") { statement in
            let id = String(cString: sqlite3_column_text(statement, 0))
            let path = String(cString: sqlite3_column_text(statement, 1))
            pathsByID[id] = path
            if sqlite3_column_type(statement, 2) != SQLITE_NULL {
                state.entries[path] = try decoder.decode(WorkspaceFileRecord.self, from: bytes(statement, column: 2))
            }
        }
        for (id, bytes) in try records("drafts") {
            guard let path = pathsByID[id] else { throw StorageError.invalidResponse }
            state.pending[path] = try decoder.decode(WorkspaceDraft.self, from: bytes)
        }
        for (key, bytes) in try records("conflicts") {
            let path: String
            if key.hasPrefix("path:") { path = String(key.dropFirst(5)) }
            else if let associated = pathsByID[key] { path = associated }
            else { throw StorageError.invalidResponse }
            state.conflicts[path] = try decoder.decode(StoredConflict.self, from: bytes).hydrate(path: path, text: text)
        }
        state.operations = try records("ops").values.map {
            try decoder.decode(StoredOperation.self, from: $0).hydrate(text: text)
        }.sorted { $0.sequence < $1.sequence }
        state.trash = try records("trash").values.map { try decoder.decode(WorkspaceTrashEntry.self, from: $0) }
            .sorted { $0.deletedAt > $1.deletedAt }
        state.attachments = try records("attachments").mapValues { try decoder.decode(CachedWorkspaceAttachment.self, from: $0) }
        return state
    }

    /// With explicit paths, ordinary saves touch only those rows and one small
    /// metadata row. Bulk refreshes compare metadata without re-encoding text.
    func save(_ next: WorkspaceState, previous: WorkspaceState, paths: Set<String>?,
              storeText: (String) throws -> String) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            if let saved = try records("meta")["workspace"] {
                let current = try decoder.decode(Meta.self, from: saved)
                guard current.revision == previous.commitSequence else {
                    throw StorageError.configuration("Another local session changed this workspace. Reopen it before saving.")
                }
            }
            let touched = paths ?? Set(previous.entries.keys).union(next.entries.keys)
                .union(previous.pending.keys).union(next.pending.keys)
            for path in touched where next.entries[path] == nil && next.pending[path] == nil {
                try run("DELETE FROM files WHERE remote_path = ?", strings: [path])
                if let old = previous.pending[path] { try remove("drafts", key: old.fileID.uuidString) }
            }
            // Free logical destinations before reassigning any paths. This
            // handles an aborted move restoring its source while retaining a
            // draft at the intended destination, independent of Set order.
            for path in touched {
                guard next.entries[path] != nil || next.pending[path] != nil,
                      LocalStore.projectedPath(path, in: next) != LocalStore.projectedPath(path, in: previous),
                      let id = previous.entries[path]?.fileID ?? previous.pending[path]?.fileID else { continue }
                let temporary = ".orgenda-state-" + UUID().uuidString
                try run("UPDATE files SET path = ?, folded_path = ? WHERE file_id = ?", strings: [temporary, temporary, id.uuidString])
            }
            for path in touched {
                let entry = next.entries[path]
                let pending = next.pending[path]
                guard let id = entry?.fileID ?? pending?.fileID else { continue }
                let localPath = LocalStore.projectedPath(path, in: next)
                let previousPath = LocalStore.projectedPath(path, in: previous)
                if entry != previous.entries[path] || pending?.fileID != previous.pending[path]?.fileID || localPath != previousPath {
                    let payload = try entry.map { try encoder.encode($0) }
                    try run("DELETE FROM files WHERE remote_path = ? AND file_id <> ?", strings: [path, id.uuidString])
                    try run("INSERT INTO files (file_id,path,remote_path,folded_path,payload) VALUES (?,?,?,?,?) ON CONFLICT(file_id) DO UPDATE SET path=excluded.path,remote_path=excluded.remote_path,folded_path=excluded.folded_path,payload=excluded.payload",
                        strings: [id.uuidString, localPath, path, LocalStore.fold(localPath)], payload: payload)
                }
                if pending != previous.pending[path] {
                    if let pending { try put("drafts", key: id.uuidString, value: pending) }
                    else { try remove("drafts", key: id.uuidString) }
                }
            }
            // Remove drafts for deleted files; moved IDs retain their drafts.
            if paths == nil {
                let retained = Set(next.pending.values.map(\.fileID))
                for draft in previous.pending.values where !retained.contains(draft.fileID) { try remove("drafts", key: draft.fileID.uuidString) }
            }
            func conflictKey(_ state: WorkspaceState, path: String) -> String {
                (state.entries[path]?.fileID ?? state.pending[path]?.fileID)?.uuidString ?? "path:" + path
            }
            let conflictPaths = paths ?? Set(previous.conflicts.keys).union(next.conflicts.keys)
            let retainedConflicts = Set(next.conflicts.keys.map { conflictKey(next, path: $0) })
            let oldConflicts = Dictionary(previous.conflicts.map { (conflictKey(previous, path: $0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
            for path in conflictPaths {
                let oldKey = conflictKey(previous, path: path), newKey = conflictKey(next, path: path)
                if previous.conflicts[path] != nil && !retainedConflicts.contains(oldKey) { try remove("conflicts", key: oldKey) }
                if let conflict = next.conflicts[path] {
                    // Renames update the associated files row; the conflict
                    // payload has no duplicated mutable path.
                    var old = oldConflicts[newKey]
                    old?.path = path
                    if old != conflict {
                        try put("conflicts", key: newKey, value: StoredConflict(conflict, storeText: storeText))
                    }
                }
            }
            if paths == nil && next.operations != previous.operations {
                let retained = Set(next.operations.map(\.id))
                for operation in previous.operations where !retained.contains(operation.id) { try remove("ops", key: operation.id.uuidString) }
                let old = Dictionary(uniqueKeysWithValues: previous.operations.map { ($0.id, $0) })
                for operation in next.operations where old[operation.id] != operation {
                    try put("ops", key: operation.id.uuidString, value: StoredOperation(operation, storeText: storeText))
                }
            }
            if next.trash != previous.trash {
                try execute("DELETE FROM trash")
                for entry in next.trash { try put("trash", key: entry.id.uuidString, value: entry) }
            }
            if next.attachments != previous.attachments {
                for path in Set(previous.attachments.keys).union(next.attachments.keys) where previous.attachments[path] != next.attachments[path] {
                    if let value = next.attachments[path] { try put("attachments", key: path, value: value) }
                    else { try remove("attachments", key: path) }
                }
            }
            try put("meta", key: "workspace", value: Meta(identity: next.identity,
                initialized: next.initialized, revision: next.commitSequence, lastSync: next.lastSync))
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func put<T: Encodable>(_ table: String, key: String, value: T) throws {
        let data = try encoder.encode(value)
        try run("INSERT INTO \(table) (record_key,payload) VALUES (?,?) ON CONFLICT(record_key) DO UPDATE SET payload=excluded.payload", strings: [key], payload: data)
    }

    private func remove(_ table: String, key: String) throws { try run("DELETE FROM \(table) WHERE record_key = ?", strings: [key]) }

    private func records(_ table: String) throws -> [String: Data] {
        var result: [String: Data] = [:]
        try query("SELECT record_key,payload FROM \(table)") { statement in
            result[String(cString: sqlite3_column_text(statement, 0))] = bytes(statement, column: 1)
        }
        return result
    }

    private func bytes(_ statement: OpaquePointer, column: Int32) -> Data {
        Data(bytes: sqlite3_column_blob(statement, column), count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func run(_ sql: String, strings: [String], payload: Data? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in strings.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else { throw failure() }
        }
        if let payload {
            let result = payload.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(strings.count + 1), $0.baseAddress, Int32($0.count), transient) }
            guard result == SQLITE_OK else { throw failure() }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    private func query(_ sql: String, row: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw failure() }
            try row(statement)
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func failure() -> StorageError {
        .configuration("Workspace database: " + String(cString: sqlite3_errmsg(handle)))
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
