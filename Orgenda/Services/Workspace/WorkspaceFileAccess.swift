import Foundation

/// Files and durable cloud sessions expose the same application-facing boundary.
protocol WorkspaceFileAccess: Sendable {
    var recoveryIdentity: String { get }
    func load() async throws -> [WorkspaceDocument]
    func write(path: String, contents: String, expectedContents: String?) async throws
    func readImageData(path: String, maxBytes: Int) async throws -> Data
    func move(path: String, to destination: String, expected: [WorkspaceDocument]) async throws
    func trash(document: WorkspaceDocument, expected: [WorkspaceDocument]) async throws -> WorkspaceTrashEntry
    func restore(_ entry: WorkspaceTrashEntry) async throws
    func deletedEntries() async throws -> [WorkspaceTrashEntry]
}

extension WorkspaceFileStore: WorkspaceFileAccess {}
