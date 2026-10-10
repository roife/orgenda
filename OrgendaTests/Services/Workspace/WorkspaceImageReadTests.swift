import XCTest
@testable import Orgenda

final class WorkspaceImageReadTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var root: URL!
    private let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0, 0xFF, 0x80, 0x01])

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrgendaWorkspaceImageTests-" + UUID().uuidString)
        root = temporaryDirectory.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testReadsExactBinaryBytesWithoutIndexingImageAsDocument() async throws {
        try fixture("images/测试 photo.png")
        let store = WorkspaceFileStore(rootURL: root)

        let data = try await store.readImageData(path: "images/测试 photo.png")
        let documents = try await store.load()

        XCTAssertEqual(data, imageBytes)
        XCTAssertFalse(documents.contains { $0.path == "images/测试 photo.png" })
    }

    func testReadsHiddenAttachmentFoldersDirectly() async throws {
        try fixture(".attach/ab/cdef/screenshot.png")
        let store = WorkspaceFileStore(rootURL: root)

        let data = try await store.readImageData(path: ".attach/ab/cdef/screenshot.png")
        let documents = try await store.load()

        XCTAssertEqual(data, imageBytes)
        XCTAssertTrue(documents.isEmpty)
    }

    func testReadsNormalizedAbsoluteAndAliasedWorkspacePaths() async throws {
        let image = try fixture("images/photo.png")
        let alias = temporaryDirectory.appendingPathComponent("selected-folder")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        for (selectedRoot, path) in [
            (root!, "notes/../images/photo.png"), (root!, image.path),
            (alias, alias.appendingPathComponent("images/photo.png").path)
        ] {
            let data = try await WorkspaceFileStore(rootURL: selectedRoot).readImageData(path: path)
            XCTAssertEqual(data, imageBytes, path)
        }
    }

    func testRejectsEscapingSymlinksAndInvalidWorkspacePaths() async throws {
        let outside = temporaryDirectory.appendingPathComponent("outside.png")
        try imageBytes.write(to: outside)
        // A sibling sharing the workspace prefix is still outside the root.
        let prefixSibling = temporaryDirectory.appendingPathComponent("workspace-copy/photo.png")
        try FileManager.default.createDirectory(at: prefixSibling.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imageBytes.write(to: prefixSibling)
        let outsideFolder = temporaryDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        try imageBytes.write(to: outsideFolder.appendingPathComponent("photo.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outsideFolder)
        let store = WorkspaceFileStore(rootURL: root)
        for path in ["../outside.png", outside.path, prefixSibling.path, "images/../../outside.png",
                     "linked/photo.png", root.appendingPathComponent("linked/photo.png").path,
                     "", "images/\0photo.png"] {
            do {
                _ = try await store.readImageData(path: path)
                XCTFail("Accepted unsafe path: \(path.debugDescription)")
            } catch let failure as WorkspaceFileStore.Failure {
                XCTAssertEqual(failure, .unsafePath(path), path.debugDescription)
            }
        }
    }

    func testMissingImageThrowsInsteadOfReturningEmptyData() async throws {
        do {
            _ = try await WorkspaceFileStore(rootURL: root).readImageData(path: "missing.png")
            XCTFail("A missing image should report an error")
        } catch {}
    }

    func testRejectsDirectory() async throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        do {
            _ = try await WorkspaceFileStore(rootURL: root).readImageData(path: "images")
            XCTFail("Tried to read a directory as an image")
        } catch let failure as WorkspaceFileStore.ImageReadFailure {
            XCTAssertEqual(failure, .notRegularFile)
        }
    }

    func testRejectsOversizedImageButAllowsExactLimit() async throws {
        try fixture("photo.png")
        let store = WorkspaceFileStore(rootURL: root)

        do {
            _ = try await store.readImageData(path: "photo.png", maxBytes: imageBytes.count - 1)
            XCTFail("Read an image beyond the allowed byte budget")
        } catch let failure as WorkspaceFileStore.ImageReadFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
        let exact = try await store.readImageData(path: "photo.png", maxBytes: imageBytes.count)
        XCTAssertEqual(exact, imageBytes)
    }

    func testReadsFileSpanningMultipleBoundedChunks() async throws {
        let bytes = Data(repeating: 0xAE, count: 160 * 1024)
        try fixture("large.png", bytes: bytes)

        let data = try await WorkspaceFileStore(rootURL: root).readImageData(path: "large.png", maxBytes: bytes.count)

        XCTAssertEqual(data, bytes)
    }

    @discardableResult
    private func fixture(_ path: String, bytes: Data? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (bytes ?? imageBytes).write(to: url)
        return url
    }
}
