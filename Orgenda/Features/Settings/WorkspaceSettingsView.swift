import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSettingsView: View {
    let store: WorkspaceStore
    @State private var isChoosingFolder = false
    @State private var isConfirmingReload = false

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: String(localized: "Workspace"), value: store.workspaceName)
                SettingsValueRow(title: String(localized: "Org files"), value: String(localized: "\(store.documents.filter { $0.kind == .org }.count)"))
                SettingsValueRow(title: String(localized: "Location"), value: store.workspaceLocation)
                if let lastSync = store.lastFileSync {
                    SettingsValueRow(title: String(localized: "Last checked"), value: lastSync.formatted(date: .omitted, time: .standard))
                }
                if store.pendingFileCount > 0 {
                    SettingsValueRow(title: String(localized: "Pending saves"), value: "\(store.pendingFileCount)")
                }
            } header: {
                Text("Current Workspace")
            } footer: {
                Text(store.storageDescription + String(localized: " Choose a folder in Files to use iCloud Drive or another file provider. Cloud transfer is managed by the provider."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Choose Folder…", systemImage: "folder.badge.plus") { isChoosingFolder = true }
                    .disabled(store.isSynchronizing || store.pendingFileCount > 0)
                    .accessibilityIdentifier("workspace.chooseFolder")
                if store.isFolderConnected {
                    Button(store.isSynchronizing ? "Checking…" : "Save & Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.synchronizeFiles() }
                    }
                    .disabled(store.isSynchronizing)
                    .accessibilityIdentifier("workspace.refresh")
                }
            }
            if let error = store.fileSyncError {
                Section("File changes need attention") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                    Text("Conflicting source files are left untouched. You can keep copies of pending edits in orgenda → Unsaved Edits, then reload the folder versions.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if store.pendingFileCount > 0 {
                        Button("Use Folder Versions…", systemImage: "arrow.down.document") {
                            isConfirmingReload = true
                        }
                        .disabled(store.isSynchronizing)
                        .accessibilityIdentifier("workspace.resolveConflict")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Workspace & Sync")
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await store.connectFolder(url) }
            case .failure(let error):
                store.fileSyncError = error.localizedDescription
            }
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
