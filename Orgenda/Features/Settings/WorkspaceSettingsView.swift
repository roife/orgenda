import SwiftUI

struct WorkspaceSettingsView: View {
    let store: WorkspaceStore
    @State private var picker: StoragePickerPresentation?
    @State private var isConfirmingDisconnect = false
    @State private var isConfirmingReload = false
    @State private var isDisconnecting = false

    private var hasPendingEdits: Bool {
        store.hasPendingStorageChanges
    }

    var body: some View {
        List {
            if !store.syncConflicts.isEmpty {
                Section {
                    NavigationLink {
                        StorageConflictsView(store: store)
                    } label: {
                        Label("Resolve Conflicts", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("workspace.resolveConflict")
                }
            }
            Section("Storage Location") {
                if let connection = store.storageConnection {
                    SettingsRow(icon: connection.provider.symbol, color: OrgendaTheme.accentText,
                                title: connection.providerSummary, subtitle: connection.storageSummary,
                                iconAsset: connection.provider.iconAsset)
                        .accessibilityValue(connection.provider.title)
                        .accessibilityIdentifier("workspace.connection")
                    if connection.provider == .webDAV, let account = connection.accountName {
                        SettingsValueRow(title: String(localized: "Account"), value: account)
                    }
                    if connection.provider == .webDAV, let endpoint = connection.endpoint {
                        SettingsValueRow(title: String(localized: "Server Address"), value: endpoint.absoluteString)
                    }
                } else {
                    SettingsRow(icon: "folder", color: OrgendaTheme.accentText,
                                title: store.workspaceName, subtitle: store.workspaceLocation)
                }
            }
            Section("Sync Status") {
                StorageSyncSummary(
                    state: store.syncState,
                    lastChecked: store.lastFileSync,
                    orgFileCount: store.documents.filter { $0.kind == .org }.count,
                    pendingUploadCount: store.pendingUploadCount
                )
            }
            if let error = store.fileSyncError {
                Section("File changes need attention") {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("workspace.error")
                    if store.syncConflicts.isEmpty && store.pendingFileCount > 0 && store.storageConnection?.provider.isRemote != true {
                        Button("Use Folder Versions…", systemImage: "arrow.down.document") {
                            isConfirmingReload = true
                        }
                        .disabled(store.isSynchronizing)
                        .accessibilityIdentifier("workspace.resolveConflict")
                    }
                }
            }
            Section {
                if let connection = store.storageConnection, connection.provider.isRemote,
                   store.syncState == .authenticationRequired || (connection.provider.usesEmailAccount && connection.emailAddress == nil) {
                    StorageReconnectAction(store: store)
                }
                if store.isWorkspaceReady {
                    Button(LocalizedStringKey(store.isSynchronizing ? "Syncing…" : "Sync Now"), systemImage: "arrow.clockwise") {
                        Task { await store.synchronizeFiles() }
                    }
                    .disabled(store.isSynchronizing || isDisconnecting)
                    .accessibilityIdentifier("workspace.refresh")
                }
                Button(LocalizedStringKey(store.storageConnection == nil ? "Choose Storage Location" : "Change Storage Location"),
                       systemImage: "arrow.left.arrow.right") {
                    picker = StoragePickerPresentation(preservePending: hasPendingEdits)
                }
                .disabled(store.isSynchronizing || isDisconnecting)
                .accessibilityIdentifier("workspace.chooseFolder")
            } header: {
                Text("Connection")
            }
            if store.storageConnection != nil {
                Section {
                    Button("Disconnect", systemImage: "link.badge.minus", role: .destructive) {
                        isConfirmingDisconnect = true
                    }
                    .disabled(store.isSynchronizing || isDisconnecting)
                    .accessibilityIdentifier("workspace.disconnect")
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(OrgendaTheme.accentText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Workspace & Sync")
        .presentationSizing(.page)
        .sheet(item: $picker) { presentation in
            StorageProviderPicker(store: store, preservePending: presentation.preservePending)
        }
        .confirmationDialog("Disconnect this workspace?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
            Button(LocalizedStringKey(hasPendingEdits ? "Keep Copies and Disconnect" : "Disconnect"), role: .destructive) {
                let preserve = hasPendingEdits
                isConfirmingDisconnect = false
                isDisconnecting = true
                Task {
                    _ = await store.disconnectStorage(preservePending: preserve)
                    isDisconnecting = false
                }
            }
            Button("Cancel", role: .cancel) { isConfirmingDisconnect = false }
        } message: {
            Text(LocalizedStringKey(hasPendingEdits
                 ? "Unsynced edits will be kept in orgenda → Unsaved Edits before leaving this workspace. They will not be uploaded to the new location."
                 : "Files at this storage location will remain unchanged. You can connect again later."))
        }
        .confirmationDialog("Reload folder versions?", isPresented: $isConfirmingReload, titleVisibility: .visible) {
            Button("Keep Copies and Reload", role: .destructive) {
                Task { await store.adoptFolderVersions() }
            }
        } message: {
            Text("Pending edits will be saved in orgenda → Unsaved Edits before the folder versions replace them in orgenda. Files in the connected folder will not be changed.")
        }
    }
}

private struct StoragePickerPresentation: Identifiable {
    let id = UUID()
    let preservePending: Bool
}
