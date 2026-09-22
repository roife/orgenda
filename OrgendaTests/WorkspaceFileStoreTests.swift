import XCTest
@testable import Orgenda

final class WorkspaceFileStoreTests: XCTestCase {
    func testFileMovePreservesFolderAttachmentsAndHiddenFiles() async throws {
        try fixture("source/nested/task.org", contents: "* TODO 中文\r\n")
        try fixture("source/.metadata", contents: "hidden")
        let bytes = Data([0, 255, 1, 128])
        try bytes.write(to: root.appendingPathComponent("source/image.png"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("target"), withIntermediateDirectories: true)
        let disk = WorkspaceFileStore(rootURL: root)
        let expected = try await disk.load().filter { WorkspaceFileTransfer.contains($0.path, in: "source") }
        try await disk.move(path: "source", to: "target/source", expected: expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("source").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("target/source/image.png")), bytes)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("target/source/.metadata"), encoding: .utf8), "hidden")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("target/source/nested/task.org")), Data("* TODO 中文\r\n".utf8))
    }

    func testFileMoveRejectsCollisionDescendantsAndStaleChildren() async throws {
        try fixture("source/task.org", contents: "* TODO Original\n")
        try fixture("target/task.org", contents: "* TODO Destination\n")
        let disk = WorkspaceFileStore(rootURL: root)
        let source = try await disk.load().filter { WorkspaceFileTransfer.contains($0.path, in: "source") }
        do {
            try await disk.move(path: "source", to: "source/child", expected: source)
            XCTFail("Moved a folder into itself")
        } catch {}
        do {
            try await disk.move(path: "source/task.org", to: "target/task.org", expected: source.filter { $0.kind == .org })
            XCTFail("Overwrote a destination")
        } catch {}
        try fixture("source/new.org", contents: "* New child\n")
        do {
            try await disk.move(path: "source", to: "target/source", expected: source)
            XCTFail("Moved a stale subtree")
        } catch {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("target/task.org"), encoding: .utf8), "* TODO Destination\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("source/new.org").path))
    }

    func testFolderTrashPersistsAcrossStoreInstancesAndRestoresExactBytes() async throws {
        try fixture("notes/task.org", contents: "* TODO e\u{301}\n")
        try fixture("notes/.config", contents: "keep")
        let disk = WorkspaceFileStore(rootURL: root)
        let before = try await disk.load()
        let folder = try XCTUnwrap(before.first { $0.path == "notes" })
        let entry = try await disk.trash(document: folder, expected: before)
        let empty = try await disk.load()
        XCTAssertTrue(empty.isEmpty)
        let reopened = WorkspaceFileStore(rootURL: root)
        let deleted = try await reopened.deletedEntries()
        XCTAssertEqual(deleted, [entry])
        try await reopened.restore(entry)
        let restored = try await reopened.load()
        XCTAssertTrue(WorkspaceFileTransfer.matches(before, restored))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes/.config"), encoding: .utf8), "keep")
        let remaining = try await reopened.deletedEntries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRestoreNeverOverwritesRecreatedFile() async throws {
        try fixture("task.org", contents: "* Original\n")
        let disk = WorkspaceFileStore(rootURL: root)
        let files = try await disk.load()
        let entry = try await disk.trash(document: files[0], expected: files)
        try fixture("task.org", contents: "* New file\n")
        do { try await disk.restore(entry); XCTFail("Replaced the new file") } catch {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("task.org"), encoding: .utf8), "* New file\n")
        let retained = try await disk.deletedEntries()
        XCTAssertEqual(retained, [entry])
    }

    func testFileMoveRejectsSymlinkDestination() async throws {
        try fixture("task.org", contents: "* Original\n")
        let outside = temporaryDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let disk = WorkspaceFileStore(rootURL: root)
        let files = try await disk.load()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        do { try await disk.move(path: "task.org", to: "linked/task.org", expected: files); XCTFail("Escaping move accepted") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("task.org").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("task.org").path))
    }

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

    func testImportsNestedOrgMarkdownAndFoldersWithoutChangingBytes() async throws {
        let org = "#+title: 测试\r\n* TODO 文本 🧪 :work:\r\n"
        try fixture("inbox.org", contents: org)
        try fixture("notes/reading.MD", contents: "# Reading\n")
        try fixture("notes/deep/context.markdown", contents: "Context\n")
        try fixture("notes/image.png", contents: "ignored")
        try fixture(".hidden/private.org", contents: "* Hidden\n")

        let documents = try await WorkspaceFileStore(rootURL: root).load()

        XCTAssertEqual(documents.map(\.path), [
            "inbox.org", "notes", "notes/deep", "notes/deep/context.markdown", "notes/reading.MD"
        ])
        XCTAssertEqual(documents.first?.contents, org)
        XCTAssertEqual(documents.first { $0.path == "notes" }?.kind, .folder)
        XCTAssertEqual(documents.first { $0.path == "notes/reading.MD" }?.kind, .markdown)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inbox.org")), Data(org.utf8))
    }

    func testCreatesNestedFileAndPersistsAnEditAcrossNewStoreInstance() async throws {
        let store = WorkspaceFileStore(rootURL: root)
        let original = "* TODO 新任务 🧪\n"
        let edited = "* DONE 新任务 🧪\n:PROPERTIES:\n:CUSTOM: keep\n:END:\n"
        try await store.write(path: "projects/work.org", contents: original, expectedContents: nil)
        try await store.write(path: "projects/work.org", contents: edited, expectedContents: original)

        let reopened = try await WorkspaceFileStore(rootURL: root).load()
        XCTAssertEqual(reopened.first { $0.path == "projects/work.org" }?.contents, edited)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("projects/work.org")), Data(edited.utf8))
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

    func testMatchingRemoteContentCompletesPreviouslyConflictingSave() async throws {
        let contents = "* TODO Matching resolution\n"
        try fixture("inbox.org", contents: contents)
        try await WorkspaceFileStore(rootURL: root).write(path: "inbox.org", contents: contents, expectedContents: "Old baseline")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8), contents)
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

    func testReloadReflectsDeletionAndStaleWriteDoesNotResurrectFile() async throws {
        try fixture("inbox.org", contents: "* TODO Original\n")
        let store = WorkspaceFileStore(rootURL: root)
        let firstLoad = try await store.load()
        XCTAssertEqual(firstLoad.count, 1)
        try FileManager.default.removeItem(at: root.appendingPathComponent("inbox.org"))
        let reloaded = try await store.load()
        XCTAssertTrue(reloaded.isEmpty)
        do {
            try await store.write(path: "inbox.org", contents: "* DONE Local\n", expectedContents: "* TODO Original\n")
            XCTFail("An externally deleted file must not be recreated by a stale edit")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .conflict("inbox.org"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("inbox.org").path))
    }

    func testInvalidPathsCannotCreateFilesOutsideWorkspace() async throws {
        let store = WorkspaceFileStore(rootURL: root)
        for path in ["../outside.org", "/outside.org", "notes/../../outside.org", "notes//file.org", "./file.org", ""] {
            do {
                try await store.write(path: path, contents: "changed", expectedContents: nil)
                XCTFail("Unsafe path accepted: \(path)")
            } catch let failure as WorkspaceFileStore.Failure {
                XCTAssertEqual(failure, .unsafePath(path))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("outside.org").path))
    }

    func testSelectedRootSymlinkIsSupported() async throws {
        try fixture("inbox.org", contents: "* TODO Original\n")
        let link = temporaryDirectory.appendingPathComponent("selected-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let store = WorkspaceFileStore(rootURL: link)
        let imported = try await store.load()
        XCTAssertEqual(imported.first?.path, "inbox.org")
        try await store.write(path: "inbox.org", contents: "* DONE Saved\n", expectedContents: "* TODO Original\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8), "* DONE Saved\n")
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

    func testDirectorySymlinkCycleDoesNotHangImport() async throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        do {
            _ = try await WorkspaceFileStore(rootURL: root).load()
            XCTFail("Directory link cycle accepted")
        } catch let failure as WorkspaceFileStore.Failure {
            XCTAssertEqual(failure, .unsafePath("loop"))
        }
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

    func testMissingRootFailsInsteadOfReturningAnEmptySnapshot() async throws {
        try FileManager.default.removeItem(at: root)
        do {
            _ = try await WorkspaceFileStore(rootURL: root).load()
            XCTFail("An inaccessible root must not look like deletion of all files")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
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

    private func fixture(_ path: String, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
