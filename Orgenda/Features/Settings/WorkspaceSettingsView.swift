import SwiftUI

struct WorkspaceSettingsView: View {
    let store: WorkspaceStore
    @State private var picker: StoragePickerPresentation?
    @State private var pendingAction: ConnectionAction?
    @State private var isConfirmingReload = false
    @State private var isDisconnecting = false

    private enum ConnectionAction { case change, disconnect }

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
                } footer: {
                    Text("Both versions are kept until you choose how to resolve each conflict.")
                }
            }
            Section("Storage Location") {
                if let connection = store.storageConnection {
                    SettingsRow(icon: connection.provider.symbol, color: OrgendaTheme.accentText,
                                title: connection.provider.title, subtitle: connection.storageSummary)
                        .accessibilityIdentifier("workspace.connection")
                    if let account = connection.accountName {
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
            Section {
                StorageSyncStatusRow(state: store.syncState)
                    .accessibilityIdentifier("workspace.syncStatus")
                if let lastSync = store.lastFileSync {
                    SettingsValueRow(title: String(localized: "Last checked"),
                                     value: lastSync.formatted(date: .abbreviated, time: .shortened))
                }
                SettingsValueRow(title: String(localized: "Org files"),
                                 value: "\(store.documents.filter { $0.kind == .org }.count)")
                if store.pendingUploadCount > 0 {
                    SettingsValueRow(title: String(localized: "Pending uploads"), value: "\(store.pendingUploadCount)")
                }
            } header: {
                Text("Sync Status")
            } footer: {
                Text(storageFooter).fixedSize(horizontal: false, vertical: true)
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
            Section("Connection") {
                if store.syncState == .authenticationRequired, store.storageConnection?.provider.isRemote == true {
                    StorageReconnectAction(store: store)
                }
                if store.isWorkspaceReady {
                    Button(store.isSynchronizing ? "Syncing…" : "Sync Now", systemImage: "arrow.clockwise") {
                        Task { await store.synchronizeFiles() }
                    }
                    .disabled(store.isSynchronizing || isDisconnecting)
                    .accessibilityIdentifier("workspace.refresh")
                }
                Button(store.storageConnection == nil ? "Choose Storage Location" : "Change Storage Location",
                       systemImage: "arrow.left.arrow.right") {
                    if hasPendingEdits { pendingAction = .change }
                    else { picker = StoragePickerPresentation(preservePending: false) }
                }
                .disabled(store.isSynchronizing || isDisconnecting)
                .accessibilityIdentifier("workspace.chooseFolder")
            }
            if store.storageConnection != nil {
                Section {
                    Button("Disconnect", systemImage: "link.badge.minus", role: .destructive) {
                        pendingAction = .disconnect
                    }
                    .disabled(store.isSynchronizing || isDisconnecting)
                    .accessibilityIdentifier("workspace.disconnect")
                } footer: {
                    Text("Disconnects this device. Files at the storage location are kept.")
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
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            if pendingAction == .change {
                Button("Keep Copies and Continue") {
                    picker = StoragePickerPresentation(preservePending: true)
                    pendingAction = nil
                }
            } else {
                Button(hasPendingEdits ? "Keep Copies and Disconnect" : "Disconnect", role: .destructive) {
                    let preserve = hasPendingEdits
                    pendingAction = nil
                    isDisconnecting = true
                    Task {
                        _ = await store.disconnectStorage(preservePending: preserve)
                        isDisconnecting = false
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(hasPendingEdits
                 ? "Unsynced edits will be kept in orgenda → Unsaved Edits before leaving this workspace. They will not be uploaded to the new location."
                 : "Files at this storage location will remain unchanged. You can connect again later.")
        }
        .confirmationDialog("Reload folder versions?", isPresented: $isConfirmingReload, titleVisibility: .visible) {
            Button("Keep Copies and Reload", role: .destructive) {
                Task { await store.adoptFolderVersions() }
            }
        } message: {
            Text("Pending edits will be saved in orgenda → Unsaved Edits before the folder versions replace them in orgenda. Files in the connected folder will not be changed.")
        }
    }

    private var confirmationTitle: LocalizedStringKey {
        pendingAction == .change ? "Change storage location?" : "Disconnect this workspace?"
    }

    private var storageFooter: String {
        if store.storageConnection?.provider == .iCloud {
            return String(localized: "Edits save on this device first, then to the selected folder. iCloud manages cloud uploads.")
        }
        return String(localized: "Edits save on this device first. Downloaded text files remain available offline.")
    }
}

private struct StoragePickerPresentation: Identifiable {
    let id = UUID()
    let preservePending: Bool
}
