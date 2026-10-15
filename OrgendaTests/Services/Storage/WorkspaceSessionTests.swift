import Foundation
import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceSessionTests: XCTestCase {
    private var cache: URL!
    private var connection: StorageConnection!

    override func setUpWithError() throws {
        cache = FileManager.default.temporaryDirectory.appendingPathComponent("SessionTests-" + UUID().uuidString)
        connection = StorageConnection(provider: .webDAV, displayName: "Test", rootID: "/org")
    }

    override func tearDownWithError() throws {
        if let cache { try? FileManager.default.removeItem(at: cache) }
    }

    private func session(_ backend: SessionFakeBackend) throws -> WorkspaceSession {
        try WorkspaceSession(connection: connection, cacheDirectory: cache, remote: backend,
                             recoveryDirectory: cache.appendingPathComponent("Recovery"))
    }

    func testRecoveryCopiesRetainDistinctDraftsAndWorkspaceIdentities() async throws {
        let first = try session(SessionFakeBackend([:]))
        try await first.preserveUnsaved("* First draft 中文\n", path: "notes/inbox.org")
        try await first.preserveUnsaved("* First draft 中文\n", path: "notes/inbox.org")
        try await first.preserveUnsaved("* Second draft\n", path: "notes/inbox.org")
        let firstIdentity = connection.identity
        connection = StorageConnection(provider: .webDAV, displayName: "Other", rootID: "/other")
        let second = try session(SessionFakeBackend([:]))
        try await second.preserveUnsaved("* First draft 中文\n", path: "notes/inbox.org")

        let recovery = cache.appendingPathComponent("Recovery")
        let copies = try FileManager.default.subpathsOfDirectory(atPath: recovery.path).filter { $0.hasSuffix(".txt") }
        XCTAssertEqual(copies.count, 3, "Repeated recovery must retain each version and each workspace independently")
        var drafts: [String: Set<String>] = [:]
        for copy in copies {
            let url = recovery.appendingPathComponent(copy)
            let metadata = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json"))) as? [String: String])
            XCTAssertEqual(metadata["path"], "notes/inbox.org")
            let identity = try XCTUnwrap(metadata["workspace"])
            drafts[identity, default: []].insert(try String(contentsOf: url, encoding: .utf8))
        }
        XCTAssertEqual(drafts[firstIdentity], ["* First draft 中文\n", "* Second draft\n"])
        XCTAssertEqual(drafts[connection.identity], ["* First draft 中文\n"])
    }

    func testExternalChangePreservesBothVersionsAndResolvesUsingLatestRemote() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Local\n", expectedContents: "* Base\n")
        await backend.replace("inbox.org", contents: "* External\n")
        do { try await workspace.synchronize(); XCTFail("Concurrent edits must conflict") }
        catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let conflict = try await workspace.snapshot()
        XCTAssertEqual(conflict.documents.first?.contents, "* Local\n")
        XCTAssertEqual(conflict.conflicts.first?.remoteContents, "* External\n")
        await backend.replace("inbox.org", contents: "* Even newer\n")
        do {
            try await workspace.resolveConflict(path: "inbox.org", resolution: .useRemote)
            XCTFail("A choice must not silently apply to a newer remote version")
        } catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let updatedConflict = try await workspace.snapshot()
        XCTAssertEqual(updatedConflict.documents.first?.contents, "* Local\n")
        XCTAssertEqual(updatedConflict.conflicts.first?.remoteContents, "* Even newer\n")
        try await workspace.resolveConflict(path: "inbox.org", resolution: .useRemote)
        let resolved = try await workspace.snapshot()
        XCTAssertEqual(resolved.documents.first?.contents, "* Even newer\n")
        XCTAssertTrue(resolved.pendingPaths.isEmpty)
        let files = try FileManager.default.subpathsOfDirectory(atPath: cache.path)
        XCTAssertTrue(files.contains { $0.contains("Recovery/") && $0.hasSuffix("/inbox.org") })
        let remoteCopy = try XCTUnwrap(files.first { $0.contains("Recovery/") && $0.hasSuffix("Remote Versions/inbox.org") })
        let localCopy = try XCTUnwrap(files.first { $0.contains("Recovery/") && $0.hasSuffix("Local Files/inbox.org") })
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent(remoteCopy), encoding: .utf8), "* Even newer\n")
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent(localCopy), encoding: .utf8), "* Local\n")
    }

    func testFailedCompleteDownloadDoesNotRemovePreviouslyLoadedDocuments() async throws {
        let backend = SessionFakeBackend(["a.org": "* A\n", "b.org": "* B\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        await backend.remove("a.org")
        await backend.replace("b.org", contents: "* Updated\n")
        await backend.failDownload("b.org")
        do { try await workspace.synchronize(); XCTFail("A partial snapshot must fail") }
        catch {}
        let snapshot = try await workspace.snapshot()
        XCTAssertEqual(snapshot.documents.map(\.path), ["a.org", "b.org"])
        XCTAssertEqual(snapshot.documents.last?.contents, "* B\n")
        let reopened = try session(backend)
        let restored = try await reopened.snapshot()
        XCTAssertEqual(restored.documents, snapshot.documents)
    }

    func testEditDuringUploadRemainsPendingAgainstAcknowledgedRevision() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* First\n", expectedContents: "* Base\n")
        await backend.pauseNextUpload()
        let syncing = Task { try await workspace.synchronize() }
        await backend.waitForUpload()
        try await workspace.write(path: "inbox.org", contents: "* Second\n", expectedContents: "* First\n")
        await backend.resumeUpload()
        try await syncing.value
        let pending = try await workspace.snapshot()
        XCTAssertEqual(pending.documents.first?.contents, "* Second\n")
        XCTAssertEqual(pending.pendingPaths, ["inbox.org"])
        try await workspace.synchronize()
        let remoteText = await backend.contents("inbox.org")
        let completed = try await workspace.snapshot()
        XCTAssertEqual(remoteText, "* Second\n")
        XCTAssertTrue(completed.pendingPaths.isEmpty)
    }

    func testLostUploadResponseIsReconciledWithoutDuplicateCreation() async throws {
        let backend = SessionFakeBackend()
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "journal/2026.org", contents: "* Today\n", expectedContents: nil)
        await backend.loseNextUploadResponse()
        _ = try? await workspace.synchronize()
        let reopened = try session(backend)
        try await reopened.synchronize()
        let snapshot = try await reopened.snapshot()
        let uploads = await backend.uploadCount
        XCTAssertTrue(snapshot.pendingPaths.isEmpty)
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(snapshot.documents.first { $0.path == "journal/2026.org" }?.contents, "* Today\n")
    }

    func testUseLocalRefusesAnUnseenNewRemoteRevision() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Draft\n", expectedContents: "* Base\n")
        await backend.replace("inbox.org", contents: "* First remote edit\n")
        _ = try? await workspace.synchronize()
        await backend.replace("inbox.org", contents: "* Unseen remote edit\n")
        do { try await workspace.resolveConflict(path: "inbox.org", resolution: .useLocal); XCTFail("Unseen revision overwritten") }
        catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let actual = await backend.contents("inbox.org")
        let snapshot = try await workspace.snapshot()
        XCTAssertEqual(actual, "* Unseen remote edit\n")
        XCTAssertEqual(snapshot.conflicts.first?.remoteContents, actual)
        XCTAssertEqual(snapshot.documents.first?.contents, "* Draft\n")
    }

    func testDraftAfterAmbiguousMoveFollowsMovedFileInsteadOfRecreatingSource() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Task\n"])
        await backend.addDirectory("archive")
        let workspace = try session(backend)
        try await workspace.synchronize()
        let expected = try await workspace.load().filter { $0.path == "inbox.org" }
        await backend.loseNextMoveResponse()
        _ = try? await workspace.move(path: "inbox.org", to: "archive/inbox.org", expected: expected)
        try await workspace.write(path: "inbox.org", contents: "* New draft\n", expectedContents: "* Task\n")
        let reopened = try session(backend)
        try await reopened.synchronize()
        let source = await backend.contents("inbox.org")
        let destination = await backend.contents("archive/inbox.org")
        let snapshot = try await reopened.snapshot()
        XCTAssertNil(source)
        XCTAssertEqual(destination, "* New draft\n")
        XCTAssertTrue(snapshot.pendingPaths.isEmpty)
        XCTAssertTrue(snapshot.conflicts.isEmpty)
    }

    func testHeadingMoveRecoversLostDestinationUploadWithoutDuplicateAppend() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Move me\n* Remaining\n", "archive.org": "* Older\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        await backend.loseNextUploadResponse()
        let source = WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "* Remaining\n", kind: .org)
        let target = WorkspaceDocument(path: "archive.org", title: "Archive", contents: "* Older\n* Move me\n", kind: .org)
        _ = try? await workspace.commitOnlineMove(source: source, destination: target,
            expectedSource: "* Move me\n* Remaining\n", expectedDestination: "* Older\n")
        let reopened = try session(backend)
        try await reopened.synchronize()
        let sourceText = await backend.contents("inbox.org")
        let destinationText = await backend.contents("archive.org")
        let uploads = await backend.uploadCount
        XCTAssertEqual(sourceText, source.contents)
        XCTAssertEqual(destinationText, target.contents)
        XCTAssertEqual(uploads, 2)
    }

    func testHeadingMoveKeepsSourceWhenCommittedDestinationChangesBeforeRecovery() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Move me\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        await backend.failUpload("inbox.org")
        let source = WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "", kind: .org)
        let target = WorkspaceDocument(path: "archive.org", title: "Archive", contents: "* Move me\n", kind: .org)
        _ = try? await workspace.commitOnlineMove(source: source, destination: target,
            expectedSource: "* Move me\n", expectedDestination: nil)
        await backend.replace("archive.org", contents: "* External replacement\n")
        let reopened = try session(backend)
        do { try await reopened.synchronize(); XCTFail("Source removed after destination changed") }
        catch {}
        let original = await backend.contents("inbox.org")
        XCTAssertEqual(original, "* Move me\n")
        await backend.failUpload(nil)
        try await reopened.synchronize()
    }

    func testDraftFromUIBeforeRefreshIsCommittedAsConflictAgainstUnseenVersion() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* A\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        await backend.replace("inbox.org", contents: "* B\n")
        await backend.pauseNextDownload("inbox.org")
        let refreshing = Task { try await workspace.synchronize() }
        await backend.waitForDownload()
        // The UI edits A while a refreshed B is downloading. Its debounce may
        // commit only after the refresh has advanced the session baseline.
        let uiDraft = "* Local based on A\n"
        await backend.resumeDownload()
        try await refreshing.value
        try await workspace.write(path: "inbox.org", contents: uiDraft, expectedContents: "* A\n")
        let reopened = try session(backend)
        do { try await reopened.synchronize(); XCTFail("Stale UI save silently overwrote B") }
        catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let snapshot = try await reopened.snapshot()
        let cloud = await backend.contents("inbox.org")
        XCTAssertEqual(snapshot.documents.first?.contents, uiDraft)
        XCTAssertEqual(snapshot.conflicts.first?.remoteContents, "* B\n")
        XCTAssertEqual(cloud, "* B\n")
        XCTAssertEqual(snapshot.pendingPaths, ["inbox.org"])
    }

}

private actor SessionFakeBackend: RemoteWorkspaceBackend {
    struct Item { var file: RemoteFile; var data: Data }
    var items: [String: Item] = [:]
    var failingDownload: String?
    var failingUpload: String?
    var paused = false
    var uploadStarted = false
    var uploadWaiters: [CheckedContinuation<Void, Never>] = []
    var resume: CheckedContinuation<Void, Never>?
    var loseUploadResponse = false
    var loseMoveResponse = false
    var uploadCount = 0
    var pausedDownloadPath: String?
    var downloadStarted = false
    var downloadWaiters: [CheckedContinuation<Void, Never>] = []
    var downloadResume: CheckedContinuation<Void, Never>?

    init(_ texts: [String: String] = [:]) {
        for (path, text) in texts {
            items[path] = Item(file: RemoteFile(id: path, path: path, isDirectory: false,
                revision: UUID().uuidString, size: Int64(text.utf8.count)), data: Data(text.utf8))
        }
    }

    func scan() throws -> RemoteScan {
        return RemoteScan(files: items.values.map(\.file))
    }
    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        if file.path == pausedDownloadPath {
            downloadStarted = true
            for waiter in downloadWaiters { waiter.resume() }
            downloadWaiters.removeAll()
            await withCheckedContinuation { downloadResume = $0 }
            pausedDownloadPath = nil
        }
        if file.path == failingDownload { throw StorageError.offline }
        guard let item = items[file.path] else { throw StorageError.http(404) }
        guard item.data.count <= maxBytes else { throw StorageError.tooLarge }
        return RemoteDownload(file: item.file, data: item.data)
    }
    func upload(path: String, data: Data, existing: RemoteFile?) async throws -> RemoteFile {
        if path == failingUpload { throw StorageError.offline }
        if paused {
            uploadStarted = true
            for waiter in uploadWaiters { waiter.resume() }
            uploadWaiters.removeAll()
            await withCheckedContinuation { resume = $0 }
            paused = false
        }
        let old = items[path]
        guard old?.file.id == existing?.id, old?.file.revision == existing?.revision else {
            throw StorageError.conflict(path)
        }
        let file = RemoteFile(id: path, path: path, isDirectory: false,
                              revision: UUID().uuidString, size: Int64(data.count))
        items[path] = Item(file: file, data: data)
        uploadCount += 1
        if loseUploadResponse { loseUploadResponse = false; throw StorageError.offline }
        return file
    }
    func createDirectory(path: String) throws -> RemoteFile {
        if let existing = items[path] {
            guard existing.file.isDirectory else { throw StorageError.conflict(path) }
            return existing.file
        }
        return addDirectory(path)
    }
    func move(_ file: RemoteFile, to path: String) throws -> RemoteFile {
        guard let old = items[file.path], old.file.id == file.id, old.file.revision == file.revision,
              items[path] == nil else { throw StorageError.conflict(file.path) }
        for (oldPath, var item) in items.filter({ WorkspaceFileTransfer.contains($0.key, in: file.path) }) {
            items.removeValue(forKey: oldPath)
            let newPath = path + oldPath.dropFirst(file.path.count)
            item.file.id = newPath
            item.file.path = newPath
            items[newPath] = item
        }
        if loseMoveResponse { loseMoveResponse = false; throw StorageError.offline }
        return items[path]!.file
    }
    @discardableResult
    func addDirectory(_ path: String) -> RemoteFile {
        let file = RemoteFile(id: path, path: path, isDirectory: true, revision: UUID().uuidString)
        items[path] = Item(file: file, data: Data())
        return file
    }
    func replace(_ path: String, contents: String) {
        items[path] = Item(file: RemoteFile(id: path, path: path, isDirectory: false,
            revision: UUID().uuidString, size: Int64(contents.utf8.count)), data: Data(contents.utf8))
    }
    func remove(_ path: String) { items.removeValue(forKey: path) }
    func contents(_ path: String) -> String? { items[path].flatMap { String(data: $0.data, encoding: .utf8) } }
    func failDownload(_ path: String) { failingDownload = path }
    func failUpload(_ path: String?) { failingUpload = path }
    func pauseNextDownload(_ path: String) { pausedDownloadPath = path; downloadStarted = false }
    func waitForDownload() async {
        if downloadStarted { return }
        await withCheckedContinuation { downloadWaiters.append($0) }
    }
    func resumeDownload() { downloadResume?.resume(); downloadResume = nil }
    func pauseNextUpload() { paused = true; uploadStarted = false }
    func waitForUpload() async {
        if uploadStarted { return }
        await withCheckedContinuation { uploadWaiters.append($0) }
    }
    func resumeUpload() { resume?.resume(); resume = nil }
    func loseNextUploadResponse() { loseUploadResponse = true }
    func loseNextMoveResponse() { loseMoveResponse = true }
}
