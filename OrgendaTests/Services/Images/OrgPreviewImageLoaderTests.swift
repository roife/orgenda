import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Orgenda

final class OrgPreviewImageLoaderTests: XCTestCase {
    func testLoadsLocalImageAndFallsBackOnlyWhenAFileIsMissing() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try imageData(width: 12, height: 8).write(to: root.appendingPathComponent("image.png"))
        let image = try await OrgPreviewImageLoader().load(
            candidates: ["missing.png", "image.png"],
            fileStore: WorkspaceFileStore(rootURL: root), workspaceID: UUID())
        XCTAssertEqual(image.size.width, 12)
        XCTAssertEqual(image.size.height, 8)
    }

    func testLocalImageReplacementIsNotHiddenByACache() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("image.png")
        let loader = OrgPreviewImageLoader()
        let store = WorkspaceFileStore(rootURL: root)
        let workspace = UUID()
        try imageData(width: 12, height: 8).write(to: url)
        let first = try await loader.load(candidates: ["image.png"], fileStore: store, workspaceID: workspace)
        try imageData(width: 20, height: 10).write(to: url, options: .atomic)
        let second = try await loader.load(candidates: ["image.png"], fileStore: store, workspaceID: workspace)
        XCTAssertEqual(first.size.width, 12)
        XCTAssertEqual(second.size.width, 20)
    }

    func testUnsafeAndDamagedCandidatesDoNotFallBack() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try imageData(width: 12, height: 8).write(to: root.appendingPathComponent("image.png"))
        try Data("not an image".utf8).write(to: root.appendingPathComponent("damaged.png"))
        let loader = OrgPreviewImageLoader()
        let store = WorkspaceFileStore(rootURL: root)
        do {
            _ = try await loader.load(candidates: ["../outside.png", "image.png"], fileStore: store, workspaceID: UUID())
            XCTFail("An unsafe first candidate must not be concealed by a valid fallback")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .unsafePath("../outside.png"))
        }
        do {
            _ = try await loader.load(candidates: ["damaged.png", "image.png"], fileStore: store, workspaceID: UUID())
            XCTFail("A damaged first candidate must not silently choose another image")
        } catch let failure as OrgPreviewImageLoader.Failure {
            XCTAssertEqual(failure, .unsupportedFormat)
        }
    }

    func testRemoteURLPreservesQueryAndDecodesPNG() async throws {
        let url = remoteURL(query: "signature=a%2Bb&size=large")
        ImageLoadingURLProtocol.register(.init(data: try imageData(width: 12, height: 8)), for: url)
        defer { ImageLoadingURLProtocol.unregister(url) }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let image = try await OrgPreviewImageLoader(session: session).load(
            candidates: [url.absoluteString], fileStore: nil, workspaceID: UUID())
        XCTAssertEqual(image.size.width, 12)
        XCTAssertEqual(image.size.height, 8)
        // The protocol registry matches the complete URL, including its query.
        XCTAssertEqual(ImageLoadingURLProtocol.requests(for: url), 1)
    }

    func testThumbnailIsBoundedAndAppliesEXIFOrientation() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try imageData(width: 400, height: 200, type: UTType.jpeg.identifier, orientation: 6)
            .write(to: root.appendingPathComponent("rotated.jpg"))
        let image = try await OrgPreviewImageLoader(maxPixelDimension: 160).load(
            candidates: ["rotated.jpg"], fileStore: WorkspaceFileStore(rootURL: root), workspaceID: UUID())
        XCTAssertEqual(image.size.width, 80)
        XCTAssertEqual(image.size.height, 160)
        XCTAssertEqual(image.imageOrientation, .up)
    }

    func testRejectsBothAdvertisedAndStreamedOversizedResponses() async throws {
        let advertisedURL = remoteURL()
        let streamedURL = remoteURL()
        ImageLoadingURLProtocol.register(.init(data: Data(), headers: ["Content-Length": "17"]), for: advertisedURL)
        ImageLoadingURLProtocol.register(.init(data: Data(repeating: 1, count: 17)), for: streamedURL)
        defer {
            ImageLoadingURLProtocol.unregister(advertisedURL)
            ImageLoadingURLProtocol.unregister(streamedURL)
        }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let loader = OrgPreviewImageLoader(session: session, maxBytes: 16)
        for url in [advertisedURL, streamedURL] {
            do {
                _ = try await loader.load(candidates: [url.absoluteString], fileStore: nil, workspaceID: UUID())
                XCTFail("An image exceeding the byte budget must fail")
            } catch let failure as OrgPreviewImageLoader.Failure {
                XCTAssertEqual(failure, .tooLarge)
            }
        }
    }

    func testRejectsFailedHTTPStatusAndUnsupportedData() async throws {
        let missingURL = remoteURL()
        let damagedURL = remoteURL()
        ImageLoadingURLProtocol.register(.init(data: try imageData(width: 2, height: 2), status: 404), for: missingURL)
        ImageLoadingURLProtocol.register(.init(data: Data("<html>not an image</html>".utf8)), for: damagedURL)
        defer {
            ImageLoadingURLProtocol.unregister(missingURL)
            ImageLoadingURLProtocol.unregister(damagedURL)
        }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let loader = OrgPreviewImageLoader(session: session)
        for (url, expected) in [(missingURL, OrgPreviewImageLoader.Failure.httpStatus(404)), (damagedURL, .unsupportedFormat)] {
            do {
                _ = try await loader.load(candidates: [url.absoluteString], fileStore: nil, workspaceID: UUID())
                XCTFail("Invalid response accepted")
            } catch let failure as OrgPreviewImageLoader.Failure {
                XCTAssertEqual(failure, expected)
            }
        }
    }

    func testRejectsCredentialsAndNonHTTPFinalResponse() async throws {
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let loader = OrgPreviewImageLoader(session: session)
        let url = remoteURL()
        ImageLoadingURLProtocol.register(.init(data: Data(), responseURL: URL(fileURLWithPath: "/private/image.png")), for: url)
        defer { ImageLoadingURLProtocol.unregister(url) }
        for source in ["https://user:secret@images.example.test/image.png", url.absoluteString] {
            do {
                _ = try await loader.load(candidates: [source], fileStore: nil, workspaceID: UUID())
                XCTFail("Unsafe URL accepted")
            } catch let failure as OrgPreviewImageLoader.Failure {
                XCTAssertEqual(failure, .invalidURL)
            }
        }
    }

    func testATSFailureExplainsHTTPSRequirement() async throws {
        let url = remoteURL()
        ImageLoadingURLProtocol.register(.init(data: Data(), error: URLError(.appTransportSecurityRequiresSecureConnection)), for: url)
        defer { ImageLoadingURLProtocol.unregister(url) }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await OrgPreviewImageLoader(session: session).load(
                candidates: [url.absoluteString], fileStore: nil, workspaceID: UUID())
            XCTFail("ATS failure was ignored")
        } catch let failure as OrgPreviewImageLoader.Failure {
            XCTAssertEqual(failure, .requiresHTTPS)
        }
    }

    func testCancellingAnActiveDownloadStopsLoading() async throws {
        let url = remoteURL()
        let started = expectation(description: "Image request started")
        let stopped = expectation(description: "Image request stopped")
        ImageLoadingURLProtocol.register(.init(data: Data(), suspend: true,
            onStart: { started.fulfill() }, onStop: { stopped.fulfill() }), for: url)
        defer { ImageLoadingURLProtocol.unregister(url) }
        let session = mockSession()
        defer { session.invalidateAndCancel() }
        let loader = OrgPreviewImageLoader(session: session)
        let task = Task {
            try await loader.load(candidates: [url.absoluteString], fileStore: nil, workspaceID: UUID())
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled request completed successfully")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        await fulfillment(of: [stopped], timeout: 3)
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OrgImageTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func remoteURL(query: String? = nil) -> URL {
        var components = URLComponents(string: "https://images.example.test/" + UUID().uuidString + ".png")!
        components.percentEncodedQuery = query
        return components.url!
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageLoadingURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func imageData(width: Int, height: Int, type: String = UTType.png.identifier, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// Every session in these tests uses this protocol: no request reaches the
/// network. URL-keyed fixtures let tests run independently without a shared
/// mutable response handler.
private final class ImageLoadingURLProtocol: URLProtocol {
    struct Stub {
        var data: Data
        var status: Int = 200
        var headers: [String: String] = [:]
        var responseURL: URL? = nil
        var error: Error? = nil
        var suspend = false
        var onStart: (() -> Void)? = nil
        var onStop: (() -> Void)? = nil
    }

    private static let lock = NSLock()
    private static var fixtures: [URL: Stub] = [:]
    private static var requestCounts: [URL: Int] = [:]
    private var onStop: (() -> Void)?

    static func register(_ stub: Stub, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        fixtures[url] = stub
        requestCounts[url] = 0
    }

    static func unregister(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        fixtures.removeValue(forKey: url)
        requestCounts.removeValue(forKey: url)
    }

    static func requests(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[url, default: 0]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        let stub = Self.fixtures[url]
        Self.requestCounts[url, default: 0] += 1
        Self.lock.unlock()
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        onStop = stub.onStop
        stub.onStart?()
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: stub.responseURL ?? url, statusCode: stub.status,
            httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if stub.suspend { return }
        if !stub.data.isEmpty { client?.urlProtocol(self, didLoad: stub.data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        onStop?()
        onStop = nil
    }
}
