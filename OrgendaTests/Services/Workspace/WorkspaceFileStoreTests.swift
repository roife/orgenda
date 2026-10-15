import XCTest
@testable import Orgenda

final class WorkspaceFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var root: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrgendaWorkspaceFileTests-" + UUID().uuidString)
        root = temporaryDirectory.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testStaleEditAndCreationNeverOverwriteExternalContents() async throws {
        let store = WorkspaceFileStore(rootURL: root)
        try fixture("inbox.org", contents: "* TODO External update\n")

        for baseline: String? in ["* TODO Old\n", nil] {
            do {
                try await store.write(path: "inbox.org", contents: "* DONE Local\n", expectedContents: baseline)
                XCTFail("An external file must not be overwritten")
            } catch let failure as WorkspaceFileStore.Failure {
                XCTAssertEqual(failure, .conflict("inbox.org"))
            }
        }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8),
                       "* TODO External update\n")
    }

    func testComparisonDetectsDifferentUnicodeBytes() async throws {
        try fixture("unicode.org", contents: "* TODO e\u{301}\n")
        let store = WorkspaceFileStore(rootURL: root)
        do {
            try await store.write(path: "unicode.org", contents: "* DONE é\n", expectedContents: "* TODO é\n")
            XCTFail("Canonical string equivalence must not conceal a byte-level external edit")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .conflict("unicode.org"))
        }
    }

    func testNestedEscapingSymlinkRejectsImportAndWrites() async throws {
        let outside = temporaryDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("private.org")
        try Data("original".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        let store = WorkspaceFileStore(rootURL: root)

        do {
            _ = try await store.load()
            XCTFail("Escaping folder link accepted")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .unsafePath("linked"))
        }
        for path in ["linked/private.org", "linked/new/created.org"] {
            do {
                try await store.write(path: path, contents: "changed", expectedContents: nil)
                XCTFail("Escaping write accepted")
            } catch let failure as WorkspaceFileStore.Failure {
                XCTAssertEqual(failure, .unsafePath(path))
            }
        }
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("new").path))
    }

    func testInvalidUTF8FailsWholeLoadInsteadOfReturningPartialSnapshot() async throws {
        try fixture("a-valid.org", contents: "* TODO Valid\n")
        try Data([0xFF, 0xFE, 0x80]).write(to: root.appendingPathComponent("z-invalid.org"))
        do {
            _ = try await WorkspaceFileStore(rootURL: root).load()
            XCTFail("A partial load must not be reported as successful")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .invalidUTF8("z-invalid.org"))
        }
    }

    func testHiddenCloudPlaceholderDoesNotLookLikeDeletion() async throws {
        try fixture(".inbox.org.icloud", contents: "provider placeholder")
        do {
            _ = try await WorkspaceFileStore(rootURL: root).load()
            XCTFail("An evicted document must not silently disappear from the workspace")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .unreadable("inbox.org"))
        }
    }

    func testMetadataFingerprintSkipsReadsAndExplicitChangeBypassesIt() async throws {
        try fixture("a.org", contents: "* Before\n")
        try fixture("b.org", contents: "* Stable\n")
        let store = WorkspaceFileStore(rootURL: root)
        let first = try await store.scan(known: [:])
        XCTAssertEqual(first.changedContents.count, 2)
        let unchanged = try await store.scan(known: first.entries)
        XCTAssertTrue(unchanged.changedContents.isEmpty)
        let originalDate = try XCTUnwrap(first.entries["a.org"]?.file.modifiedAt)
        try fixture("a.org", contents: "* After_\n")
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: root.appendingPathComponent("a.org").path)
        let targeted = try await store.scan(known: first.entries, changedPaths: ["a.org"])
        XCTAssertEqual(Set(targeted.changedContents.keys), ["a.org"])
        XCTAssertEqual(targeted.changedContents["a.org"], Data("* After_\n".utf8))
        XCTAssertEqual(targeted.entries["b.org"], first.entries["b.org"])
    }

    func testFolderOperationsCanQueueOfflineAndReplayWithSameTrashIdentity() async throws {
        try fixture("inbox.org", contents: "* Keep me\n")
        let connection = StorageConnection(provider: .local, displayName: "Folder", rootID: root.path)
        let session = try LocalStore(connection: connection, cacheDirectory: temporaryDirectory.appendingPathComponent("Cache"),
            folder: WorkspaceFileStore(rootURL: root))
        try await session.synchronize()
        let loaded = try await session.document(at: "inbox.org")
        let document = try XCTUnwrap(loaded)
        let unavailable = temporaryDirectory.appendingPathComponent("unavailable")
        try FileManager.default.moveItem(at: root, to: unavailable)
        let deleted = try await session.trash(document: document, expected: [document])
        try await session.restore(deleted)
        let local = try await session.snapshot()
        XCTAssertEqual(local.documents.first?.contents, document.contents)
        XCTAssertTrue(local.hasPendingOperation)
        try FileManager.default.moveItem(at: unavailable, to: root)
        try await session.synchronize()
        let final = try await session.snapshot()
        XCTAssertFalse(final.hasPendingOperation)
        XCTAssertEqual(final.documents.first?.id, document.id)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8), document.contents)
        await session.close()
    }

    private func fixture(_ path: String, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
