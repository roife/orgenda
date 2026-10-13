import SwiftUI

struct StorageReconnectAction: View {
    let store: WorkspaceStore
    @State private var credentialConnection: StorageConnection?

    var body: some View {
        Button {
            credentialConnection = store.storageConnection
        } label: {
            Label("Update Password", systemImage: "key.fill")
        }
        .disabled(store.isSynchronizing)
        .tint(OrgendaTheme.accentText)
        .accessibilityIdentifier("storage.reauthenticate")
        .sheet(item: $credentialConnection) { connection in
            StorageWebDAVCredentialsView(store: store, connection: connection)
        }
    }
}

private struct StorageWebDAVCredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let connection: StorageConnection
    @State private var password = ""
    @State private var isReconnecting = false
    @State private var connectionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("WebDAV") {
                    if let endpoint = connection.endpoint {
                        SettingsValueRow(title: String(localized: "Server Address"), value: endpoint.absoluteString)
                    }
                    if let username = connection.accountID {
                        SettingsValueRow(title: String(localized: "Username"), value: username)
                    }
                    SecureField("New Password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("storage.reauthenticate.password")
                }
                Section {
                    Button {
                        isReconnecting = true
                        connectionError = nil
                        Task {
                            let connected = await store.reconnectStorage(webDAVPassword: password)
                            isReconnecting = false
                            if connected { dismiss() }
                            else { connectionError = store.fileSyncError }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if isReconnecting { ProgressView() }
                            Text("Update Password")
                        }
                    }
                    .disabled(password.isEmpty)
                    .accessibilityIdentifier("storage.reauthenticate.save")
                }
                if let connectionError {
                    Section("Could Not Connect") {
                        Text(connectionError).font(.subheadline).textSelection(.enabled)
                    }
                }
            }
            .disabled(isReconnecting)
            .navigationTitle("Update WebDAV Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.disabled(isReconnecting)
                }
            }
        }
        .interactiveDismissDisabled(isReconnecting)
    }
}
