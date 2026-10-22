import Foundation

/// In-memory state owned by LocalStore. SQLite transactions are the commit
/// point; text in conflicts and operations is persisted as blob references.
struct WorkspaceState: Sendable {
    var commitSequence: UInt64 = 0
    var identity: String
    var initialized = false
    var entries: [String: WorkspaceFileRecord] = [:]
    var pending: [String: WorkspaceDraft] = [:]
    var conflicts: [String: WorkspaceConflict] = [:]
    var attachments: [String: CachedWorkspaceAttachment] = [:]
    var trash: [WorkspaceTrashEntry] = []
    var operations: [WorkspaceOperation] = []
    var lastSync: Date?
}

struct WorkspaceFileRecord: Codable, Equatable, Sendable {
    var file: RemoteFile
    var blob: String?
    var fileID = UUID()
}

struct WorkspaceDraft: Codable, Equatable, Sendable {
    var blob: String
    var base: RemoteFile?
    var baseBlob: String?
    var generation: UUID = UUID()
    // A stale UI save must not become a new unconditional upload on retry.
    var requiresResolution = false
    var fileID = UUID()
    var destinationFileID: UUID?
    var requiredDestinationBlob: String?
}

struct CachedWorkspaceAttachment: Codable, Equatable, Sendable {
    var blob: String
    var revision: String?
    var remoteID: String?
}

/// Ordered durable local intent, replayed with remote preconditions.
struct WorkspaceOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case move, trash, restore }
    var kind: Kind
    var sourcePath: String
    var destinationPath: String
    var source: RemoteFile?
    var expected: [WorkspaceDocument]
    var trashEntry: WorkspaceTrashEntry?
    var id = UUID()
    var sequence: UInt64 = 0
}
