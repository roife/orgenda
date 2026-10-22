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

    func testNestedEscapingSymlinkRejectsScanAndWrites() async throws {
        let outside = temporaryDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("private.org")
        try Data("original".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        let store = WorkspaceFileStore(rootURL: root)

        do {
            _ = try await store.scan(known: [:])
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

    func testInvalidUTF8FailsWholeScanInsteadOfReturningPartialInventory() async throws {
        try fixture("a-valid.org", contents: "* TODO Valid\n")
        try Data([0xFF, 0xFE, 0x80]).write(to: root.appendingPathComponent("z-invalid.org"))
        do {
            _ = try await WorkspaceFileStore(rootURL: root).scan(known: [:])
            XCTFail("A partial scan must not be reported as successful")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .invalidUTF8("z-invalid.org"))
        }
    }

    func testHiddenCloudPlaceholderDoesNotLookLikeDeletion() async throws {
        try fixture(".inbox.org.icloud", contents: "provider placeholder")
        do {
            _ = try await WorkspaceFileStore(rootURL: root).scan(known: [:])
            XCTFail("An evicted document must not silently disappear from the workspace")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .unreadable(".inbox.org.icloud"))
        }
    }

    func testExplicitChangeReadsReplacementWithUnchangedSizeAndModificationDate() async throws {
        try fixture("a.org", contents: "* Before\n")
        let store = WorkspaceFileStore(rootURL: root)
        let first = try await store.scan(known: [:])
        let originalDate = try XCTUnwrap(first.entries["a.org"]?.file.modifiedAt)
        try fixture("a.org", contents: "* After_\n")
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: root.appendingPathComponent("a.org").path)
        let targeted = try await store.scan(known: first.entries, changedPaths: ["a.org"])
        XCTAssertEqual(targeted.changedContents["a.org"], Data("* After_\n".utf8))
    }

    private func fixture(_ path: String, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
