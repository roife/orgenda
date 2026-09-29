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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case server, username, password, directory }

    var body: some View {
        Form {
            Section("Server") {
                StorageFormRow(title: "Server Address") {
                    TextField("https://dav.example.com", text: $serverURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .server)
                        .accessibilityLabel("Server Address")
                        .accessibilityIdentifier("storage.webDAV.server")
                }
                StorageFormRow(title: "Username") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .focused($focusedField, equals: .username)
                        .accessibilityLabel("Username")
                        .accessibilityIdentifier("storage.webDAV.username")
                }
                StorageFormRow(title: "Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .accessibilityLabel("Password")
                        .accessibilityIdentifier("storage.webDAV.password")
                }
            }
            Section {
                StorageFormRow(title: "Remote Directory") {
                    TextField("/Orgenda", text: $directory)
                        .focused($focusedField, equals: .directory)
                        .accessibilityLabel("Remote Directory")
                        .accessibilityIdentifier("storage.webDAV.directory")
                }
            } header: {
                Text("Workspace")
            } footer: {
                Text("Files save on this device first, then sync to the server.")
            }
            Section {
                Button(action: connect) {
                    HStack {
                        Spacer(minLength: 0)
                        if isConnecting { ProgressView().tint(.white) }
                        Text(isConnecting ? "Connecting…" : "Test & Connect").fontWeight(.semibold)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(OrgendaTheme.accent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || directory.isEmpty || isConnecting)
                .accessibilityIdentifier("storage.webDAV.connect")
            } footer: {
                Text("Connect a WebDAV server or NAS using HTTPS. Your password is stored securely on this device.")
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
        isConnecting = true
        let configuration = WebDAVConfiguration(serverURL: address, username: user,
                                                password: password, directory: remoteDirectory)
        Task {
            let connected = await store.connectWebDAV(configuration, preservePending: preservePending)
            isConnecting = false
            if connected { dismiss() }
            else { connectionError = store.fileSyncError }
        }
    }
}

private struct StorageFormRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                content
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 16) {
                Text(title).fixedSize()
                content.multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 36)
        }
    }
}
