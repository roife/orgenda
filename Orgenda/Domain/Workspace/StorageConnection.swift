import Foundation

enum StorageProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case local, iCloud, oneDrive, googleDrive, dropbox, webDAV

    var id: String { rawValue }
    var isRemote: Bool { self != .local && self != .iCloud }
    var usesEmailAccount: Bool { self == .oneDrive || self == .googleDrive || self == .dropbox }
    var title: String {
        switch self {
        case .local: String(localized: "Files")
        case .iCloud: "iCloud Drive"
        case .oneDrive: "OneDrive"
        case .googleDrive: "Google Drive"
        case .dropbox: "Dropbox"
        case .webDAV: "WebDAV"
        }
    }
    var symbol: String {
        switch self {
        case .local: "folder.fill"
        case .iCloud: "icloud.fill"
        case .oneDrive: "cloud.fill"
        case .googleDrive: "externaldrive.fill"
        case .dropbox: "shippingbox.fill"
        case .webDAV: "server.rack"
        }
    }
}

/// Only this descriptor is stored in preferences. Credentials live in Keychain.
struct StorageConnection: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var provider: StorageProvider
    var displayName: String
    var accountID: String? = nil
    var accountName: String? = nil
    var accountEmail: String? = nil
    var rootID: String
    var endpoint: URL? = nil
    var credentialKey: String? = nil
    var bookmark: Data? = nil

    var identity: String { "\(provider.rawValue)|\(accountID ?? "")|\(rootID)|\(id.uuidString)" }

    var emailAddress: String? {
        guard provider.usesEmailAccount else { return nil }
        // Older Google Drive and Dropbox connections stored the email in accountName.
        let legacyEmail = provider == .googleDrive || provider == .dropbox ? accountName : nil
        return [accountEmail, legacyEmail].compactMap(Self.normalizedEmail).first
    }

    static func normalizedEmail(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return value
    }
}

enum WorkspaceSyncState: Equatable, Sendable {
    case idle, saving, pending(Int), syncing, synced, folderUpdated, offline, authenticationRequired
    case conflict(Int), failed(String)

    var title: String {
        switch self {
        case .idle: String(localized: "Workspace not connected")
        case .saving: String(localized: "Saving on this device…")
        case .pending(let count): String(localized: "Saved on this device · \(count) pending")
        case .syncing: String(localized: "Syncing…")
        case .synced: String(localized: "Up to date")
        case .folderUpdated: String(localized: "Saved to folder")
        case .offline: String(localized: "Offline · Changes stay on this device")
        case .authenticationRequired: String(localized: "Sign in again to sync")
        case .conflict(let count): String(localized: "\(count) conflicts need attention")
        case .failed(let message): message
        }
    }
    var needsAttention: Bool {
        switch self {
        case .authenticationRequired, .conflict, .failed: true
        default: false
        }
    }
}

struct WorkspaceConflict: Codable, Equatable, Sendable, Identifiable {
    var id: String { path }
    var path: String
    var localContents: String
    var remoteContents: String?
    var remoteRevision: String?
    var detectedAt: Date
    var remoteModifiedAt: Date?
}

enum WorkspaceConflictResolution: String, CaseIterable, Sendable {
    case keepBoth, useLocal, useRemote
}

struct WorkspaceSessionSnapshot: Sendable {
    var documents: [WorkspaceDocument]
    var pendingPaths: Set<String>
    var conflicts: [WorkspaceConflict]
    var lastSync: Date?
    var hasPendingOperation: Bool = false
    var revision: UInt64 = 0
}

struct WebDAVConfiguration: Sendable {
    var serverURL: String
    var username: String
    var password: String
    var directory: String = "/Orgenda"
}
