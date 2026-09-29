import Foundation

/// The manifest is the commit point. Blobs are immutable, so an interrupted
/// save leaves either the previous complete draft or the next complete draft.
struct SyncManifest: Codable, Sendable {
    var version = 1
    var commitSequence: UInt64? = nil
    var identity: String
    var initialized = false
    var entries: [String: SyncManifestEntry] = [:]
    var pending: [String: SyncPendingWrite] = [:]
    var conflicts: [String: WorkspaceConflict] = [:]
    var attachments: [String: SyncCachedAttachment] = [:]
    var trash: [WorkspaceTrashEntry] = []
    var fileOperation: SyncFileOperation?
    var cursor: String?
    var lastSync: Date?
}

struct SyncManifestEntry: Codable, Sendable {
    var file: RemoteFile
    var blob: String?
}

struct SyncPendingWrite: Codable, Sendable {
    var blob: String
    var base: RemoteFile?
    var baseBlob: String?
    var operationID: UUID = UUID()
    var generation: UUID = UUID()
    // Optional for compatibility with already-committed version-1 manifests.
    // A stale UI save must not become a new unconditional upload on retry.
    var requiresResolution: Bool? = nil
}

struct SyncCachedAttachment: Codable, Sendable {
    var blob: String
    var revision: String?
    var remoteID: String?
}

/// Only online file actions enter this journal. It records uncertain network
/// outcomes; it is not an offline queue of filesystem gestures.
struct SyncFileOperation: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case move, trash, restore, refile }
    var id = UUID()
    var kind: Kind
    var sourcePath: String
    var destinationPath: String
    var source: RemoteFile?
    var expected: [WorkspaceDocument]
    var trashEntry: WorkspaceTrashEntry?
    var destinationContents: String?
    var sourceContents: String?
    var expectedDestination: String?
    var destinationCommitted = false
}
