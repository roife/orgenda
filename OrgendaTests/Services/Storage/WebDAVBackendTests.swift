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
