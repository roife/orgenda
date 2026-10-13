import XCTest
@testable import Orgenda

@MainActor
final class WebDAVBackendTests: XCTestCase {
    override func tearDown() {
        StorageMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRestoreUsesSavedWebDAVCredentialsWithoutNetworkAccess() async throws {
        let root = URL(string: "https://dav.example/org/")!
        let key = UUID().uuidString
        defer { try? StorageKeychain.remove(key) }
        try StorageKeychain.write(StorageCredential(username: "alice", password: "password"), key: key)
        let connection = StorageConnection(provider: .webDAV, displayName: "Workspace", accountID: "alice",
                                           rootID: root.absoluteString, endpoint: root, credentialKey: key)
        let restored = try await WebDAVConnectionFactory.restore(connection)
        let backend = try XCTUnwrap(restored as? WebDAVBackend)
        let restoredRoot = await backend.rootURL
        let restoredTransport = await backend.transport
        XCTAssertEqual(restoredRoot, root)
        let transport = try XCTUnwrap(restoredTransport as? StorageURLSessionTransport)
        XCTAssertEqual(transport.credential?.user, "alice")
        XCTAssertEqual(transport.credential?.password, "password")
        XCTAssertEqual(transport.allowedPathRoot, root)
    }

    func testRestoreRejectsInvalidRootsBeforeReadingCredentials() async throws {
        let root = URL(string: "https://dav.example/org/")!
        let connection = StorageConnection(provider: .webDAV, displayName: "Workspace", accountID: "alice",
                                           rootID: root.absoluteString, endpoint: root, credentialKey: UUID().uuidString)
        for candidate in [
            StorageConnection(provider: .local, displayName: "Files", rootID: root.absoluteString, endpoint: root),
            StorageConnection(provider: .webDAV, displayName: "Workspace", rootID: root.absoluteString),
            StorageConnection(provider: .webDAV, displayName: "Workspace", rootID: "https://dav.example/other/", endpoint: root)
        ] {
            do { _ = try await WebDAVConnectionFactory.restore(candidate); XCTFail("Invalid root accepted") }
            catch { XCTAssertEqual(error as? StorageError, .rootUnavailable) }
        }
        do { _ = try await WebDAVConnectionFactory.restore(connection); XCTFail("Missing credentials accepted") }
        catch { XCTAssertEqual(error as? StorageError, .authenticationRequired) }
    }

    func testSetupRejectsUnsafeServerAddressesAndDirectories() async throws {
        for configuration in [
            WebDAVConfiguration(serverURL: "http://dav.example", username: "alice", password: "password"),
            WebDAVConfiguration(serverURL: "https://alice:password@dav.example", username: "alice", password: "password"),
            WebDAVConfiguration(serverURL: "https://dav.example/?redirect=other", username: "alice", password: "password"),
            WebDAVConfiguration(serverURL: "https://dav.example/#fragment", username: "alice", password: "password"),
            WebDAVConfiguration(serverURL: "https://dav.example", username: "alice", password: "password", directory: "../outside")
        ] {
            do { _ = try await WebDAVConnectionFactory.prepare(configuration: configuration); XCTFail("Unsafe configuration accepted") }
            catch {
                guard let storageError = error as? StorageError else { return XCTFail("Unexpected error: \(error)") }
                switch storageError {
                case .configuration, .unsafePath: break
                default: XCTFail("Unexpected error: \(storageError)")
                }
            }
        }
    }

    func testReconnectWithEmptyPasswordLeavesSavedCredentialsIntact() async throws {
        let root = URL(string: "https://dav.example/org/")!
        let key = UUID().uuidString
        defer { try? StorageKeychain.remove(key) }
        try StorageKeychain.write(StorageCredential(username: "alice", password: "saved-password"), key: key)
        let connection = StorageConnection(provider: .webDAV, displayName: "Workspace", accountID: "alice",
                                           rootID: root.absoluteString, endpoint: root, credentialKey: key)
        do { _ = try await WebDAVConnectionFactory.reauthenticate(connection, password: ""); XCTFail("Empty password accepted") }
        catch {
            guard case .configuration = error as? StorageError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try StorageKeychain.read(key).password, "saved-password")
    }

    func testResponseLimitRejectsAdvertisedAndStreamedOversizedBodies() async throws {
        for reply in [StorageMockURLProtocol.Reply(body: Data(repeating: 42, count: 4096)),
                      .init(headers: ["Content-Length": "5000"])] {
            StorageMockURLProtocol.handler = { _ in reply }
            do {
                _ = try await transport.send(URLRequest(url: URL(string: "https://dav.example/test")!), maxBytes: 512)
                XCTFail("Oversized response accepted")
            } catch { XCTAssertEqual(error as? StorageError, .tooLarge) }
        }
    }

    func testRetryAfterSecondsAndHTTPDateBecomeBackoff() throws {
        XCTAssertThrowsError(try StorageHTTPResponse(status: 429, headers: ["retry-after": "120"], data: Data()).checked()) {
            XCTAssertEqual($0 as? StorageError, .throttled(120))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let date = formatter.string(from: Date().addingTimeInterval(90))
        XCTAssertThrowsError(try StorageHTTPResponse(status: 503, headers: ["retry-after": date], data: Data()).checked()) {
            guard case .throttled(let delay) = $0 as? StorageError else { return XCTFail("Missing server backoff") }
            XCTAssertGreaterThan(delay, 87)
            XCTAssertLessThanOrEqual(delay, 90)
        }
    }

    func testRedirectsKeepWritesInsideDAVRootAndRequirePreservingStatus() {
        let root = URL(string: "https://dav.example/org/")!
        var request = URLRequest(url: root.appendingPathComponent("note.org"))
        request.httpMethod = "PUT"
        XCTAssertFalse(StorageHTTP.redirectAllowed(request: request, target: root.appendingPathComponent("canonical.org"), status: 303, pathRoot: root))
        XCTAssertTrue(StorageHTTP.redirectAllowed(request: request, target: root.appendingPathComponent("canonical.org"), status: 307, pathRoot: root))
        for target in ["https://dav.example/other/note.org", "https://dav.example/org-copy/note.org",
                       "https://dav.example/org/../outside.org", "https://dav.example/org/%2E%2E/outside.org",
                       "https://untrusted.example/org/note.org", "http://dav.example/org/note.org"] {
            XCTAssertFalse(StorageHTTP.redirectAllowed(request: request, target: URL(string: target)!, status: 307, pathRoot: root), target)
        }
        request.httpMethod = "GET"
        XCTAssertTrue(StorageHTTP.redirectAllowed(request: request, target: root, status: 301, pathRoot: root))
    }

    func testWebDAVParsesNamespacesAndPreservesHiddenBinaryEntries() throws {
        let parser = WebDAVMultistatusParser()
        let xml = """
        <multistatus xmlns="DAV:"><response><href>/org/.attach/photo.png</href><propstat><prop><getetag>"revision"</getetag><getcontentlength>42</getcontentlength><resourcetype/></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
        """
        let files = try parser.parse(Data(xml.utf8), root: URL(string: "https://dav.example/org/")!)
        XCTAssertEqual(files.first?.path, ".attach/photo.png")
        XCTAssertEqual(files.first?.revision, "\"revision\"")
        XCTAssertEqual(files.first?.size, 42)
    }

    func testWebDAVRejectsEscapingHrefAndFailedResourceStatus() throws {
        for href in ["https://other.example/org/note.org", "/outside/note.org", "/org/../outside.org"] {
            let xml = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>\(href)</d:href><d:propstat><d:prop><d:getetag>\"x\"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
            XCTAssertThrowsError(try WebDAVMultistatusParser().parse(Data(xml.utf8), root: URL(string: "https://dav.example/org/")!))
        }
        let denied = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/org/secret.org</d:href><d:status>HTTP/1.1 403 Forbidden</d:status></d:response></d:multistatus>"
        XCTAssertThrowsError(try WebDAVMultistatusParser().parse(Data(denied.utf8), root: URL(string: "https://dav.example/org/")!))
    }

    func testWebDAVRequiresSuccessfulResourceTypeAndDirectoryRoot() async throws {
        let missingType = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/org/</d:href><d:propstat><d:prop><d:getetag>\"x\"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
        XCTAssertThrowsError(try WebDAVMultistatusParser().parse(Data(missingType.utf8), root: URL(string: "https://dav.example/org/")!))
        let fileRoot = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/org/</d:href><d:propstat><d:prop><d:resourcetype/><d:getetag>\"x\"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
        var calls = 0
        StorageMockURLProtocol.handler = { _ in calls += 1; return .init(status: 207, body: Data(fileRoot.utf8)) }
        do { _ = try await WebDAVBackend(rootURL: URL(string: "https://dav.example/org/")!, transport: transport).scan(); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .rootUnavailable) }
        XCTAssertEqual(calls, 1)
    }

    func testWebDAVExistingUploadUsesExactETagAndNeverRetries412() async throws {
        var requests = 0
        StorageMockURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return .init(status: 412)
        }
        let backend = WebDAVBackend(rootURL: URL(string: "https://dav.example/org/")!, transport: transport)
        do {
            _ = try await backend.upload(path: "note.org", data: Data("edit".utf8),
                                         existing: .init(id: "note.org", path: "note.org", isDirectory: false, revision: "\"base\""))
            XCTFail("A stale write succeeded")
        } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
        XCTAssertEqual(requests, 1)
    }

    func testWebDAVCreateAndMoveNeverReplaceDestination() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
            } else {
                XCTAssertEqual(request.httpMethod, "MOVE")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Overwrite"), "F")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Destination"), "https://dav.example/org/new.org")
            }
            return .init(status: 412)
        }
        let backend = WebDAVBackend(rootURL: URL(string: "https://dav.example/org/")!, transport: transport)
        do { _ = try await backend.upload(path: "new.org", data: Data(), existing: nil); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .conflict("new.org")) }
        do { _ = try await backend.move(.init(id: "old.org", path: "old.org", isDirectory: false, revision: "\"base\""), to: "new.org"); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .conflict("new.org")) }
    }

    private var transport: StorageURLSessionTransport { .init(protocolClasses: [StorageMockURLProtocol.self]) }
}

private final class StorageMockURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }
    static var handler: ((URLRequest) throws -> Reply)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw StorageError.invalidResponse }
            let reply = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
