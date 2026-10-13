import SwiftUI

struct StorageSyncSummary: View {
    @ScaledMetric(relativeTo: .body) private var iconWidth = 20.0
    let state: WorkspaceSyncState
    let lastChecked: Date?
    let orgFileCount: Int
    let pendingUploadCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Keep the symbol's baseline when ProgressView appears; its
                // intrinsic baseline otherwise changes the entire row height.
                Image(systemName: "checkmark.circle.fill")
                    .hidden()
                    .frame(width: iconWidth)
                    .overlay {
                        if state == .saving || state == .syncing {
                            ProgressView()
                        } else {
                            Image(systemName: state.storageSymbol)
                                .foregroundStyle(state.storageColor)
                        }
                    }
                    .accessibilityHidden(true)
                Text(state.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workspace.syncStatus")

            VStack(alignment: .leading, spacing: 8) {
                if let lastChecked {
                    LabeledContent("Last checked",
                                   value: lastChecked.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Org files", value: orgFileCount.formatted())
                if pendingUploadCount > 0 {
                    LabeledContent("Pending uploads", value: pendingUploadCount.formatted())
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

#Preview("Sync summaries") {
    List {
        Section("Sync Status") {
            StorageSyncSummary(state: .folderUpdated,
                               lastChecked: Date(timeIntervalSince1970: 1_791_004_020),
                               orgFileCount: 0, pendingUploadCount: 0)
        }
        Section("Sync Status") {
            StorageSyncSummary(state: .syncing, lastChecked: nil,
                               orgFileCount: 24, pendingUploadCount: 3)
        }
        Section("Sync Status") {
            StorageSyncSummary(state: .conflict(1),
                               lastChecked: Date(timeIntervalSince1970: 1_791_004_020),
                               orgFileCount: 24, pendingUploadCount: 1)
        }
    }
    .listStyle(.insetGrouped)
}

extension WorkspaceSyncState {
    var storageSymbol: String {
        switch self {
        case .idle: "info.circle"
        case .saving, .syncing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .pending: "arrow.up.circle"
        case .synced, .folderUpdated: "checkmark.circle.fill"
        case .offline: "wifi.slash"
        case .authenticationRequired: "key.fill"
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
        return displayName
    }
}
