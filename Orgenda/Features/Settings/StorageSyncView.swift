import SwiftUI

struct StorageSyncStatusRow: View {
    let state: WorkspaceSyncState

    var body: some View {
        HStack(spacing: 12) {
            if state == .saving || state == .syncing {
                ProgressView().accessibilityHidden(true)
            } else {
                Image(systemName: state.storageSymbol)
                    .foregroundStyle(state.storageColor)
                    .accessibilityHidden(true)
            }
            Text(state.title)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

extension WorkspaceSyncState {
    var storageSymbol: String {
        switch self {
        case .idle: "info.circle"
        case .saving, .syncing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .pending: "arrow.up.circle"
        case .synced, .folderUpdated: "checkmark.circle.fill"
        case .offline: "wifi.slash"
        case .authenticationRequired: "person.crop.circle.badge.exclamationmark"
        case .conflict, .failed: "exclamationmark.triangle.fill"
        }
    }

    var storageColor: Color {
        if needsAttention { return .red }
        switch self {
        case .synced, .folderUpdated: return .green
        case .idle, .offline: return .secondary
        default: return OrgendaTheme.accentText
        }
    }
}

extension StorageConnection {
    var storageSummary: String {
        if provider == .webDAV, let endpoint {
            return (endpoint.host ?? "WebDAV") + endpoint.path
        }
        if let accountName { return accountName + " · " + displayName }
        return displayName
    }
}
