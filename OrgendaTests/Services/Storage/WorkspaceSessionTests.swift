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

    func testUninitializedCacheDoesNotAppearReady() async throws {
        let backend = SessionFakeBackend()
        let workspace = try session(backend)
        do { _ = try await workspace.snapshot(); XCTFail("An uninitialized cache is not an empty workspace") }
        catch { XCTAssertEqual(error as? StorageError, .rootUnavailable) }
    }

    func testOfflineDraftSurvivesRestartAndUploadsAfterReconnect() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Original\n"])
        let first = try session(backend)
        try await first.initialize()
        await backend.setOffline(true)
        try await first.write(path: "inbox.org", contents: "* Offline edit\n", expectedContents: "* Original\n")
        do { try await first.synchronize(); XCTFail("Offline sync must fail") }
        catch { XCTAssertEqual(error as? StorageError, .offline) }
        let reopened = try session(backend)
        let saved = try await reopened.snapshot()
        XCTAssertEqual(saved.documents.first?.contents, "* Offline edit\n")
        XCTAssertEqual(saved.pendingPaths, ["inbox.org"])
        await backend.setOffline(false)
        try await reopened.synchronize()
        let remoteText = await backend.contents("inbox.org")
        let final = try await reopened.snapshot()
        XCTAssertEqual(remoteText, "* Offline edit\n")
        XCTAssertTrue(final.pendingPaths.isEmpty)
    }

    func testExternalChangePreservesBothVersionsAndResolvesUsingLatestRemote() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
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

    func testKeepBothRetainsCloudFileAndUploadsSeparateDraft() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        try await workspace.write(path: "inbox.org", contents: "* Draft\n", expectedContents: "* Base\n")
        await backend.replace("inbox.org", contents: "* Cloud\n")
        _ = try? await workspace.synchronize()
        try await workspace.resolveConflict(path: "inbox.org", resolution: .keepBoth)
        let snapshot = try await workspace.snapshot()
        XCTAssertEqual(snapshot.documents.count, 2)
        XCTAssertTrue(snapshot.documents.contains { $0.path == "inbox.org" && $0.contents == "* Cloud\n" })
        XCTAssertTrue(snapshot.documents.contains { $0.path != "inbox.org" && $0.contents == "* Draft\n" })
        XCTAssertTrue(snapshot.pendingPaths.isEmpty)
    }

    func testDeletionAndReplacedIdentityDoNotResurrectOrOverwrite() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        try await workspace.write(path: "inbox.org", contents: "* Draft\n", expectedContents: "* Base\n")
        await backend.remove("inbox.org")
        _ = try? await workspace.synchronize()
        let deleted = try await workspace.snapshot()
        XCTAssertNil(deleted.conflicts.first?.remoteContents)
        let absent = await backend.contents("inbox.org")
        XCTAssertNil(absent)
        await backend.replace("inbox.org", contents: "* Base\n", newIdentity: true)
        _ = try? await workspace.synchronize()
        let replaced = try await workspace.snapshot()
        XCTAssertEqual(replaced.conflicts.count, 1)
        let untouched = await backend.contents("inbox.org")
        XCTAssertEqual(untouched, "* Base\n")
    }

    func testFailedCompleteDownloadDoesNotRemovePreviouslyLoadedDocuments() async throws {
        let backend = SessionFakeBackend(["a.org": "* A\n", "b.org": "* B\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
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
        try await workspace.initialize()
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
        try await workspace.initialize()
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

    func testFolderMoveTrashAndRestorePreserveUnindexedAndHiddenAttachments() async throws {
        let backend = SessionFakeBackend(["project/inbox.org": "* Task\n"])
        await backend.addDirectory("project")
        await backend.addDirectory("archive")
        await backend.addBinary("project/.attach/photo.png", data: Data([1, 2, 255]))
        let workspace = try session(backend)
        try await workspace.initialize()
        let original = try await workspace.load().filter { $0.path.hasPrefix("project") }
        try await workspace.move(path: "project", to: "archive/project", expected: original)
        let moved = try await workspace.load().filter { $0.path.hasPrefix("archive/project") }
        let document = try XCTUnwrap(moved.first { $0.path == "archive/project" })
        let entry = try await workspace.trash(document: document, expected: moved)
        let payload = await backend.binary(entry.storagePath + "/.attach/photo.png")
        XCTAssertEqual(payload, Data([1, 2, 255]))
        let reopened = try session(backend)
        try await reopened.initialize()
        let deleted = try await reopened.deletedEntries()
        XCTAssertEqual(deleted, [entry])
        try await reopened.restore(entry)
        let restored = await backend.binary("archive/project/.attach/photo.png")
        XCTAssertEqual(restored, Data([1, 2, 255]))
        let final = try await reopened.load()
        XCTAssertTrue(final.contains { $0.path == "archive/project/inbox.org" })
        XCTAssertFalse(final.contains { $0.path.contains(".attach") })
    }

    func testInterruptedMoveIsRecoveredOnRestart() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Task\n"])
        await backend.addDirectory("archive")
        let workspace = try session(backend)
        try await workspace.initialize()
        let expected = try await workspace.load().filter { $0.path == "inbox.org" }
        await backend.loseNextMoveResponse()
        do { try await workspace.move(path: "inbox.org", to: "archive/inbox.org", expected: expected); XCTFail("Response is lost") }
        catch { XCTAssertEqual(error as? StorageError, .offline) }
        let reopened = try session(backend)
        try await reopened.synchronize()
        let final = try await reopened.snapshot()
        XCTAssertTrue(final.documents.contains { $0.path == "archive/inbox.org" })
        XCTAssertFalse(final.documents.contains { $0.path == "inbox.org" })
        let moves = await backend.moveCount
        XCTAssertEqual(moves, 1)
    }

    func testCachedAttachmentsWorkOfflineAndRejectEscapingPaths() async throws {
        let backend = SessionFakeBackend()
        await backend.addBinary(".attach/image.png", data: Data([1, 2, 3]))
        let workspace = try session(backend)
        try await workspace.initialize()
        let bytes = try await workspace.readImageData(path: ".attach/image.png", maxBytes: 3)
        XCTAssertEqual(bytes, Data([1, 2, 3]))
        await backend.setOffline(true)
        let reopened = try session(backend)
        let cached = try await reopened.readImageData(path: ".attach/image.png", maxBytes: 3)
        XCTAssertEqual(cached, bytes)
        for path in ["../private.png", "/private.png", "notes/../../private.png"] {
            do { _ = try await reopened.readImageData(path: path, maxBytes: 3); XCTFail("Escaping path accepted") }
            catch { XCTAssertEqual(error as? StorageError, .unsafePath(path)) }
        }
    }

    func testPathCollisionsDoNotReplaceSnapshot() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Original\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        await backend.replace("INBOX.org", contents: "* Ambiguous\n", newIdentity: true)
        _ = try? await workspace.synchronize()
        let snapshot = try await workspace.snapshot()
        XCTAssertEqual(snapshot.documents.map(\.path), ["inbox.org"])
        XCTAssertEqual(snapshot.conflicts.count, 1)
    }

    func testFolderSessionKeepsOfflineDraftWithoutChangingExternalVersion() async throws {
        let root = cache.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("inbox.org")
        try Data("* Base\n".utf8).write(to: url)
        let descriptor = StorageConnection(provider: .iCloud, displayName: "Folder", rootID: root.path)
        let workspace = try WorkspaceSession(connection: descriptor, cacheDirectory: cache,
                                             folder: WorkspaceFileStore(rootURL: root))
        try await workspace.initialize()
        try await workspace.write(path: "inbox.org", contents: "* Draft\n", expectedContents: "* Base\n")
        try Data("* External\n".utf8).write(to: url)
        _ = try? await workspace.synchronize()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* External\n")
        let reopened = try WorkspaceSession(connection: descriptor, cacheDirectory: cache,
                                            folder: WorkspaceFileStore(rootURL: root))
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.documents.first?.contents, "* Draft\n")
        XCTAssertEqual(snapshot.conflicts.first?.remoteContents, "* External\n")
    }

    func testCacheIsIsolatedByConnectionIdentity() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Private\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        let other = StorageConnection(provider: .webDAV, displayName: "Other", rootID: "/other")
        let isolated = try WorkspaceSession(connection: other, cacheDirectory: cache, remote: SessionFakeBackend())
        do { _ = try await isolated.snapshot(); XCTFail("A new connection must not expose another cache") }
        catch {}
    }

    func testUseLocalRefusesAnUnseenNewRemoteRevision() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
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

    func testReauthenticationPreservesTheSamePendingDraft() async throws {
        let expired = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(expired)
        try await workspace.initialize()
        await expired.setOffline(true)
        try await workspace.write(path: "inbox.org", contents: "* Pending\n", expectedContents: "* Base\n")
        let authenticated = await expired.authenticatedCopy()
        try await workspace.replaceRemoteBackend(authenticated)
        try await workspace.synchronize()
        let snapshot = try await workspace.snapshot()
        let uploaded = await authenticated.contents("inbox.org")
        XCTAssertEqual(uploaded, "* Pending\n")
        XCTAssertTrue(snapshot.pendingPaths.isEmpty)
    }

    func testLostTrashResponseWithPathIDsRecoversAndRestoresText() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Task\n"])
        await backend.usePathIdentifiers()
        let workspace = try session(backend)
        try await workspace.initialize()
        let docs = try await workspace.load()
        await backend.loseNextMoveResponse()
        do { _ = try await workspace.trash(document: try XCTUnwrap(docs.first), expected: docs); XCTFail("Response lost") }
        catch { XCTAssertEqual(error as? StorageError, .offline) }
        let reopened = try session(backend)
        try await reopened.synchronize()
        let entries = try await reopened.deletedEntries()
        let entry = try XCTUnwrap(entries.first)
        try await reopened.restore(entry)
        let restored = try await reopened.snapshot()
        XCTAssertEqual(restored.documents.first?.contents, "* Task\n")
        let moves = await backend.moveCount
        XCTAssertEqual(moves, 2)
    }

    func testDraftAfterAmbiguousMoveFollowsMovedFileInsteadOfRecreatingSource() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Task\n"])
        await backend.addDirectory("archive")
        let workspace = try session(backend)
        try await workspace.initialize()
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
        try await workspace.initialize()
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
        try await workspace.initialize()
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

    func testDeltaFolderRenameAndDeletionCarryAllDescendants() async throws {
        let backend = SessionFakeBackend(["project/task.org": "* Task\n"])
        let oldFolder = await backend.addDirectory("project")
        let workspace = try session(backend)
        try await workspace.initialize()
        let moved = try await backend.move(oldFolder, to: "renamed")
        await backend.returnNextScan(RemoteScan(files: [moved], cursor: "rename", isFullSnapshot: false))
        try await workspace.synchronize()
        let renamed = try await workspace.snapshot()
        XCTAssertEqual(renamed.documents.map(\.path), ["renamed", "renamed/task.org"])
        await backend.returnNextScan(RemoteScan(files: [], deletedIDs: [moved.id], cursor: "delete", isFullSnapshot: false))
        try await workspace.synchronize()
        let deleted = try await workspace.snapshot()
        XCTAssertTrue(deleted.documents.isEmpty)
    }

    func testIncompleteAncestorInventoryCannotReplaceKnownSnapshot() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Original\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        let orphan = RemoteFile(id: "orphan", path: "missing/child.org", isDirectory: false, revision: "1")
        await backend.returnNextScan(RemoteScan(files: [orphan]))
        do { try await workspace.synchronize(); XCTFail("A missing ancestor is an incomplete snapshot") }
        catch { XCTAssertEqual(error as? StorageError, .invalidResponse) }
        let retained = try await workspace.snapshot()
        XCTAssertEqual(retained.documents.first?.contents, "* Original\n")
    }

    func testRetiredArchivedDraftIsNotUploadedWhenFolderIsConnectedAgain() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        try await workspace.write(path: "inbox.org", contents: "* Retained draft\n", expectedContents: "* Base\n")
        let recovery = cache.appendingPathComponent("Exported")
        try await workspace.archiveUnsynced(to: recovery)
        try await workspace.retireAfterArchiving()
        let reopened = try session(backend)
        try await reopened.synchronize()
        let cloud = await backend.contents("inbox.org")
        XCTAssertEqual(cloud, "* Base\n")
        let copies = try FileManager.default.subpathsOfDirectory(atPath: recovery.path).filter { $0.hasSuffix("/inbox.org") }
        let file = try XCTUnwrap(copies.first)
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent(file), encoding: .utf8), "* Retained draft\n")
    }

    func testSuccessfulSyncCollectsOldBlobsButKeepsRecoveryCopyAndCurrentText() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* Base\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        try await workspace.write(path: "inbox.org", contents: "* Recovery draft\n", expectedContents: "* Base\n")
        let recovery = cache.appendingPathComponent("Exported")
        try await workspace.archiveUnsynced(to: recovery)
        try await workspace.write(path: "inbox.org", contents: "* Current\n", expectedContents: "* Recovery draft\n")
        let reopened = try session(backend)
        try await reopened.synchronize()
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.documents.first?.contents, "* Current\n")
        let blobs = cache.appendingPathComponent(connection.id.uuidString).appendingPathComponent("blobs")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: blobs.path).count, 1)
        let copies = try FileManager.default.subpathsOfDirectory(atPath: recovery.path).filter { $0.hasSuffix("/inbox.org") }
        let file = try XCTUnwrap(copies.first)
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent(file), encoding: .utf8), "* Recovery draft\n")
        let again = try session(backend)
        let durable = try await again.snapshot()
        XCTAssertEqual(durable.documents.first?.contents, "* Current\n")
    }

    func testDraftFromUIBeforeRefreshIsCommittedAsConflictAgainstUnseenVersion() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* A\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
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

    func testStaleUISaveAfterDeletionRequiresExplicitResolutionAcrossRestart() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* A\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        await backend.remove("inbox.org")
        try await workspace.synchronize()
        try await workspace.write(path: "inbox.org", contents: "* Retained draft\n", expectedContents: "* A\n")
        let reopened = try session(backend)
        _ = try? await reopened.synchronize()
        let snapshot = try await reopened.snapshot()
        let cloud = await backend.contents("inbox.org")
        XCTAssertNil(cloud)
        XCTAssertEqual(snapshot.conflicts.count, 1)
        XCTAssertNil(snapshot.conflicts.first?.remoteContents)
        try await reopened.resolveConflict(path: "inbox.org", resolution: .useLocal)
        let explicitRestoration = await backend.contents("inbox.org")
        XCTAssertEqual(explicitRestoration, "* Retained draft\n")
    }

    func testSnapshotRevisionIncreasesAcrossCommitsAndRestart() async throws {
        let backend = SessionFakeBackend(["inbox.org": "* A\n"])
        let workspace = try session(backend)
        try await workspace.initialize()
        let original = try await workspace.snapshot()
        try await workspace.write(path: "inbox.org", contents: "* B\n", expectedContents: "* A\n")
        let committed = try await workspace.snapshot()
        XCTAssertGreaterThan(committed.revision, original.revision)
        let reopened = try session(backend)
        let restored = try await reopened.snapshot()
        XCTAssertEqual(restored.revision, committed.revision)
        try await reopened.synchronize()
        let synchronized = try await reopened.snapshot()
        XCTAssertGreaterThan(synchronized.revision, restored.revision)
        XCTAssertEqual(synchronized.documents.first?.contents, "* B\n")
    }
}

private actor SessionFakeBackend: RemoteWorkspaceBackend {
    struct Item { var file: RemoteFile; var data: Data }
    var items: [String: Item] = [:]
    var offline = false
    var failingDownload: String?
    var failingUpload: String?
    var pathIDs = false
    var paused = false
    var uploadStarted = false
    var uploadWaiters: [CheckedContinuation<Void, Never>] = []
    var resume: CheckedContinuation<Void, Never>?
    var loseUploadResponse = false
    var loseMoveResponse = false
    var uploadCount = 0
    var moveCount = 0
    var nextScan: RemoteScan?
    var pausedDownloadPath: String?
    var downloadStarted = false
    var downloadWaiters: [CheckedContinuation<Void, Never>] = []
    var downloadResume: CheckedContinuation<Void, Never>?

    init(_ texts: [String: String] = [:]) {
        for (path, text) in texts {
            items[path] = Item(file: RemoteFile(id: UUID().uuidString, path: path, isDirectory: false,
                revision: UUID().uuidString, size: Int64(text.utf8.count)), data: Data(text.utf8))
        }
    }
    init(items: [String: Item]) { self.items = items }

    func scan(cursor: String?) throws -> RemoteScan {
        try checkOnline()
        if let scan = nextScan { nextScan = nil; return scan }
        return RemoteScan(files: items.values.map(\.file))
    }
    func download(_ file: RemoteFile, maxBytes: Int) async throws -> RemoteDownload {
        try checkOnline()
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
    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) async throws -> RemoteFile {
        try checkOnline()
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
        let file = RemoteFile(id: existing?.id ?? UUID().uuidString, path: path, isDirectory: false,
                              revision: UUID().uuidString, size: Int64(data.count))
        items[path] = Item(file: file, data: data)
        uploadCount += 1
        if loseUploadResponse { loseUploadResponse = false; throw StorageError.offline }
        return file
    }
    func createDirectory(path: String) throws -> RemoteFile {
        try checkOnline()
        if let existing = items[path] {
            guard existing.file.isDirectory else { throw StorageError.conflict(path) }
            return existing.file
        }
        return addDirectory(path)
    }
    func move(_ file: RemoteFile, to path: String) throws -> RemoteFile {
        try checkOnline()
        guard let old = items[file.path], old.file.id == file.id, old.file.revision == file.revision,
              items[path] == nil else { throw StorageError.conflict(file.path) }
        for (oldPath, var item) in items.filter({ WorkspaceFileTransfer.contains($0.key, in: file.path) }) {
            items.removeValue(forKey: oldPath)
            let newPath = path + oldPath.dropFirst(file.path.count)
            if item.file.id == oldPath { item.file.id = newPath }
            item.file.path = newPath
            items[newPath] = item
        }
        moveCount += 1
        if loseMoveResponse { loseMoveResponse = false; throw StorageError.offline }
        return items[path]!.file
    }
    @discardableResult
    func addDirectory(_ path: String) -> RemoteFile {
        let file = RemoteFile(id: pathIDs ? path : UUID().uuidString, path: path, isDirectory: true, revision: UUID().uuidString)
        items[path] = Item(file: file, data: Data())
        return file
    }
    func addBinary(_ path: String, data: Data) {
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty {
            if items[parent] == nil { addDirectory(parent) }
            parent = (parent as NSString).deletingLastPathComponent
        }
        items[path] = Item(file: RemoteFile(id: UUID().uuidString, path: path, isDirectory: false,
            revision: UUID().uuidString, size: Int64(data.count)), data: data)
    }
    func replace(_ path: String, contents: String, newIdentity: Bool = false) {
        let id = newIdentity ? UUID().uuidString : items[path]?.file.id ?? UUID().uuidString
        items[path] = Item(file: RemoteFile(id: id, path: path, isDirectory: false,
            revision: UUID().uuidString, size: Int64(contents.utf8.count)), data: Data(contents.utf8))
    }
    func remove(_ path: String) { items.removeValue(forKey: path) }
    func contents(_ path: String) -> String? { items[path].flatMap { String(data: $0.data, encoding: .utf8) } }
    func binary(_ path: String) -> Data? { items[path]?.data }
    func setOffline(_ value: Bool) { offline = value }
    func failDownload(_ path: String) { failingDownload = path }
    func failUpload(_ path: String?) { failingUpload = path }
    func returnNextScan(_ scan: RemoteScan) { nextScan = scan }
    func pauseNextDownload(_ path: String) { pausedDownloadPath = path; downloadStarted = false }
    func waitForDownload() async {
        if downloadStarted { return }
        await withCheckedContinuation { downloadWaiters.append($0) }
    }
    func resumeDownload() { downloadResume?.resume(); downloadResume = nil }
    func authenticatedCopy() -> SessionFakeBackend { SessionFakeBackend(items: items) }
    func usePathIdentifiers() {
        pathIDs = true
        for path in items.keys { items[path]?.file.id = path }
    }
    func pauseNextUpload() { paused = true; uploadStarted = false }
    func waitForUpload() async {
        if uploadStarted { return }
        await withCheckedContinuation { uploadWaiters.append($0) }
    }
    func resumeUpload() { resume?.resume(); resume = nil }
    func loseNextUploadResponse() { loseUploadResponse = true }
    func loseNextMoveResponse() { loseMoveResponse = true }
    func checkOnline() throws { if offline { throw StorageError.offline } }
}
