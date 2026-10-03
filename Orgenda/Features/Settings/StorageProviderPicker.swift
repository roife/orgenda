import SwiftUI
import UniformTypeIdentifiers

struct StorageProviderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let preservePending: Bool
    @State private var isChoosingFolder = false
    @State private var connectingProvider: StorageProvider?
    @State private var connectionError: String?
    @State private var pendingConnection: PendingConnection?

    private enum PendingConnection {
        case folder(URL)
        case cloud(StorageProvider)

        var destination: String {
            switch self {
            case .folder(let url): url.path
            case .cloud(let provider):
                String(localized: "\(provider.title) · Orgenda folder in the account you choose next")
            }
        }
    }

    private var shouldPreservePending: Bool { preservePending || store.hasPendingStorageChanges }

    var body: some View {
        NavigationStack {
            List {
                Section("Cloud Storage") {
                    providerButton(.iCloud)
                    providerButton(.oneDrive)
                    providerButton(.googleDrive)
                    providerButton(.dropbox)
                    NavigationLink {
                        StorageWebDAVView(store: store, preservePending: shouldPreservePending)
                    } label: {
                        providerRow(.webDAV)
                    }
                    .accessibilityIdentifier("storage.provider.webDAV")
                }
                Section {
                    providerButton(.local)
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
            .disabled(connectingProvider != nil)
            .navigationTitle("Choose Storage Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(connectingProvider != nil || store.isSynchronizing)
                        .accessibilityIdentifier("storage.cancel")
                }
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                handleFolderSelection(result)
            }
            .confirmationDialog("Change storage location?", isPresented: Binding(
                get: { pendingConnection != nil },
                set: { if !$0 { pendingConnection = nil } }
            ), titleVisibility: .visible, presenting: pendingConnection) { selection in
                Button(LocalizedStringKey(shouldPreservePending ? "Keep Copies and Change Location" : "Change Location")) {
                    pendingConnection = nil
                    connect(selection)
                }
                Button("Cancel", role: .cancel) { pendingConnection = nil }
            } message: { selection in
                if let current = store.storageConnection {
                    Text(StorageLocationChange.message(current: current, destination: selection.destination,
                                                       preservePending: shouldPreservePending))
                }
            }
            .onChange(of: store.storageConnection?.id) { _, current in
                if current != nil { dismiss() }
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.large])
        .interactiveDismissDisabled(connectingProvider != nil || store.isSynchronizing)
    }

    private func providerButton(_ provider: StorageProvider) -> some View {
        Button {
            connectionError = nil
            if provider == .iCloud || provider == .local {
                isChoosingFolder = true
            } else {
                confirmOrConnect(.cloud(provider))
            }
        } label: {
            HStack(spacing: 8) {
                providerRow(provider)
                if connectingProvider == provider {
                    ProgressView().accessibilityLabel("Connecting…")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("storage.provider.\(provider.rawValue)")
    }

    private func providerRow(_ provider: StorageProvider) -> some View {
        SettingsRow(icon: provider.symbol, color: provider == .webDAV ? .gray : OrgendaTheme.accent,
                    title: provider.title, subtitle: "", iconAsset: provider.iconAsset)
    }

    private func confirmOrConnect(_ selection: PendingConnection) {
        if let current = store.storageConnection {
            if case .folder(let url) = selection,
               !current.provider.isRemote,
               current.rootID == url.resolvingSymlinksInPath().standardizedFileURL.path {
                connect(selection)
            } else {
                pendingConnection = selection
            }
        } else {
            connect(selection)
        }
    }

    private func connect(_ selection: PendingConnection) {
        let preserve = shouldPreservePending
        switch selection {
        case .cloud(let provider):
            connectingProvider = provider
            Task {
                let connected = await store.connectCloud(provider, preservePending: preserve)
                connectingProvider = nil
                if connected { dismiss() }
                else { connectionError = store.fileSyncError }
            }
        case .folder(let url):
            connectingProvider = .local
            Task {
                let previous = store.storageConnection?.id
                await store.connectFolder(url, preservePending: preserve)
                connectingProvider = nil
                let selectedRoot = url.resolvingSymlinksInPath().standardizedFileURL.path
                let isCurrentFolder = store.storageConnection?.provider.isRemote == false
                    && store.storageConnection?.rootID == selectedRoot && store.fileSyncError == nil
                if store.storageConnection?.id != previous || isCurrentFolder { dismiss() }
                else { connectionError = store.fileSyncError }
            }
        }
    }

    private func handleFolderSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            confirmOrConnect(.folder(url))
        case .failure(let error):
            let error = error as NSError
            guard !(error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) else { return }
            connectionError = error.localizedDescription
        }
    }
}

/// Shared wording keeps the final decision consistent for folder, OAuth and WebDAV connections.
enum StorageLocationChange {
    static func message(current: StorageConnection, destination: String, preservePending: Bool) -> String {
        let location = current.provider.isRemote ? current.storageSummary : current.rootID
        let currentLocation = "\(current.providerSummary) · \(location)"
        var message = String(localized: "Current location: \(currentLocation)\nNew location: \(destination)")
        message += "\n\n" + String(localized: "Orgenda will open the workspace at the new location. Existing files stay where they are and will not be moved or copied.")
        if preservePending {
            message += "\n\n" + String(localized: "Unsynced edits will be kept in orgenda → Unsaved Edits before leaving this workspace. They will not be uploaded to the new location.")
        }
        return message
    }
}
