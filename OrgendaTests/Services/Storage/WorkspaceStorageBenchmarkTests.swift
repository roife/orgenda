import Foundation
import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStorageBenchmarkTests: XCTestCase {
    func testSingleEditWithStrongPUTETag() async throws {
        try await measureSingleEdit(strongPUTETag: true)
    }

    func testSingleEditWithVerifiedPUTFallback() async throws {
        try await measureSingleEdit(strongPUTETag: false)
    }

    private func measureSingleEdit(strongPUTETag: Bool) async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("StorageBenchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let connection = StorageConnection(provider: .webDAV, displayName: "Benchmark", rootID: "/org")
        let server = BenchmarkDAVServer(fileCount: 1000, bytesPerFile: 10 * 1024, strongPUTETag: strongPUTETag)
        let backend = WebDAVBackend(rootURL: server.root, transport: server)
        let session = try LocalStore(connection: connection, cacheDirectory: cache, remote: backend)
        try await session.synchronize()
        let initial = try await session.snapshot()
        let original = try XCTUnwrap(initial.documents.first { $0.path == "group0/file0.org" })
        let edited = original.contents + "\n* Edited\n"
        let wal = cache.appendingPathComponent(connection.id.uuidString).appendingPathComponent("state.sqlite-wal")
        let walBefore = (try FileManager.default.attributesOfItem(atPath: wal.path)[.size] as? NSNumber)?.intValue ?? 0
        await session.beginMeasuringIO()
        await server.resetMetrics()
        let start = ContinuousClock.now
        // Match the persistence pipeline: local commit and UI snapshot, then
        // synchronization and the final UI snapshot. Initial import is excluded.
        try await session.write(path: original.path, contents: edited, expectedBlob: initial.blobHashes[original.path])
        let local = try await session.snapshot(since: initial.revision)
        try await session.synchronize(mode: .push)
        let delta = try await session.snapshot(since: local.revision)
        let elapsed = start.duration(to: .now)
        let walAfter = (try FileManager.default.attributesOfItem(atPath: wal.path)[.size] as? NSNumber)?.intValue ?? 0
        let network = await server.metrics
        let measuredIO = await session.ioMetrics
        let io = try XCTUnwrap(measuredIO)
        let report = BenchmarkReport(strongPUTETag: strongPUTETag, files: 1000, workspaceBytes: 1000 * 10 * 1024,
            seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            network: network, localIO: io, walFileGrowthBytes: max(0, walAfter - walBefore))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "storage-benchmark"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("STORAGE_BENCHMARK " + String(decoding: try JSONEncoder().encode(report), as: UTF8.self))
        XCTAssertTrue(delta.pendingPaths.isEmpty)
        XCTAssertFalse(local.isComplete)
        XCTAssertEqual(local.documents.map(\.path), [original.path])
        XCTAssertTrue(delta.documents.isEmpty)
        XCTAssertEqual(io.blobBytesRead, 0)
        XCTAssertLessThan(io.stateBytesWritten, 4096)
        XCTAssertEqual(network.methods["PROPFIND", default: 0], strongPUTETag ? 0 : 2)
        XCTAssertEqual(network.methods["GET", default: 0], strongPUTETag ? 0 : 1)
        let final = try await session.snapshot()
        XCTAssertEqual(final.documents.filter { $0.kind == .org }.count, 1000)
        XCTAssertEqual(final.documents.first { $0.path == original.path }?.contents, edited)
        let remote = await server.contents(original.path)
        XCTAssertEqual(remote, Data(edited.utf8))
        XCTAssertEqual(network.methods["PUT"], 1)
        await session.close()
    }
}

private struct BenchmarkReport: Codable {
    var strongPUTETag: Bool
    var files: Int
    var workspaceBytes: Int
    var seconds: Double
    var network: BenchmarkDAVServer.Metrics
    var localIO: LocalStoreIOMetrics
    var walFileGrowthBytes: Int
}

/// Exercises the real DAV parser, conditional writes and verification requests.
/// There is no artificial latency; elapsed time measures client work only.
private actor BenchmarkDAVServer: StorageHTTPTransport {
    struct Metrics: Codable, Sendable {
        var methods: [String: Int] = [:]
        var requestBytes = 0
        var responseBytes = 0
    }
    nonisolated let root = URL(string: "https://benchmark.example/org/")!
    private var files: [String: Data] = [:]
    private var versions: [String: Int] = [:]
    private var directories: Set<String> = [""]
    private(set) var metrics = Metrics()
    private let strongPUTETag: Bool

    init(fileCount: Int, bytesPerFile: Int, strongPUTETag: Bool) {
        self.strongPUTETag = strongPUTETag
        for index in 0..<fileCount {
            let parent = "group\(index / 100)"
            let path = parent + "/file\(index).org"
            let header = "* File \(index)\n"
            files[path] = Data((header + String(repeating: "x", count: bytesPerFile - header.utf8.count)).utf8)
            versions[path] = 1
            directories.insert(parent)
        }
    }

    func resetMetrics() { metrics = Metrics() }
    func contents(_ path: String) -> Data? { files[path] }

    func send(_ request: URLRequest, maxBytes: Int) throws -> StorageHTTPResponse {
        let url = try XCTUnwrap(request.url)
        let path = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let method = request.httpMethod ?? "GET"
        metrics.methods[method, default: 0] += 1
        metrics.requestBytes += request.httpBody?.count ?? 0
        let revision = versions[path].map { "\"version-\($0)\"" }
        let response: StorageHTTPResponse
        switch method {
        case "PROPFIND":
            guard directories.contains(path) || files[path] != nil else {
                return .init(status: 404, headers: [:], data: Data())
            }
            var paths = [path]
            if request.value(forHTTPHeaderField: "Depth") == "1" {
                paths += (Array(directories) + Array(files.keys)).filter {
                    $0 != path && ($0 as NSString).deletingLastPathComponent == path
                }.sorted()
            }
            let entries = paths.map { item -> String in
                let collection = directories.contains(item) ? "<d:collection/>" : ""
                let etag = versions[item].map { "<d:getetag>&quot;version-\($0)&quot;</d:getetag>" } ?? ""
                return """
                <d:response><d:href>\(root.path)/\(item)</d:href><d:propstat><d:prop>
                <d:resourcetype>\(collection)</d:resourcetype>\(etag)
                <d:getcontentlength>\(files[item]?.count ?? 0)</d:getcontentlength>
                </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
                """
            }.joined()
            let xml = "<d:multistatus xmlns:d=\"DAV:\">" + entries + "</d:multistatus>"
            response = .init(status: 207, headers: [:], data: Data(xml.utf8))
        case "GET":
            guard let data = files[path] else { return .init(status: 404, headers: [:], data: Data()) }
            if let expected = request.value(forHTTPHeaderField: "If-Match"), expected != revision {
                return .init(status: 412, headers: [:], data: Data())
            }
            response = .init(status: 200, headers: ["etag": revision!], data: data)
        case "PUT":
            if let expected = request.value(forHTTPHeaderField: "If-Match"), expected != revision {
                return .init(status: 412, headers: [:], data: Data())
            }
            if request.value(forHTTPHeaderField: "If-None-Match") == "*", files[path] != nil {
                return .init(status: 412, headers: [:], data: Data())
            }
            files[path] = request.httpBody ?? Data()
            versions[path, default: 0] += 1
            response = .init(status: 204,
                headers: strongPUTETag ? ["etag": "\"version-\(versions[path]!)\""] : [:], data: Data())
        default: throw StorageError.invalidResponse
        }
        guard response.data.count <= maxBytes else { throw StorageError.tooLarge }
        metrics.responseBytes += response.data.count
        return response
    }
}
