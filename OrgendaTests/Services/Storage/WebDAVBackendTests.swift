import XCTest
@testable import Orgenda

@MainActor
final class WebDAVBackendTests: XCTestCase {
    override func tearDown() {
        StorageMockURLProtocol.handler = nil
        super.tearDown()
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

    func testNutstorePreservesFilesWithHEADOrGETVersions() async throws {
        for behavior in [NutstoreTestServer.Behavior.standard, .getOnly] {
            let server = NutstoreTestServer(behavior)
            let backend = WebDAVBackend(rootURL: server.root, transport: server)
            try await backend.verifyWritable()
            let probes = await server.files
            XCTAssertTrue(probes.isEmpty)

            let original = Data("original".utf8)
            let saved = try await backend.upload(path: "note.org", data: original, existing: nil)
            do {
                _ = try await backend.upload(path: "note.org", data: Data("replacement".utf8), existing: nil)
                XCTFail("Creating a file replaced another device's file")
            } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
            let files = await server.files
            XCTAssertEqual(files, ["note.org": original])

            await server.replaceExternally("note.org", data: Data("other device".utf8))
            let count = await server.requests.count
            do {
                _ = try await backend.upload(path: "note.org", data: Data("local edit".utf8), existing: saved)
                XCTFail("A stale version overwrote another device's edit")
            } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
            let requests = await server.requests
            XCTAssertEqual(requests.count, count + 1)
            XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "If-Match"), saved.revision)
            let contents = await server.files["note.org"]
            XCTAssertEqual(contents, Data("other device".utf8))
        }
    }

    func testNutstoreProbeRejectsIgnoredWriteProtections() async throws {
        for (behavior, message) in [
            (NutstoreTestServer.Behavior.ignoresVersions, String(localized: "This WebDAV server does not reject conflicting changes.")),
            (.ignoresOverwrite, String(localized: "This WebDAV server does not enforce create-only writes."))
        ] {
            let server = NutstoreTestServer(behavior)
            let backend = WebDAVBackend(rootURL: server.root, transport: server)
            do {
                try await backend.verifyWritable()
                XCTFail("The connection accepted a server that ignores write protection")
            } catch { XCTAssertEqual(error as? StorageError, .unsupported(message)) }
            let files = await server.files
            XCTAssertTrue(files.isEmpty)
        }
    }

    func testUnusableVersionsCannotAuthorizeWrites() async throws {
        StorageMockURLProtocol.handler = { _ in XCTFail("An unsafe write was sent"); return .init(status: 500) }
        for (host, revision) in [
            ("dav.jianguoyun.com", nil), ("dav.jianguoyun.com", "W/\"weak\""),
            ("dav.jianguoyun.com", "*"), ("dav.jianguoyun.com", "first,second"), ("dav.example", "bare-version")
        ] as [(String, String?)] {
            let backend = WebDAVBackend(rootURL: URL(string: "https://\(host)/org/")!, transport: transport)
            do {
                _ = try await backend.upload(path: "note.org", data: Data("edit".utf8),
                    existing: .init(id: "note.org", path: "note.org", isDirectory: false, revision: revision))
                XCTFail("An unusable version was accepted")
            } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
        }
    }

    func testDownloadRetriesWhenHeaderVersionChangesDuringRead() async throws {
        let server = NutstoreTestServer()
        await server.replaceExternally("note.org", data: Data("before".utf8))
        await server.replaceAfterNextGET(with: Data("after".utf8))
        let backend = WebDAVBackend(rootURL: server.root, transport: server)
        let read = try await backend.download(.init(id: "note.org", path: "note.org", isDirectory: false), maxBytes: 1024)
        XCTAssertEqual(read.data, Data("after".utf8))
        let requests = await server.requests
        XCTAssertEqual(requests.filter { $0.httpMethod == "GET" }.count, 2)
    }

    func testMissingHEADVersionStillReadsAndVerifiesContents() async throws {
        let server = NutstoreTestServer(.getOnly)
        await server.replaceExternally("note.org", data: Data("original".utf8))
        let backend = WebDAVBackend(rootURL: server.root, transport: server)
        let file = RemoteFile(id: "note.org", path: "note.org", isDirectory: false)
        let cached = try await backend.download(file, maxBytes: 1024)
        await server.replaceExternally("note.org", data: Data("updated".utf8))
        let result = try await backend.downloadIfChanged(file, since: XCTUnwrap(cached.file.revision), maxBytes: 1024)
        XCTAssertEqual(result?.data, Data("updated".utf8))
    }

    func testRevalidationFailurePreservesCachedSnapshot() async throws {
        let server = NutstoreTestServer()
        await server.replaceExternally("note.org", data: Data("* Local cache\n".utf8))
        let backend = WebDAVBackend(rootURL: server.root, transport: server)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let connection = StorageConnection(provider: .webDAV, displayName: "Test", rootID: server.root.absoluteString)
        let workspace = try LocalStore(connection: connection, cacheDirectory: cache, remote: backend)
        try await workspace.synchronize()
        let initial = try await workspace.snapshot()
        for (status, error) in [(405, StorageError.http(405)), (501, .http(501)), (503, .throttled(60))] {
            await server.failHEAD(status: status)
            do { try await workspace.synchronize(); XCTFail("A failed revalidation was treated as unchanged") }
            catch let failure { XCTAssertEqual(failure as? StorageError, error) }
            let snapshot = try await workspace.snapshot()
            XCTAssertEqual(snapshot.blobHashes, initial.blobHashes)
            XCTAssertEqual(snapshot.lastSync, initial.lastSync)
        }
        await workspace.close()
    }

    func testSharedTransportSeparatesResponsesAndEnforcesLimits() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.httpMethod == "HEAD" {
                return .init(headers: ["Content-Length": "100000000", "ETag": "\"version\""])
            }
            return .init(body: Data(request.url!.lastPathComponent.utf8))
        }
        let shared = transport
        let root = URL(string: "https://dav.example/org/")!
        let responses = try await withThrowingTaskGroup(of: StorageHTTPResponse.self) { group in
            for name in ["one", "two", "three", "four"] {
                group.addTask { try await shared.send(URLRequest(url: root.appendingPathComponent(name)), maxBytes: 32) }
            }
            var replies: [StorageHTTPResponse] = []
            for try await response in group { replies.append(response) }
            return replies
        }
        XCTAssertEqual(Set(responses.map { String(decoding: $0.data, as: UTF8.self) }), ["one", "two", "three", "four"])
        do { _ = try await shared.send(URLRequest(url: root.appendingPathComponent("oversized")), maxBytes: 2); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .tooLarge) }
        var head = URLRequest(url: root)
        head.httpMethod = "HEAD"
        let response = try await shared.send(head, maxBytes: 2)
        XCTAssertEqual(response.headers["etag"], "\"version\"")
        XCTAssertTrue(response.data.isEmpty)
    }

    private var transport: StorageURLSessionTransport { .init(protocolClasses: [StorageMockURLProtocol.self]) }
}

/// No DAV:getetag, bare HTTP ETags, and ignored If-None-Match.
private actor NutstoreTestServer: StorageHTTPTransport {
    enum Behavior { case standard, getOnly, ignoresVersions, ignoresOverwrite }
    nonisolated let root = URL(string: "https://dav.jianguoyun.com/dav/org/")!
    private let behavior: Behavior
    private(set) var files: [String: Data] = [:]
    private(set) var requests: [URLRequest] = []
    private var versions: [String: String] = [:]
    private var nextGETReplacement: Data?
    private var headFailure: Int?

    init(_ behavior: Behavior = .standard) {
        self.behavior = behavior
    }

    func failHEAD(status: Int) { headFailure = status }

    func replaceExternally(_ path: String, data: Data) {
        files[path] = data; versions[path] = UUID().uuidString
    }

    func replaceAfterNextGET(with data: Data) { nextGETReplacement = data }

    func send(_ request: URLRequest, maxBytes: Int) async throws -> StorageHTTPResponse {
        requests.append(request)
        let url = try XCTUnwrap(request.url)
        let path = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let method = request.httpMethod ?? "GET"
        if behavior != .ignoresVersions, let expected = request.value(forHTTPHeaderField: "If-Match"), expected != versions[path] {
            return .init(status: 412, headers: [:], data: Data())
        }
        switch method {
        case "PROPFIND":
            guard path.isEmpty || files[path] != nil else { return .init(status: 404, headers: [:], data: Data()) }
            func entry(_ path: String) -> String {
                let resource = path.isEmpty ? "<d:collection/>" : ""
                let href = path.isEmpty ? root.path : root.appendingPathComponent(path).path
                return """
                <d:response><d:href>\(href)</d:href>
                <d:propstat><d:prop><d:resourcetype>\(resource)</d:resourcetype></d:prop>
                <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
                </d:response>
                """
            }
            var entries = entry(path)
            if path.isEmpty, request.value(forHTTPHeaderField: "Depth") == "1" {
                for child in files.keys.sorted() { entries += entry(child) }
            }
            let xml = "<d:multistatus xmlns:d=\"DAV:\">\(entries)</d:multistatus>"
            return .init(status: 207, headers: [:], data: Data(xml.utf8))
        case "HEAD", "GET":
            if method == "HEAD", let headFailure { return .init(status: headFailure, headers: [:], data: Data()) }
            guard let data = files[path] else { return .init(status: 404, headers: [:], data: Data()) }
            let headers = method == "HEAD" && behavior == .getOnly ? [:] : versions[path].map { ["etag": $0] } ?? [:]
            if method == "GET", let replacement = nextGETReplacement {
                nextGETReplacement = nil
                replaceExternally(path, data: replacement)
            }
            if method == "GET", data.count > maxBytes { throw StorageError.tooLarge }
            return .init(status: 200, headers: headers, data: method == "GET" ? data : Data())
        case "PUT":
            replaceExternally(path, data: request.httpBody ?? Data())
            return .init(status: 201, headers: [:], data: Data())
        case "MOVE":
            let destination = try XCTUnwrap(request.value(forHTTPHeaderField: "Destination").flatMap(URL.init(string:)))
            let target = String(destination.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let data = files[path] else { return .init(status: 404, headers: [:], data: Data()) }
            if files[target] != nil, request.value(forHTTPHeaderField: "Overwrite") == "F", behavior != .ignoresOverwrite {
                return .init(status: 412, headers: [:], data: Data())
            }
            replaceExternally(target, data: data)
            files.removeValue(forKey: path); versions.removeValue(forKey: path)
            return .init(status: 201, headers: [:], data: Data())
        case "DELETE":
            files.removeValue(forKey: path); versions.removeValue(forKey: path)
            return .init(status: 204, headers: [:], data: Data())
        default: throw StorageError.invalidResponse
        }
    }
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
