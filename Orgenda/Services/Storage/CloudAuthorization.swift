import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct StorageCredential: Codable, Sendable {
    var username: String? = nil
    var password: String? = nil
    var accessToken: String? = nil
    var refreshToken: String? = nil
    var expiresAt: Date? = nil
}

enum StorageKeychain {
    private static let service = "com.roifewu.Orgenda.storage"
    private static let lock = NSLock()
    private static var removedKeys = Set<String>()

    static func read(_ key: String) throws -> StorageCredential {
        lock.lock(); defer { lock.unlock() }
        guard !removedKeys.contains(key) else { throw StorageError.authenticationRequired }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key,
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw StorageError.authenticationRequired
        }
        return try JSONDecoder().decode(StorageCredential.self, from: data)
    }

    static func write(_ credential: StorageCredential, key: String) throws {
        lock.lock(); defer { lock.unlock() }
        // A refresh already in flight must not recreate credentials after logout.
        guard !removedKeys.contains(key) else { throw StorageError.authenticationRequired }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key]
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credential),
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw StorageError.authenticationRequired }
        } else if status != errSecSuccess { throw StorageError.authenticationRequired }
    }

    static func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        removedKeys.insert(key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.authenticationRequired }
    }
}

struct CloudOAuthConfiguration: Sendable {
    var provider: StorageProvider
    var clientID: String
    var redirectURI: String
    var authorizationURL: URL
    var tokenURL: URL
    var scopes: String

    static func configured(_ provider: StorageProvider, bundle: Bundle = .main) throws -> Self {
        let prefix: String, authorization: String, token: String, scopes: String
        switch provider {
        case .oneDrive:
            prefix = "ORGENDAOneDrive"
            authorization = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
            token = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
            scopes = "Files.ReadWrite.AppFolder offline_access"
        case .googleDrive:
            prefix = "ORGENDAGoogleDrive"
            authorization = "https://accounts.google.com/o/oauth2/v2/auth"
            token = "https://oauth2.googleapis.com/token"
            scopes = "https://www.googleapis.com/auth/drive"
        case .dropbox:
            prefix = "ORGENDADropbox"
            authorization = "https://www.dropbox.com/oauth2/authorize"
            token = "https://api.dropboxapi.com/oauth2/token"
            scopes = "files.metadata.read files.content.read files.content.write account_info.read"
        default: throw StorageError.configuration("This storage provider does not use OAuth.")
        }
        guard let clientID = bundle.object(forInfoDictionaryKey: prefix + "ClientID") as? String,
              let redirect = bundle.object(forInfoDictionaryKey: prefix + "RedirectURI") as? String,
              !clientID.isEmpty, !clientID.contains("$("), !redirect.contains("$("),
              let redirectURL = URL(string: redirect), let scheme = redirectURL.scheme,
              !["http", "https"].contains(scheme.lowercased()) else {
            throw StorageError.configuration(String(localized: "This build has not configured \(provider.title) sign-in. See CloudStorage.md for setup."))
        }
        return Self(provider: provider, clientID: clientID, redirectURI: redirect,
                    authorizationURL: URL(string: authorization)!, tokenURL: URL(string: token)!, scopes: scopes)
    }

    func authorizationRequest(state: String, verifier: String) throws -> URL {
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "client_id", value: clientID),
                     .init(name: "redirect_uri", value: redirectURI), .init(name: "response_type", value: "code"),
                     .init(name: "scope", value: scopes), .init(name: "state", value: state),
                     .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")]
        if provider == .googleDrive { items += [.init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent")] }
        if provider == .dropbox { items.append(.init(name: "token_access_type", value: "offline")) }
        components.queryItems = items
        guard let url = components.url else { throw StorageError.invalidResponse }
        return url
    }

    func tokenRequest(_ parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parameters = parameters
        parameters["client_id"] = clientID
        request.httpBody = Data(parameters.keys.sorted().map {
            Self.formEscape($0) + "=" + Self.formEscape(parameters[$0]!)
        }.joined(separator: "&").utf8)
        return request
    }

    private static func formEscape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
    }
}

private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

actor CloudTokenManager: StorageAccessTokenSource {
    let configuration: CloudOAuthConfiguration
    let credentialKey: String
    let transport: any StorageHTTPTransport
    private var refreshing: Task<String, Error>?

    init(configuration: CloudOAuthConfiguration, credentialKey: String, transport: any StorageHTTPTransport) {
        self.configuration = configuration; self.credentialKey = credentialKey; self.transport = transport
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        if let refreshing { return try await refreshing.value }
        let saved = try StorageKeychain.read(credentialKey)
        if !forceRefresh, let token = saved.accessToken,
           let expires = saved.expiresAt, expires.timeIntervalSinceNow > 90 { return token }
        guard let refresh = saved.refreshToken else { throw StorageError.authenticationRequired }
        let config = configuration, transport = transport, key = credentialKey
        let task = Task<String, Error> {
            let request = config.tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh])
            let response = try await transport.send(request, maxBytes: 256 * 1024)
            if response.status == 400 || response.status == 401 { throw StorageError.authenticationRequired }
            let json = try response.checked().json()
            let credential = try Self.credential(from: json, previousRefresh: refresh)
            try StorageKeychain.write(credential, key: key)
            return credential.accessToken!
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    static func credential(from json: [String: Any], previousRefresh: String? = nil) throws -> StorageCredential {
        let access = try StorageHTTP.string(json, "access_token")
        let refresh = json["refresh_token"] as? String ?? previousRefresh
        guard let refresh, !refresh.isEmpty else { throw StorageError.authenticationRequired }
        let seconds = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return StorageCredential(accessToken: access, refreshToken: refresh,
                                 expiresAt: Date().addingTimeInterval(seconds))
    }
}

@MainActor
final class CloudSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: UIWindow?
    private var pending: CheckedContinuation<URL, Error>?

    func authenticate(_ configuration: CloudOAuthConfiguration,
                      transport: any StorageHTTPTransport) async throws -> (StorageCredential, [String: Any]) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw StorageError.authenticationRequired
        }
        anchor = scene.windows.first(where: \.isKeyWindow) ?? UIWindow(windowScene: scene)
        defer { anchor = nil }
        let verifier = try Self.randomString(), state = try Self.randomString()
        let authorizationURL = try configuration.authorizationRequest(state: state, verifier: verifier)
        guard let redirect = URL(string: configuration.redirectURI), let scheme = redirect.scheme else {
            throw StorageError.invalidResponse
        }
        let callback = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                pending = continuation
                let session = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: scheme) { [weak self] url, error in
                    Task { @MainActor in
                        if let url { self?.finish(.success(url)) }
                        else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                            self?.finish(.failure(CancellationError()))
                        } else { self?.finish(.failure(error ?? StorageError.authenticationRequired)) }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() { finish(.failure(StorageError.authenticationRequired)) }
            }
        } onCancel: {
            Task { @MainActor in
                self.session?.cancel()
                self.finish(.failure(CancellationError()))
            }
        }
        guard callback.scheme == redirect.scheme, callback.host == redirect.host,
              callback.path == redirect.path,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw StorageError.authenticationRequired
        }
        let values = components.queryItems ?? []
        guard values.filter({ $0.name == "state" }).count == 1,
              values.first(where: { $0.name == "state" })?.value == state,
              let code = values.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { throw StorageError.authenticationRequired }
        let request = configuration.tokenRequest(["grant_type": "authorization_code", "code": code,
                                                   "redirect_uri": configuration.redirectURI, "code_verifier": verifier])
        let json = try await transport.send(request, maxBytes: 256 * 1024).checked().json()
        return (try CloudTokenManager.credential(from: json), json)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // authenticate() establishes the scene before starting the session.
        anchor!
    }

    private func finish(_ result: Result<URL, Error>) {
        let pending = pending
        self.pending = nil; session = nil
        pending?.resume(with: result)
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StorageError.authenticationRequired
        }
        return Data(bytes).base64URLEncoded
    }
}
