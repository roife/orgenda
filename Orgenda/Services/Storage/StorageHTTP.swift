import Foundation

struct StorageHTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var data: Data

    func checked(path: String = "") throws -> Self {
        switch status {
        case 200..<300: return self
        case 401: throw StorageError.authenticationRequired
        case 409, 412: throw StorageError.conflict(path)
        case 404, 410: throw StorageError.rootUnavailable
        case 413: throw StorageError.tooLarge
        case 429, 503:
            let delay: TimeInterval
            if let raw = headers["retry-after"], let seconds = Double(raw), seconds.isFinite {
                delay = max(1, seconds)
            } else if let raw = headers["retry-after"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                delay = max(1, formatter.date(from: raw)?.timeIntervalSinceNow ?? 60)
            } else { delay = 60 }
            throw StorageError.throttled(delay)
        default: throw StorageError.http(status)
        }
    }
    func json() throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StorageError.invalidResponse
        }
        return object
    }
}

protocol StorageHTTPTransport: Sendable {
    func send(_ request: URLRequest, maxBytes: Int) async throws -> StorageHTTPResponse
}

/// A bounded delegate download, including metadata responses. URLSession.data(for:)
/// would allocate the complete response before enforcing a size limit.
struct StorageURLSessionTransport: StorageHTTPTransport {
    var credential: URLCredential? = nil
    var protocolClasses: [AnyClass]? = nil
    var allowedPathRoot: URL? = nil

    func send(_ request: URLRequest, maxBytes: Int) async throws -> StorageHTTPResponse {
        let operation = StorageHTTPOperation(request: request, limit: maxBytes,
                                             credential: credential, protocolClasses: protocolClasses, allowedPathRoot: allowedPathRoot)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { operation.start($0) }
        } onCancel: { operation.cancel() }
    }
}

private final class StorageHTTPOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let limit: Int
    private let credential: URLCredential?
    private let protocolClasses: [AnyClass]?
    private let allowedPathRoot: URL?
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<StorageHTTPResponse, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var failure: Error?

    init(request: URLRequest, limit: Int, credential: URLCredential?, protocolClasses: [AnyClass]?, allowedPathRoot: URL?) {
        self.request = request; self.limit = limit; self.credential = credential
        self.protocolClasses = protocolClasses; self.allowedPathRoot = allowedPathRoot
    }

    func start(_ continuation: CheckedContinuation<StorageHTTPResponse, Error>) {
        lock.lock()
        guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.protocolClasses = protocolClasses
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            failure = StorageError.invalidResponse; completionHandler(.cancel); return
        }
        self.response = response
        if response.expectedContentLength > Int64(limit) {
            failure = StorageError.tooLarge; completionHandler(.cancel)
        } else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count <= limit, chunk.count <= limit - data.count else {
            failure = StorageError.tooLarge; dataTask.cancel(); return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never move a password, bearer token, or a preauthenticated URL across origins.
        guard let target = newRequest.url,
              StorageHTTP.redirectAllowed(request: request, target: target, status: response.statusCode, pathRoot: allowedPathRoot) else {
            completionHandler(nil); return
        }
        var redirected = request
        redirected.url = target
        completionHandler(redirected)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard let origin = request.url, let credential,
              challenge.previousFailureCount == 0,
              space.host.caseInsensitiveCompare(origin.host ?? "") == .orderedSame,
              space.port == (origin.port ?? 443), space.protocol?.lowercased() == "https",
              [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest].contains(space.authenticationMethod)
        else { completionHandler(.performDefaultHandling, nil); return }
        completionHandler(.useCredential, credential)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<StorageHTTPResponse, Error>
        if let failure { result = .failure(failure) }
        else if let error {
            let code = (error as? URLError)?.code
            if code == .cancelled { result = .failure(CancellationError()) }
            else if [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                     .cannotFindHost, .dnsLookupFailed, .timedOut].contains(code) {
                result = .failure(StorageError.offline)
            } else { result = .failure(error) }
        } else if let response {
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            result = .success(StorageHTTPResponse(status: response.statusCode, headers: headers, data: data))
        } else { result = .failure(StorageError.invalidResponse) }
        lock.lock(); let continuation = continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(with: result)
        session.finishTasksAndInvalidate()
        self.session = nil
    }
}

enum StorageHTTP {
    static let metadataLimit = 8 * 1024 * 1024
    static let maximumEntries = 50_000

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? 443) == (rhs.port ?? 443)
    }
    static func redirectAllowed(request: URLRequest, target: URL, status: Int, pathRoot: URL?) -> Bool {
        guard let origin = request.url, sameOrigin(origin, target), target.scheme?.lowercased() == "https",
              target.user == nil, target.password == nil else { return false }
        let method = request.httpMethod ?? "GET"
        guard ["GET", "HEAD"].contains(method) || [307, 308].contains(status) else { return false }
        guard let pathRoot else { return true }
        func components(_ path: String) -> [String]? {
            var result: [String] = []
            for component in path.split(separator: "/") {
                if component == "." { continue }
                if component == ".." {
                    guard !result.isEmpty else { return nil }
                    result.removeLast()
                } else { result.append(String(component)) }
            }
            return result
        }
        guard let root = components(pathRoot.path), let destination = components(target.path),
              destination.count >= root.count, destination.starts(with: root) else { return false }
        return true
    }
    static func requireHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw StorageError.configuration(String(localized: "Enter an HTTPS server address without embedded credentials."))
        }
    }
    static func url(_ base: String, path: String = "", query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base) else { throw StorageError.invalidResponse }
        components.path += path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw StorageError.invalidResponse }
        return url
    }
    static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String, !value.isEmpty else { throw StorageError.invalidResponse }
        return value
    }
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    static func size(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        return (value as? String).flatMap(Int64.init)
    }
    static func child(_ parent: String, _ name: String) throws -> String {
        guard !name.contains("/") else { throw StorageError.unsafePath(name) }
        let path = parent.isEmpty ? name : parent + "/" + name
        try StorageError.validate(path: path)
        return path
    }
    static func strongETag(_ etag: String?) -> String? {
        guard let etag, etag.hasPrefix("\""), etag.hasSuffix("\""), etag.count > 2,
              !etag.contains("\r"), !etag.contains("\n") else { return nil }
        return etag
    }
}

protocol StorageAccessTokenSource: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

struct CloudHTTPClient: Sendable {
    let transport: any StorageHTTPTransport
    let tokens: any StorageAccessTokenSource
    let allowedHosts: Set<String>

    func send(_ request: URLRequest, maxBytes: Int = StorageHTTP.metadataLimit) async throws -> StorageHTTPResponse {
        guard let url = request.url, allowedHosts.contains(url.host?.lowercased() ?? "") else {
            throw StorageError.invalidResponse
        }
        try StorageHTTP.requireHTTPS(url)
        for attempt in 0...1 {
            var request = request
            request.setValue("Bearer " + (try await tokens.accessToken(forceRefresh: attempt == 1)), forHTTPHeaderField: "Authorization")
            let response = try await transport.send(request, maxBytes: maxBytes)
            if response.status != 401 { return response }
        }
        throw StorageError.authenticationRequired
    }

    func json(_ url: URL, method: String = "GET", body: [String: Any]? = nil,
              headers: [String: String] = [:], path: String = "") async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        else if method == "POST" {
            // Argument-free JSON RPC endpoints (e.g. Dropbox account lookup)
            // expect JSON null, rather than an untyped empty request body.
            request.httpBody = Data("null".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return try await send(request).checked(path: path).json()
    }
}
