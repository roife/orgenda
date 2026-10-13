import Foundation

enum WebDAVConnectionFactory {
    @MainActor
    static func prepare(configuration: WebDAVConfiguration) async throws -> PreparedRemoteConnection {
        let raw = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let server = URL(string: raw) else { throw StorageError.configuration(String(localized: "Enter a valid HTTPS server address.")) }
        try StorageHTTP.requireHTTPS(server)
        guard server.query == nil else { throw StorageError.configuration(String(localized: "The WebDAV server address must not contain a query string.")) }
        let directory = configuration.directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try StorageError.validate(path: directory, allowEmpty: true)
        let root = directory.split(separator: "/").reduce(server) { $0.appendingPathComponent(String($1), isDirectory: true) }
        let key = UUID().uuidString
        let credential = StorageCredential(username: configuration.username, password: configuration.password)
        let backend = makeBackend(root: root, credential: credential)
        // Only setup may create a missing root. An existing connection never does.
        try await backend.ensureRootDuringSetup()
        try await backend.verifyWritable()
        try StorageKeychain.write(credential, key: key)
        let connection = StorageConnection(provider: .webDAV, displayName: root.host ?? "WebDAV",
                                           accountID: configuration.username,
                                           rootID: root.absoluteString, endpoint: root, credentialKey: key)
        return PreparedRemoteConnection(connection: connection, backend: backend)
    }

    /// Construct locally so the session can load its offline mirror before
    /// network access or root validation can fail.
    static func restore(_ connection: StorageConnection) async throws -> any RemoteWorkspaceBackend {
        let root = try validatedRoot(connection)
        guard let key = connection.credentialKey else { throw StorageError.authenticationRequired }
        let credential = try StorageKeychain.read(key)
        return makeBackend(root: root, credential: credential)
    }

    static func removeCredentials(for connection: StorageConnection) throws {
        if let key = connection.credentialKey { try StorageKeychain.remove(key) }
    }

    @MainActor
    static func reauthenticate(_ connection: StorageConnection, password: String) async throws -> PreparedRemoteConnection {
        let root = try validatedRoot(connection)
        guard let username = connection.accountID else { throw StorageError.rootUnavailable }
        guard !password.isEmpty else {
            throw StorageError.configuration(String(localized: "Enter your WebDAV password to reconnect this workspace."))
        }
        let credential = StorageCredential(username: username, password: password)
        let backend = makeBackend(root: root, credential: credential)
        // Reconnecting must validate the original root without recreating it.
        try await backend.verifyWritable()
        _ = try await backend.scan()
        let key = UUID().uuidString
        try StorageKeychain.write(credential, key: key)
        var updated = connection
        updated.credentialKey = key
        return PreparedRemoteConnection(connection: updated, backend: backend)
    }

    private static func validatedRoot(_ connection: StorageConnection) throws -> URL {
        guard connection.provider == .webDAV, let root = connection.endpoint,
              root.absoluteString == connection.rootID else { throw StorageError.rootUnavailable }
        try StorageHTTP.requireHTTPS(root)
        guard root.query == nil else { throw StorageError.rootUnavailable }
        return root
    }

    private static func makeBackend(root: URL, credential: StorageCredential) -> WebDAVBackend {
        WebDAVBackend(rootURL: root,
                      transport: StorageURLSessionTransport(credential: URLCredential(user: credential.username,
                                                                                    password: credential.password, persistence: .none),
                                                            allowedPathRoot: root))
    }
}
