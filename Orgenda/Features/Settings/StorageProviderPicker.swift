import SwiftUI
import UniformTypeIdentifiers

struct StorageProviderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let preservePending: Bool
    @State private var isChoosingFolder = false
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var pendingFolder: URL?

    private var shouldPreservePending: Bool { preservePending || store.hasPendingStorageChanges }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        connectionError = nil
                        isChoosingFolder = true
                    } label: {
                        HStack(spacing: OrgendaSpacing.rowInset) {
                            providerRow(.local)
                            if isConnecting {
                                ProgressView().accessibilityLabel("Connecting…")
                            }
                        }
                    }
                    .accessibilityIdentifier("storage.provider.local")
                    NavigationLink {
                        StorageWebDAVView(store: store, preservePending: shouldPreservePending)
                    } label: {
                        providerRow(.webDAV)
                    }
                    .accessibilityIdentifier("storage.provider.webDAV")
                }
                if let connectionError {
                    Section("Could Not Connect") {
                        Text(connectionError)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("storage.connectionError")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .disabled(isConnecting)
            .navigationTitle("Choose Storage Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isConnecting || store.isSynchronizing)
                        .accessibilityIdentifier("storage.cancel")
                }
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                handleFolderSelection(result)
            }
            .confirmationDialog("Change storage location?", item: $pendingFolder, titleVisibility: .visible) { folder in
                Button(LocalizedStringKey(shouldPreservePending ? "Keep Copies and Change Location" : "Change Location")) {
                    pendingFolder = nil
                    connect(folder)
                }
                Button("Cancel", role: .cancel) { pendingFolder = nil }
            } message: { folder in
                if let current = store.storageConnection {
                    Text(StorageLocationChange.message(current: current, destination: folder.path,
                                                       preservePending: shouldPreservePending))
                }
            }
            .onChange(of: store.storageConnection?.id) { _, current in
                if current != nil { dismiss() }
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.large])
        .interactiveDismissDisabled(isConnecting || store.isSynchronizing)
    }

    private func providerRow(_ provider: StorageProvider) -> some View {
        SettingsRow(icon: provider.symbol, color: provider == .webDAV ? OrgendaTheme.neutral : OrgendaTheme.accent,
                    title: provider.title, subtitle: "")
    }

    private func confirmOrConnect(_ url: URL) {
        if let current = store.storageConnection {
            if !current.provider.isRemote,
               current.rootID == url.resolvingSymlinksInPath().standardizedFileURL.path {
                connect(url)
            } else {
                pendingFolder = url
            }
        } else {
            connect(url)
        }
    }

    private func connect(_ url: URL) {
        let preserve = shouldPreservePending
        isConnecting = true
        Task {
            let previous = store.storageConnection?.id
            await store.connectFolder(url, preservePending: preserve)
            isConnecting = false
            let selectedRoot = url.resolvingSymlinksInPath().standardizedFileURL.path
            let isCurrentFolder = store.storageConnection?.provider.isRemote == false
                && store.storageConnection?.rootID == selectedRoot && store.fileSyncError == nil
            if store.storageConnection?.id != previous || isCurrentFolder { dismiss() }
            else { connectionError = store.fileSyncError }
        }
    }

    private func handleFolderSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            confirmOrConnect(url)
        case .failure(let error):
            let error = error as NSError
            guard !(error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) else { return }
            connectionError = error.localizedDescription
        }
    }
}

/// Shared wording keeps the final decision consistent for Files and WebDAV connections.
enum StorageLocationChange {
    static func message(current: StorageConnection, destination: String, preservePending: Bool) -> String {
        let location = current.provider.isRemote ? current.storageSummary : current.rootID
        let currentLocation = "\(current.provider.title) · \(location)"
        var message = String(localized: "Current location: \(currentLocation)\nNew location: \(destination)")
        message += "\n\n" + String(localized: "Orgenda will open the workspace at the new location. Existing files stay where they are and will not be moved or copied.")
        if preservePending {
            message += "\n\n" + String(localized: "Unsynced edits will be kept in orgenda → Unsaved Edits before leaving this workspace. They will not be uploaded to the new location.")
        }
        return message
    }
}
