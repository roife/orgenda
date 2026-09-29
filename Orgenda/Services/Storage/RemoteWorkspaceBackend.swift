import Foundation

struct RemoteFile: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var path: String
    var isDirectory: Bool
    var revision: String?
    var modifiedAt: Date? = nil
    var size: Int64? = nil
}

struct RemoteScan: Sendable {
    var files: [RemoteFile]
    var deletedIDs: Set<String> = []
    var cursor: String? = nil
    var isFullSnapshot: Bool = true
}

struct RemoteDownload: Sendable {
    var file: RemoteFile
    var data: Data
}

/// All paths are relative to the persisted root. A scan must throw on any
/// partial enumeration; upload and move must never silently overwrite.
protocol RemoteWorkspaceBackend: Sendable {
    func scan(cursor: String?) async throws -> RemoteScan
    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload
    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile
    func createDirectory(path: String) async throws -> RemoteFile
    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile
}

enum StorageError: Error, LocalizedError, Equatable {
    case authenticationRequired, offline, rootUnavailable, conflict(String), unsafePath(String)
    case unsupported(String), invalidResponse, http(Int), tooLarge, configuration(String), busy, throttled(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: String(localized: "Sign in again to sync. Your edits are saved on this device.")
        case .offline: String(localized: "Connect to the internet to sync. Your edits are saved on this device.")
        case .rootUnavailable: String(localized: "The storage folder is unavailable. Reconnect it; your local edits are safe.")
        case .conflict(let path): String(localized: "\(path) changed elsewhere. Both versions have been kept.")
        case .unsafePath(let path): String(localized: "The storage path is invalid: \(path)")
        case .unsupported(let message), .configuration(let message): message
        case .invalidResponse: String(localized: "The storage service returned an invalid response.")
        case .http(let status): String(localized: "The storage service returned HTTP \(status). Try again later.")
        case .tooLarge: String(localized: "The file exceeds the download size limit.")
        case .busy: String(localized: "Finish syncing or resolve conflicts before moving files.")
        case .throttled: String(localized: "The storage service is busy. Sync will retry automatically.")
        }
    }

    static func validate(path: String, allowEmpty: Bool = false) throws {
        if allowEmpty && path.isEmpty { return }
        guard !path.isEmpty, !path.contains("\0"), !path.contains("\\"),
              path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw Self.unsafePath(path)
        }
    }
}

struct PreparedRemoteConnection: Sendable {
    var connection: StorageConnection
    var backend: any RemoteWorkspaceBackend
}
