import Foundation

enum CloudConnectionFactory {
    @MainActor
    static func prepareWebDAV(configuration: WebDAVConfiguration) async throws -> PreparedRemoteConnection {
        let raw = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let server = URL(string: raw) else { throw StorageError.configuration(String(localized: "Enter a valid HTTPS server address.")) }
        try StorageHTTP.requireHTTPS(server)
        guard server.query == nil else { throw StorageError.configuration(String(localized: "The WebDAV server address must not contain a query string.")) }
        let directory = configuration.directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try StorageError.validate(path: directory, allowEmpty: true)
        let root = directory.split(separator: "/").reduce(server) { $0.appendingPathComponent(String($1), isDirectory: true) }
        let key = UUID().uuidString
        let transport = StorageURLSessionTransport(credential: URLCredential(user: configuration.username,
                                                                              password: configuration.password, persistence: .none), allowedPathRoot: root)
        let backend = WebDAVBackend(rootURL: root, transport: transport)
        // Only setup may create a missing root. An existing connection never does.
        try await backend.ensureRootDuringSetup()
        try await backend.verifyWritable()
        try StorageKeychain.write(StorageCredential(username: configuration.username, password: configuration.password), key: key)
        let connection = StorageConnection(provider: .webDAV, displayName: root.host ?? "WebDAV",
                                           accountID: configuration.username, accountName: configuration.username,
                                           rootID: root.absoluteString, endpoint: root, credentialKey: key)
        return PreparedRemoteConnection(connection: connection, backend: backend)
    }

    @MainActor
    static func prepareCloud(provider: StorageProvider) async throws -> PreparedRemoteConnection {
        let configuration = try CloudOAuthConfiguration.configured(provider)
        let transport = StorageURLSessionTransport()
        let signIn = CloudSignIn()
        let (credential, tokenResult) = try await signIn.authenticate(configuration, transport: transport)
        let key = UUID().uuidString
        try StorageKeychain.write(credential, key: key)
        let tokens = CloudTokenManager(configuration: configuration, credentialKey: key, transport: transport)
        let client = makeClient(provider: provider, tokens: tokens, transport: transport)
        do {
            let connection: StorageConnection
            let backend: any RemoteWorkspaceBackend
            switch provider {
            case .oneDrive:
                let root = try await client.json(URL(string: "https://graph.microsoft.com/v1.0/me/drive/special/approot")!)
                guard root["folder"] != nil, let parent = root["parentReference"] as? [String: Any],
                      let driveID = parent["driveId"] as? String else { throw StorageError.invalidResponse }
                let rootID = try StorageHTTP.string(root, "id")
                let name = ((root["createdBy"] as? [String: Any])?["user"] as? [String: Any])?["displayName"] as? String
                connection = StorageConnection(provider: provider, displayName: "OneDrive · Apps/" + ((root["name"] as? String) ?? "Orgenda"),
                                                accountID: driveID, accountName: name, rootID: rootID, credentialKey: key)
                backend = OneDriveBackend(driveID: driveID, rootID: rootID, client: client)
            case .googleDrive:
                let about = try await client.json(StorageHTTP.url("https://www.googleapis.com", path: "/drive/v2/about",
                                                                   query: [.init(name: "fields", value: "user(displayName,emailAddress,permissionId)")]))
                let user = about["user"] as? [String: Any] ?? [:]
                let roots = try await client.json(GoogleDriveBackend.fileURL(query: [
                    .init(name: "q", value: "'root' in parents and title = 'Orgenda' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
                    .init(name: "fields", value: "items(id,title),nextPageToken"), .init(name: "maxResults", value: "100")]))
                let matches = roots["items"] as? [[String: Any]] ?? []
                guard (roots["items"] == nil || roots["items"] is [[String: Any]]), roots["nextPageToken"] == nil, matches.count <= 1 else {
                    throw StorageError.configuration(String(localized: "More than one Orgenda folder exists in Google Drive. Rename the duplicate folders and reconnect."))
                }
                let root: [String: Any]
                if let existing = matches.first { root = existing }
                else {
                    root = try await client.json(GoogleDriveBackend.fileURL(), method: "POST",
                                                 body: ["title": "Orgenda", "mimeType": "application/vnd.google-apps.folder", "parents": [["id": "root"]]])
                }
                let rootID = try StorageHTTP.string(root, "id")
                connection = StorageConnection(provider: provider, displayName: "Google Drive · Orgenda",
                                                accountID: user["permissionId"] as? String,
                                                accountName: user["emailAddress"] as? String ?? user["displayName"] as? String,
                                                rootID: rootID, credentialKey: key)
                backend = GoogleDriveBackend(rootID: rootID, client: client)
            case .dropbox:
                let account = try await client.json(URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!, method: "POST")
                let root: [String: Any]
                do {
                    root = try await client.json(URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!,
                                                 method: "POST", body: ["path": "/Workspace"])
                } catch StorageError.conflict {
                    let result = try await client.json(URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!,
                                                       method: "POST", body: ["path": "/Workspace", "autorename": false])
                    guard let metadata = result["metadata"] as? [String: Any] else { throw StorageError.invalidResponse }
                    root = metadata
                }
                guard root[".tag"] as? String == "folder" else { throw StorageError.rootUnavailable }
                let rootID = try StorageHTTP.string(root, "id")
                connection = StorageConnection(provider: provider, displayName: "Dropbox · Apps/Orgenda/Workspace",
                                                accountID: account["account_id"] as? String ?? tokenResult["account_id"] as? String,
                                                accountName: account["email"] as? String, rootID: rootID, credentialKey: key)
                backend = DropboxBackend(rootID: rootID, client: client)
            default: throw StorageError.configuration("Choose a cloud storage provider.")
            }
            _ = try await backend.scan(cursor: nil)
            return PreparedRemoteConnection(connection: connection, backend: backend)
        } catch {
            try? StorageKeychain.remove(key)
            throw error
        }
    }

    /// Construct only. The session must be able to load its offline mirror before
    /// token refresh, network access or root validation can fail.
    static func restore(_ connection: StorageConnection) async throws -> any RemoteWorkspaceBackend {
        guard let key = connection.credentialKey else { throw StorageError.authenticationRequired }
        if connection.provider == .webDAV {
            guard let root = connection.endpoint, root.absoluteString == connection.rootID else { throw StorageError.rootUnavailable }
            try StorageHTTP.requireHTTPS(root)
            // Keychain reading is local and never triggers an account request.
            let credential = try StorageKeychain.read(key)
            guard let username = credential.username, let password = credential.password else { throw StorageError.authenticationRequired }
            return WebDAVBackend(rootURL: root,
                                 transport: StorageURLSessionTransport(credential: URLCredential(user: username, password: password, persistence: .none), allowedPathRoot: root))
        }
        let configuration = try CloudOAuthConfiguration.configured(connection.provider)
        let transport = StorageURLSessionTransport()
        let tokens = CloudTokenManager(configuration: configuration, credentialKey: key, transport: transport)
        let client = makeClient(provider: connection.provider, tokens: tokens, transport: transport)
        switch connection.provider {
        case .oneDrive:
            guard let driveID = connection.accountID else { throw StorageError.rootUnavailable }
            return OneDriveBackend(driveID: driveID, rootID: connection.rootID, client: client)
        case .googleDrive: return GoogleDriveBackend(rootID: connection.rootID, client: client)
        case .dropbox: return DropboxBackend(rootID: connection.rootID, client: client)
        default: throw StorageError.configuration("This location is not a remote storage connection.")
        }
    }

    static func removeCredentials(for connection: StorageConnection) throws {
        if let key = connection.credentialKey { try StorageKeychain.remove(key) }
    }

    @MainActor
    static func reauthenticate(_ connection: StorageConnection, webDAVPassword: String? = nil) async throws -> PreparedRemoteConnection {
        let key = UUID().uuidString
        var updated = connection
        updated.credentialKey = key
        let credential: StorageCredential
        if connection.provider == .webDAV {
            guard let endpoint = connection.endpoint, endpoint.absoluteString == connection.rootID,
                  let username = connection.accountID else { throw StorageError.rootUnavailable }
            try StorageHTTP.requireHTTPS(endpoint)
            guard let password = webDAVPassword, !password.isEmpty else {
                throw StorageError.configuration(String(localized: "Enter your WebDAV password to reconnect this workspace."))
            }
            credential = StorageCredential(username: username, password: password)
            let backend = WebDAVBackend(rootURL: endpoint,
                                         transport: StorageURLSessionTransport(credential: URLCredential(user: username, password: password, persistence: .none), allowedPathRoot: endpoint))
            // Never call ensureRootDuringSetup while repairing a connection.
            try await backend.verifyWritable()
            _ = try await backend.scan(cursor: nil)
        } else {
            let configuration = try CloudOAuthConfiguration.configured(connection.provider)
            let transport = StorageURLSessionTransport()
            (credential, _) = try await CloudSignIn().authenticate(configuration, transport: transport)
            guard let access = credential.accessToken else { throw StorageError.authenticationRequired }
            let client = makeClient(provider: connection.provider, tokens: FreshAccessToken(value: access), transport: transport)
            let accountID: String
            let backend: any RemoteWorkspaceBackend
            switch connection.provider {
            case .oneDrive:
                let drive = try await client.json(URL(string: "https://graph.microsoft.com/v1.0/me/drive?$select=id")!)
                accountID = try StorageHTTP.string(drive, "id")
                backend = OneDriveBackend(driveID: accountID, rootID: connection.rootID, client: client)
            case .googleDrive:
                let about = try await client.json(StorageHTTP.url("https://www.googleapis.com", path: "/drive/v2/about",
                                                                   query: [.init(name: "fields", value: "user(permissionId)")]))
                guard let user = about["user"] as? [String: Any] else { throw StorageError.invalidResponse }
                accountID = try StorageHTTP.string(user, "permissionId")
                backend = GoogleDriveBackend(rootID: connection.rootID, client: client)
            case .dropbox:
                let account = try await client.json(URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!, method: "POST")
                accountID = try StorageHTTP.string(account, "account_id")
                backend = DropboxBackend(rootID: connection.rootID, client: client)
            default: throw StorageError.authenticationRequired
            }
            guard accountID == connection.accountID else {
                throw StorageError.configuration(String(localized: "Sign in to the account originally connected to this workspace. Your offline changes have not been moved."))
            }
            _ = try await backend.scan(cursor: nil)
        }
        // Publish the new key only after identity and the original root validate.
        try StorageKeychain.write(credential, key: key)
        do { return PreparedRemoteConnection(connection: updated, backend: try await restore(updated)) }
        catch { try? StorageKeychain.remove(key); throw error }
    }

    private static func makeClient(provider: StorageProvider, tokens: any StorageAccessTokenSource,
                                   transport: any StorageHTTPTransport) -> CloudHTTPClient {
        let hosts: Set<String>
        switch provider {
        case .oneDrive: hosts = ["graph.microsoft.com"]
        case .googleDrive: hosts = ["www.googleapis.com"]
        case .dropbox: hosts = ["api.dropboxapi.com", "content.dropboxapi.com"]
        default: hosts = []
        }
        return CloudHTTPClient(transport: transport, tokens: tokens, allowedHosts: hosts)
    }
}

private struct FreshAccessToken: StorageAccessTokenSource {
    let value: String
    func accessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh { throw StorageError.authenticationRequired }
        return value
    }
}
