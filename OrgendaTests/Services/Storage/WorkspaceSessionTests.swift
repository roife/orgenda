import Foundation
import SQLite3
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

    private func session(_ backend: SessionFakeBackend) throws -> LocalStore {
        try LocalStore(connection: connection, cacheDirectory: cache, remote: backend,
                             recoveryDirectory: cache.appendingPathComponent("Recovery"))
    }

    private func document(_ path: String, in workspace: LocalStore) async throws -> WorkspaceDocument {
        let loaded = try await workspace.document(at: path)
        return try XCTUnwrap(loaded)
    }

    func testFullRefreshDuringPushKeepsPullAndNewEdits() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* One\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Two\n", expectedContents: "* One\n")
        let engine = SyncEngine(store: workspace)
        await backend.pauseNextUpload()
        let pushing = await engine.schedule(.push)
        await backend.waitForUpload()
        try await workspace.write(path: "inbox.org", contents: "* Three\n", expectedContents: "* Two\n")
        await backend.replace("new.org", contents: "* Remote\n")
        let refresh = await engine.schedule(.full)
        await backend.resumeUpload()
        try await pushing.value
        try await refresh.value
        let contents = await backend.contents("inbox.org")
        XCTAssertEqual(contents, "* Three\n")
        let received = try await workspace.document(at: "new.org")
        XCTAssertEqual(received?.contents, "* Remote\n")
        await engine.stop()
    }

    func testDisjointRemoteEditsMergeButOverlappingAndUnicodeByteEditsConflict() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* One\n* Two\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Local one\n* Two\n", expectedContents: "* One\n* Two\n")
        await backend.replace("inbox.org", contents: "* One\n* Remote two\n")
        try await workspace.synchronize()
        let merged = await backend.contents("inbox.org")
        XCTAssertEqual(merged, "* Local one\n* Remote two\n")
        XCTAssertNil(WorkspaceTextMerge.merge(base: "* A\n", local: "* Local\n", remote: "* Remote\n"))
        XCTAssertNil(WorkspaceTextMerge.merge(base: "é\n", local: "e\u{301}\n", remote: "other\n"))
        XCTAssertEqual(WorkspaceTextMerge.merge(base: "a\nb", local: "A\nb", remote: "a\nB"), "A\nB")
    }

    func testRefileDependencyFollowsDestinationIdentityThroughQueuedMove() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Move\n", "archive.org": "* Existing\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        let source = WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "", kind: .org)
        let destination = WorkspaceDocument(path: "archive.org", title: "Archive", contents: "* Existing\n* Move\n", kind: .org)
        try await workspace.refile(source: source, destination: destination,
            expectedSource: "* Move\n", expectedDestination: "* Existing\n")
        let local = try await document("archive.org", in: workspace)
        try await workspace.move(path: "archive.org", to: "renamed.org", expected: [local])
        let reopened = try session(backend)
        try await reopened.synchronize()
        let savedSource = await backend.contents("inbox.org")
        let savedDestination = await backend.contents("renamed.org")
        let oldDestination = await backend.contents("archive.org")
        XCTAssertEqual(savedSource, "")
        XCTAssertEqual(savedDestination, destination.contents)
        XCTAssertNil(oldDestination)
    }

    func testEmptyFolderCollisionRemainsAResolvableOperationConflict() async throws {
        let backend = SessionFakeBackend()
        await backend.addDirectory("source")
        let workspace = try session(backend)
        try await workspace.synchronize()
        let folder = try await document("source", in: workspace)
        try await workspace.move(path: "source", to: "target", expected: [folder])
        await backend.addDirectory("target")
        do { try await workspace.synchronize(); XCTFail("The collision was ignored") }
        catch {}
        let reopened = try session(backend)
        let conflict = try await reopened.snapshot()
        XCTAssertEqual(conflict.conflicts.first?.path, "target")
        XCTAssertTrue(conflict.conflicts.first?.isOperation == true)
        try await reopened.resolveConflict(path: "target", resolution: .useRemote)
        let resolved = try await reopened.snapshot()
        XCTAssertTrue(resolved.conflicts.isEmpty)
        XCTAssertEqual(Set(resolved.documents.map(\.path)), ["source", "target"])
    }

    func testQueuedMoveConflictPreservesBothFilesAcrossRestart() async throws {
        let text = "* Unique private text 中文\n"
        let backend = SessionFakeBackend(["inbox.org": text])
        let workspace = try session(backend)
        try await workspace.synchronize()
        let original = try await document("inbox.org", in: workspace)
        await backend.setOffline(true)
        try await workspace.move(path: "inbox.org", to: "moved.org", expected: [original])
        await backend.setOffline(false)
        await backend.replace("inbox.org", contents: "* External\n")
        do { try await workspace.synchronize(); XCTFail("A changed source was moved") }
        catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let reopened = try session(backend)
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.documents.first { $0.path == "moved.org" }?.contents, text)
        XCTAssertEqual(snapshot.documents.first { $0.path == "inbox.org" }?.contents, "* External\n")
        XCTAssertEqual(snapshot.conflicts.first?.path, "moved.org")
    }

    func testInvalidInventoryBranchRetainsCacheAndDoesNotBlockHealthyUpload() async throws {
        let backend = SessionFakeBackend(["a.org": "* A\n", "b.org": "* B\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "b.org", contents: "* Local B\n", expectedContents: "* B\n")
        await backend.addAmbiguousPath("A.org")
        do { try await workspace.synchronize(); XCTFail("The invalid inventory was hidden") }
        catch {}
        let snapshot = try await workspace.snapshot()
        let remote = await backend.contents("b.org")
        XCTAssertEqual(snapshot.documents.first { $0.path == "a.org" }?.contents, "* A\n")
        XCTAssertFalse(snapshot.documents.contains { $0.path == "A.org" })
        XCTAssertEqual(remote, "* Local B\n")
        XCTAssertTrue(snapshot.pendingPaths.isEmpty)
        XCTAssertNotNil(snapshot.uploadErrors["a.org"])
    }

    func testOfflineMoveTrashRestoreQueueRetainsIdentityAndNewDraftAfterRestart() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        await backend.addDirectory("archive")
        let workspace = try session(backend)
        try await workspace.synchronize()
        let original = try await document("inbox.org", in: workspace)
        await backend.setOffline(true)
        try await workspace.move(path: original.path, to: "archive/inbox.org", expected: [original])
        try await workspace.write(path: "archive/inbox.org", contents: "* Offline draft\n", expectedContents: original.contents)
        let moved = try await document("archive/inbox.org", in: workspace)
        let deleted = try await workspace.trash(document: moved, expected: [moved])
        try await workspace.restore(deleted)
        let reopened = try session(backend)
        let local = try await reopened.snapshot()
        XCTAssertEqual(local.documents.first { $0.kind == .org }?.contents, "* Offline draft\n")
        XCTAssertEqual(local.documents.first { $0.kind == .org }?.id, original.id)
        let queued = await reopened.state.operations.count
        XCTAssertEqual(queued, 3)
        await backend.setOffline(false)
        try await reopened.synchronize()
        let completed = try await reopened.snapshot()
        let oldRemote = await backend.contents("inbox.org")
        let remote = await backend.contents("archive/inbox.org")
        XCTAssertNil(oldRemote)
        XCTAssertEqual(remote, "* Offline draft\n")
        XCTAssertFalse(completed.hasPendingOperation)
        XCTAssertTrue(completed.pendingPaths.isEmpty)
        XCTAssertEqual(completed.documents.first { $0.kind == .org }?.id, original.id)
    }

    func testListingTrashRetainsQueuedOfflineDeletionAcrossRestart() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        let original = try await document("inbox.org", in: workspace)
        await backend.setOffline(true)
        let deleted = try await workspace.trash(document: original, expected: [original])
        let listed = try await workspace.deletedEntries()
        XCTAssertEqual(listed, [deleted])

        let reopened = try session(backend)
        let durable = try await reopened.deletedEntries()
        XCTAssertEqual(durable, [deleted])
        try await reopened.restore(deleted)
        await backend.setOffline(false)
        try await reopened.synchronize()
        let remote = await backend.contents("inbox.org")
        let restored = try await document("inbox.org", in: reopened)
        XCTAssertEqual(remote, original.contents)
        XCTAssertEqual(restored.id, original.id)
    }

    func testListingTrashDoesNotResurrectQueuedRestore() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        let original = try await document("inbox.org", in: workspace)
        let deleted = try await workspace.trash(document: original, expected: [original])
        try await workspace.synchronize()
        try await workspace.restore(deleted)

        let listed = try await workspace.deletedEntries()
        XCTAssertTrue(listed.isEmpty)
        let reopened = try session(backend)
        let durable = try await reopened.deletedEntries()
        XCTAssertTrue(durable.isEmpty)
        try await reopened.synchronize()
        let remote = await backend.contents("inbox.org")
        XCTAssertEqual(remote, original.contents)
        let completed = try await reopened.deletedEntries()
        XCTAssertTrue(completed.isEmpty)
    }

    func testFolderTrashListingPreservesQueuedDeletionAndRestore() async throws {
        let root = cache.appendingPathComponent("Folder", isDirectory: true)
        let unavailable = cache.appendingPathComponent("UnavailableFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("* Base\n".utf8).write(to: root.appendingPathComponent("inbox.org"))
        let localConnection = StorageConnection(provider: .local, displayName: "Folder", rootID: root.path)
        let workspace = try LocalStore(connection: localConnection, cacheDirectory: cache,
            folder: WorkspaceFileStore(rootURL: root))
        try await workspace.synchronize()
        let original = try await document("inbox.org", in: workspace)
        try FileManager.default.moveItem(at: root, to: unavailable)
        let deleted = try await workspace.trash(document: original, expected: [original])
        try FileManager.default.moveItem(at: unavailable, to: root)
        let listed = try await workspace.deletedEntries()
        XCTAssertEqual(listed, [deleted])
        await workspace.close()

        let reopened = try LocalStore(connection: localConnection, cacheDirectory: cache,
            folder: WorkspaceFileStore(rootURL: root))
        let durable = try await reopened.deletedEntries()
        XCTAssertEqual(durable, [deleted])
        try await reopened.synchronize()
        try FileManager.default.moveItem(at: root, to: unavailable)
        try await reopened.restore(deleted)
        try FileManager.default.moveItem(at: unavailable, to: root)
        let restoring = try await reopened.deletedEntries()
        XCTAssertTrue(restoring.isEmpty)
        await reopened.close()

        let restoringSession = try LocalStore(connection: localConnection, cacheDirectory: cache,
            folder: WorkspaceFileStore(rootURL: root))
        let queued = try await restoringSession.deletedEntries()
        XCTAssertTrue(queued.isEmpty)
        try await restoringSession.synchronize()
        let restored = try await document("inbox.org", in: restoringSession)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("inbox.org"), encoding: .utf8), original.contents)
        await restoringSession.close()
    }

    func testPushConflictKeepsBothVersions() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Local\n", expectedContents: "* Base\n")
        await backend.replace("inbox.org", contents: "* External\n")
        do { try await workspace.synchronize(mode: .push); XCTFail("The stale conditional write succeeded") }
        catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let conflict = try await workspace.snapshot()
        XCTAssertEqual(conflict.conflicts.first?.remoteContents, "* External\n")
        XCTAssertEqual(conflict.documents.first?.contents, "* Local\n")
        let remote = await backend.contents("inbox.org")
        XCTAssertEqual(remote, "* External\n")
    }

    func testOneFailedPathDoesNotBlockAnotherPendingUpload() async throws {
        let backend = SessionFakeBackend(["a.org": "* A\n", "b.org": "* B\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "a.org", contents: "* Local A\n", expectedContents: "* A\n")
        try await workspace.write(path: "b.org", contents: "* Local B\n", expectedContents: "* B\n")
        await backend.failUpload("a.org", error: .http(500))
        do { try await workspace.synchronize(mode: .push); XCTFail("The failed path was hidden") }
        catch { XCTAssertEqual(error as? StorageError, .http(500)) }
        let snapshot = try await workspace.snapshot()
        let remote = await backend.contents("b.org")
        XCTAssertEqual(snapshot.pendingPaths, ["a.org"])
        XCTAssertNotNil(snapshot.uploadErrors["a.org"])
        XCTAssertEqual(remote, "* Local B\n")
    }

    func testExternalRenamePreservesStableIdentityAndRebasesDraftAtNewPath() async throws {
        let backend = SessionFakeBackend(["old.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        let original = try await document("old.org", in: workspace)
        let metadata = await workspace.state.entries["old.org"]?.file
        let remoteFile = try XCTUnwrap(metadata)
        try await workspace.write(path: "old.org", contents: "* Draft\n", expectedContents: original.contents)
        _ = try await backend.move(remoteFile, to: "new.org")
        try await workspace.synchronize()
        let renamed = try await document("new.org", in: workspace)
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.contents, "* Draft\n")
        let old = await backend.contents("old.org")
        let new = await backend.contents("new.org")
        XCTAssertNil(old)
        XCTAssertEqual(new, "* Draft\n")
    }

    func testFailedStateTransactionRetainsPreviousDurableDraft() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Saved draft\n", expectedContents: "* Base\n")
        let before = try await workspace.snapshot()
        let url = cache.appendingPathComponent(connection.id.uuidString).appendingPathComponent("state.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TRIGGER reject_commit BEFORE INSERT ON meta BEGIN SELECT RAISE(ABORT, 'test write failure'); END", nil, nil, nil), SQLITE_OK)
        do {
            try await workspace.write(path: "inbox.org", contents: "* Failed draft\n", expectedContents: "* Saved draft\n")
            XCTFail("The injected transaction failure must reject the new draft")
        } catch {}
        let after = try await workspace.snapshot()
        XCTAssertEqual(after.revision, before.revision)
        XCTAssertEqual(after.documents, before.documents)
        XCTAssertEqual(after.pendingPaths, ["inbox.org"])

        XCTAssertEqual(sqlite3_exec(database, "DROP TRIGGER reject_commit", nil, nil, nil), SQLITE_OK)
        let reopened = try session(backend)
        let durable = try await reopened.snapshot()
        XCTAssertEqual(durable.documents, before.documents)
        try await reopened.synchronize()
        let remote = await backend.contents("inbox.org")
        XCTAssertEqual(remote, "* Saved draft\n")
    }

    func testReopeningRejectsCorruptBlobWithoutDiscardingPendingDraft() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Local draft\n", expectedContents: "* Base\n")
        let blob = LocalStore.digest(Data("* Local draft\n".utf8))
        let url = cache.appendingPathComponent(connection.id.uuidString).appendingPathComponent("blobs/" + blob)
        try Data("corrupt".utf8).write(to: url, options: .atomic)
        let reopened = try session(backend)
        do {
            _ = try await reopened.snapshot()
            XCTFail("A corrupted blob must not be accepted as a durable draft")
        } catch { XCTAssertEqual(error as? StorageError, .invalidResponse) }
        let pending = await reopened.state.pending["inbox.org"]
        XCTAssertEqual(pending?.blob, blob)
        let remote = await backend.contents("inbox.org")
        XCTAssertEqual(remote, "* Base\n")
    }

    func testSavingDraftRepairsExistingCorruptBlobBeforeAcknowledgingCommit() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.synchronize()
        let draft = "* Local draft\n"
        let blob = LocalStore.digest(Data(draft.utf8))
        let url = cache.appendingPathComponent(connection.id.uuidString).appendingPathComponent("blobs/" + blob)
        try Data("corrupt".utf8).write(to: url, options: .atomic)

        try await workspace.write(path: "inbox.org", contents: draft, expectedContents: "* Base\n")
        let reopened = try session(backend)
        let saved = try await document("inbox.org", in: reopened)
        XCTAssertEqual(saved.contents, draft)
        try await reopened.synchronize()
        let remote = await backend.contents("inbox.org")
        XCTAssertEqual(remote, draft)
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
        try await workspace.move(path: "inbox.org", to: "archive/inbox.org", expected: expected)
        _ = try? await workspace.synchronize()
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
        _ = try? await workspace.refile(source: source, destination: target,
            expectedSource: "* Move me\n* Remaining\n", expectedDestination: "* Older\n")
        _ = try? await workspace.synchronize()
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
        _ = try? await workspace.refile(source: source, destination: target,
            expectedSource: "* Move me\n", expectedDestination: nil)
        _ = try? await workspace.synchronize()
        await backend.replace("archive.org", contents: "* External replacement\n")
        let reopened = try session(backend)
        do { try await reopened.synchronize(); XCTFail("Source removed after destination changed") }
        catch {}
        let original = await backend.contents("inbox.org")
        XCTAssertEqual(original, "* Move me\n")
        await backend.failUpload(nil)
        let conflict = try await reopened.snapshot()
        XCTAssertEqual(conflict.conflicts.first?.path, "inbox.org")
        try await reopened.resolveConflict(path: "inbox.org", resolution: .useRemote)
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
    var uploadFailure: StorageError = .offline
    var offline = false
    var ambiguousPath: String?
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
        if offline { throw StorageError.offline }
        var files = items.values.map(\.file)
        if let ambiguousPath { files.append(RemoteFile(id: ambiguousPath, path: ambiguousPath, isDirectory: false, revision: "ambiguous")) }
        return RemoteScan(files: files)
    }
    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        if offline { throw StorageError.offline }
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
        if offline { throw StorageError.offline }
        if path == failingUpload { throw uploadFailure }
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
        if offline { throw StorageError.offline }
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
    func failUpload(_ path: String?, error: StorageError = .offline) { failingUpload = path; uploadFailure = error }
    func setOffline(_ value: Bool) { offline = value }
    func addAmbiguousPath(_ path: String) { ambiguousPath = path }
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
