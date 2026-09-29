import SwiftUI

struct StorageSyncView: View {
    let store: WorkspaceStore

    var body: some View {
        List {
            Section {
                StorageSyncStatusRow(state: store.syncState)
                    .accessibilityIdentifier("storage.sync.state")
                if let lastSync = store.lastFileSync {
                    SettingsValueRow(title: String(localized: "Last checked"),
                                     value: lastSync.formatted(date: .abbreviated, time: .shortened))
                }
                SettingsValueRow(title: String(localized: "Pending uploads"), value: "\(store.pendingUploadCount)")
            } footer: {
                Text("Downloaded text files are available offline. Attachments download when you open them.")
            }
            if !store.syncConflicts.isEmpty {
                Section {
                    NavigationLink {
                        StorageConflictsView(store: store)
                    } label: {
                        Label("Resolve Conflicts", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("storage.sync.conflicts")
                } footer: {
                    Text("Both versions are kept until you choose how to resolve each conflict.")
                }
            }
            if let connection = store.storageConnection {
                Section("Storage Location") {
                    SettingsValueRow(title: String(localized: "Service"), value: connection.provider.title)
                    if let account = connection.accountName {
                        SettingsValueRow(title: String(localized: "Account"), value: account)
                    }
                    SettingsValueRow(title: String(localized: "Workspace"), value: connection.displayName)
                    if connection.provider == .webDAV, let endpoint = connection.endpoint {
                        SettingsValueRow(title: String(localized: "Server Address"), value: endpoint.absoluteString)
                    }
                }
            }
            if let error = store.fileSyncError {
                Section("File changes need attention") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                }
            }
            if store.isWorkspaceReady {
                Section {
                    if store.syncState == .authenticationRequired, store.storageConnection?.provider.isRemote == true {
                        StorageReconnectAction(store: store)
                    }
                    Button(store.isSynchronizing ? "Syncing…" : "Sync Now", systemImage: "arrow.clockwise") {
                        Task { await store.synchronizeFiles() }
                    }
                    .disabled(store.isSynchronizing)
                    .accessibilityIdentifier("storage.sync.refresh")
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(OrgendaTheme.accentText)
        .navigationTitle("Sync Status")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
