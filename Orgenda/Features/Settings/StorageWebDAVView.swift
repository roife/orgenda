import SwiftUI

struct StorageWebDAVView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let preservePending: Bool
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var directory = "/Orgenda"
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var pendingConfiguration: WebDAVConfiguration?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case server, username, password, directory }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Server Address") {
                    TextField("Server Address", text: $serverURL, prompt: Text("https://dav.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .server)
                        .accessibilityIdentifier("storage.webDAV.server")
                }
                LabeledContent("Username") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .accessibilityIdentifier("storage.webDAV.username")
                }
                LabeledContent("Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .password)
                        .accessibilityIdentifier("storage.webDAV.password")
                }
            }
            Section {
                LabeledContent("Remote Directory") {
                    TextField("Remote Directory", text: $directory, prompt: Text("/Orgenda"))
                        .submitLabel(.go)
                        .focused($focusedField, equals: .directory)
                        .accessibilityIdentifier("storage.webDAV.directory")
                }
            } header: {
                Text("Workspace")
            }
            Section {
                Button(action: connect) {
                    HStack {
                        if isConnecting { ProgressView() }
                        Text(LocalizedStringKey(isConnecting ? "Connecting…" : "Test & Connect"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonSizing(.flexible)
                .controlSize(.large)
                .tint(OrgendaTheme.accent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || directory.isEmpty || isConnecting)
                .accessibilityIdentifier("storage.webDAV.connect")
            }
            if let connectionError {
                Section("Could Not Connect") {
                    Text(connectionError)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("storage.webDAV.error")
                }
            }
        }
        .disabled(isConnecting)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Connect WebDAV")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isConnecting)
        .interactiveDismissDisabled(isConnecting)
        .confirmationDialog("Change storage location?", item: $pendingConfiguration, titleVisibility: .visible) { configuration in
            Button(LocalizedStringKey(shouldPreservePending ? "Keep Copies and Change Location" : "Change Location")) {
                pendingConfiguration = nil
                performConnection(configuration)
            }
            Button("Cancel", role: .cancel) { pendingConfiguration = nil }
        } message: { configuration in
            if let current = store.storageConnection, let server = URL(string: configuration.serverURL) {
                let destination = configuration.directory.split(separator: "/").reduce(server) {
                    $0.appendingPathComponent(String($1), isDirectory: true)
                }
                Text(StorageLocationChange.message(current: current, destination: destination.absoluteString,
                                                   preservePending: shouldPreservePending))
            }
        }
        .onSubmit {
            switch focusedField {
            case .server: focusedField = .username
            case .username: focusedField = .password
            case .password: focusedField = .directory
            case .directory: connect()
            case nil: break
            }
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        focusedField = nil
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.url != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            connectionError = String(localized: "Enter a valid HTTPS server address without a username, password, query, or fragment.")
            return
        }
        let remoteDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard remoteDirectory.hasPrefix("/"),
              !remoteDirectory.contains("\\"), !remoteDirectory.contains("\0"),
              remoteDirectory.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else {
            connectionError = String(localized: "Enter an absolute directory such as /Orgenda without . or .. components.")
            return
        }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            connectionError = String(localized: "Enter your WebDAV username and password.")
            return
        }
        connectionError = nil
        let configuration = WebDAVConfiguration(serverURL: address, username: user,
                                                password: password, directory: remoteDirectory)
        if store.storageConnection != nil {
            pendingConfiguration = configuration
        } else {
            performConnection(configuration)
        }
    }

    private var shouldPreservePending: Bool { preservePending || store.hasPendingStorageChanges }

    private func performConnection(_ configuration: WebDAVConfiguration) {
        isConnecting = true
        let preserve = shouldPreservePending
        Task {
            let connected = await store.connectWebDAV(configuration, preservePending: preserve)
            isConnecting = false
            if connected { dismiss() }
            else { connectionError = store.fileSyncError }
        }
    }
}
