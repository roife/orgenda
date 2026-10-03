import Foundation
import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStorageConcurrencyTests: XCTestCase {
    func testMoveKeepsUIEditArrivingDuringRemoteAwaitAtDestination() async throws {
        let started = expectation(description: "Remote MOVE is waiting")
        let fixture = try await makeFixture(moveStarted: started)
        let store = fixture.store
        let original = try XCTUnwrap(store.documents.first { $0.path == "inbox.org" })
        let transfer = store.fileTransfer(original)
        let moving = Task { await store.moveFile(transfer, to: "archive") }
        await fulfillment(of: [started], timeout: 5)

        store.updateDocument(path: "inbox.org", contents: "* Edited while moving\n")
        store.fileSaveTask?.cancel()
        XCTAssertEqual(store.dirtyFilePaths, ["inbox.org"])
        await fixture.backend.releaseMove()
        let succeeded = await moving.value
        XCTAssertTrue(succeeded, store.fileActionError ?? "Move failed")

        XCTAssertFalse(store.documents.contains { $0.path == "inbox.org" })
        XCTAssertEqual(store.documents.first { $0.path == "archive/inbox.org" }?.contents,
                       "* Edited while moving\n")
        XCTAssertTrue(store.dirtyFilePaths.isEmpty)
        XCTAssertEqual(store.pendingUploadPaths, ["archive/inbox.org"])
        let reopened = try WorkspaceSession(connection: fixture.connection, cacheDirectory: fixture.cache,
            remote: fixture.backend, recoveryDirectory: fixture.cache.appendingPathComponent("Recovery"))
        let durable = try await reopened.snapshot()
        XCTAssertEqual(durable.documents.first { $0.path == "archive/inbox.org" }?.contents,
                       "* Edited while moving\n")

        await store.synchronizeFiles()
        let oldRemote = await fixture.backend.contents("inbox.org")
        let movedRemote = await fixture.backend.contents("archive/inbox.org")
        XCTAssertNil(oldRemote, "A delayed UI save must never recreate the old source path")
        XCTAssertEqual(movedRemote, "* Edited while moving\n")
        XCTAssertTrue(store.pendingUploadPaths.isEmpty)
        XCTAssertTrue(store.syncConflicts.isEmpty)
        store.fileSaveTask?.cancel()
    }

    func testDeleteKeepsUIEditArrivingDuringRemoteAwaitAsDurableDeletionConflict() async throws {
        let started = expectation(description: "Remote trash MOVE is waiting")
        let fixture = try await makeFixture(moveStarted: started)
        let store = fixture.store
        let original = try XCTUnwrap(store.documents.first { $0.path == "inbox.org" })
        let transfer = store.fileTransfer(original)
        let deleting = Task { await store.deleteFile(transfer) }
        await fulfillment(of: [started], timeout: 5)

        store.updateDocument(path: "inbox.org", contents: "* Edited while deleting\n")
        store.fileSaveTask?.cancel()
        XCTAssertEqual(store.dirtyFilePaths, ["inbox.org"])
        await fixture.backend.releaseMove()
        let succeeded = await deleting.value
        XCTAssertTrue(succeeded, store.fileActionError ?? "Delete failed")

        XCTAssertEqual(store.documents.first { $0.path == "inbox.org" }?.contents,
                       "* Edited while deleting\n")
        XCTAssertTrue(store.dirtyFilePaths.isEmpty)
        XCTAssertEqual(store.pendingUploadPaths, ["inbox.org"])
        XCTAssertEqual(store.syncConflicts.first?.localContents, "* Edited while deleting\n")
        XCTAssertNil(store.syncConflicts.first?.remoteContents)
        let entry = try XCTUnwrap(store.recentlyDeleted.first)
        let remoteSource = await fixture.backend.contents("inbox.org")
        let trashed = await fixture.backend.contents(entry.storagePath)
        XCTAssertNil(remoteSource)
        XCTAssertEqual(trashed, "* Original\n")

        let reopened = try WorkspaceSession(connection: fixture.connection, cacheDirectory: fixture.cache,
            remote: fixture.backend, recoveryDirectory: fixture.cache.appendingPathComponent("Recovery"))
        do { try await reopened.synchronize(); XCTFail("A deleted file was silently recreated") }
        catch { XCTAssertEqual(error as? StorageError, .conflict("inbox.org")) }
        let durable = try await reopened.snapshot()
        XCTAssertEqual(durable.conflicts.first?.localContents, "* Edited while deleting\n")
        let stillDeleted = await fixture.backend.contents("inbox.org")
        XCTAssertNil(stillDeleted)
        store.fileSaveTask?.cancel()
    }

    private struct Fixture {
        let store: WorkspaceStore
        let backend: AwaitingFileActionBackend
        let cache: URL
        let connection: StorageConnection
    }

    private func makeFixture(moveStarted: XCTestExpectation) async throws -> Fixture {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("StorageConcurrency-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: cache) }
        let connection = StorageConnection(provider: .webDAV, displayName: "Concurrency Test", rootID: "/org")
        let backend = AwaitingFileActionBackend { moveStarted.fulfill() }
        let session = try WorkspaceSession(connection: connection, cacheDirectory: cache, remote: backend,
                                            recoveryDirectory: cache.appendingPathComponent("Recovery"))
        try await session.synchronize()
        let store = WorkspaceStore()
        store.storageCacheDirectory = cache
        store.storageConnection = connection
        store.workspaceSession = session
        store.fileStore = session
        store.isFolderConnected = true
        store.isStartingWorkspace = false
        store.usesEmacsConfiguration = true
        store.applyStorageSnapshot(try await session.snapshot())
        await store.waitForWorkspaceIndex()
        return Fixture(store: store, backend: backend, cache: cache, connection: connection)
    }
}

/// The barrier pauses the actual remote mutation, after the Store and Session
/// have validated their initial snapshots. Tests can then add an uncommitted UI
/// edit without relying on arbitrary sleeps or an autosave timing coincidence.
private actor AwaitingFileActionBackend: RemoteWorkspaceBackend {
    struct Item { var file: RemoteFile; var data: Data }
    var items: [String: Item]
    let started: @Sendable () -> Void
    var moveContinuation: CheckedContinuation<Void, Never>?
    var moveReleased = false

    init(started: @escaping @Sendable () -> Void) {
        self.started = started
        items = [
            "inbox.org": Item(file: RemoteFile(id: "inbox-id", path: "inbox.org", isDirectory: false,
                revision: "initial", size: 11), data: Data("* Original\n".utf8)),
            "archive": Item(file: RemoteFile(id: "archive-id", path: "archive", isDirectory: true,
                revision: "initial"), data: Data())
        ]
    }

    func scan(cursor: String?) -> RemoteScan { RemoteScan(files: items.values.map(\.file)) }

    func download(_ file: RemoteFile, maxBytes: Int) throws -> RemoteDownload {
        guard let current = items[file.path] else { throw StorageError.http(404) }
        guard current.data.count <= maxBytes else { throw StorageError.tooLarge }
        return RemoteDownload(file: current.file, data: current.data)
    }

    func upload(path: String, data: Data, existing: RemoteFile?, operationID: UUID) throws -> RemoteFile {
        let current = items[path]
        guard current?.file.id == existing?.id, current?.file.revision == existing?.revision else {
            throw StorageError.conflict(path)
        }
        let file = RemoteFile(id: existing?.id ?? UUID().uuidString, path: path, isDirectory: false,
                              revision: UUID().uuidString, size: Int64(data.count))
        items[path] = Item(file: file, data: data)
        return file
    }

    func createDirectory(path: String) throws -> RemoteFile {
        if let existing = items[path] {
            guard existing.file.isDirectory else { throw StorageError.conflict(path) }
            return existing.file
        }
        let file = RemoteFile(id: UUID().uuidString, path: path, isDirectory: true, revision: UUID().uuidString)
        items[path] = Item(file: file, data: Data())
        return file
    }

    func move(_ file: RemoteFile, to path: String) async throws -> RemoteFile {
        started()
        if !moveReleased { await withCheckedContinuation { moveContinuation = $0 } }
        guard let original = items[file.path], original.file.id == file.id,
              original.file.revision == file.revision, items[path] == nil else { throw StorageError.conflict(file.path) }
        for (oldPath, var item) in items.filter({ WorkspaceFileTransfer.contains($0.key, in: file.path) }) {
            items.removeValue(forKey: oldPath)
            let destination = path + oldPath.dropFirst(file.path.count)
            item.file.path = destination
            items[destination] = item
        }
        guard let moved = items[path]?.file else { throw StorageError.invalidResponse }
        return moved
    }

    func releaseMove() {
        moveReleased = true
        moveContinuation?.resume()
        moveContinuation = nil
    }

    func contents(_ path: String) -> String? {
        items[path].flatMap { String(data: $0.data, encoding: .utf8) }
    }
}
