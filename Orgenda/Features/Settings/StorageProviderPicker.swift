import SwiftUI
import UniformTypeIdentifiers

struct StorageProviderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let preservePending: Bool
    @State private var isChoosingFolder = false
    @State private var connectingProvider: StorageProvider?
    @State private var connectionError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Keep your Org files in sync across devices.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }
                Section("Cloud Storage") {
                    providerButton(.iCloud)
                    providerButton(.oneDrive)
                    providerButton(.googleDrive)
                    providerButton(.dropbox)
                    NavigationLink {
                        StorageWebDAVView(store: store, preservePending: preservePending)
                    } label: {
                        providerRow(.webDAV)
                    }
                    .accessibilityIdentifier("storage.provider.webDAV")
                }
                Section {
                    providerButton(.local)
                } footer: {
                    Text("Connect one location at a time. Cloud services use a dedicated Orgenda folder. Changing locations does not move your existing files.")
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
            .onChange(of: store.storageConnection?.id) { previous, current in
                if current != nil && current != previous { dismiss() }
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
                connectingProvider = provider
                Task {
                    let connected = await store.connectCloud(provider, preservePending: preservePending)
                    connectingProvider = nil
                    if connected { dismiss() }
                    else { connectionError = store.fileSyncError }
                }
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
                    title: provider.title, subtitle: provider.connectionSubtitle)
    }

    private func handleFolderSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            connectingProvider = .local
            Task {
                let previous = store.storageConnection?.id
                await store.connectFolder(url, preservePending: preservePending)
                connectingProvider = nil
                let selectedRoot = url.resolvingSymlinksInPath().standardizedFileURL.path
                let isCurrentFolder = store.storageConnection?.provider.isRemote == false
                    && store.storageConnection?.rootID == selectedRoot && store.fileSyncError == nil
                if store.storageConnection?.id != previous || isCurrentFolder { dismiss() }
                else { connectionError = store.fileSyncError }
            }
        case .failure(let error):
            let error = error as NSError
            guard !(error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) else { return }
            connectionError = error.localizedDescription
        }
    }
}

private extension StorageProvider {
    var connectionSubtitle: String {
        switch self {
        case .local: String(localized: "Choose a folder in Files")
        case .iCloud: String(localized: "Connect through the Files app")
        case .oneDrive: String(localized: "Sign in to your Microsoft account")
        case .googleDrive: String(localized: "Sign in to your Google account")
        case .dropbox: String(localized: "Sign in to your Dropbox account")
        case .webDAV: String(localized: "Connect your own server")
        }
    }
}
