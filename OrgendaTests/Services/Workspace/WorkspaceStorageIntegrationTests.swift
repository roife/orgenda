import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStorageIntegrationTests: XCTestCase {
    func testExternalUnicodeNormalizationUpdatesSourceBytesAndIndex() async throws {
        let environment = try makeEnvironment()
        let file = environment.folder.appendingPathComponent("inbox.org")
        let original = "* TODO Caf\u{00E9}\n* TODO Next\n"
        let updated = "* TODO Cafe\u{0301}\n* TODO Next\n"
        XCTAssertEqual(original, updated)
        XCTAssertNotEqual(Data(original.utf8), Data(updated.utf8))
        try original.write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore(environment.cache)
        await store.connectFolder(environment.folder, remember: false)
        let priorByte = try XCTUnwrap(store.items.first { $0.title == "Next" }?.source.startByte)
        try updated.write(to: file, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        await store.waitForWorkspaceIndex()
        XCTAssertEqual(Data(try XCTUnwrap(store.documents.first?.contents).utf8), Data(updated.utf8))
        XCTAssertEqual(store.items.first { $0.title == "Next" }?.source.startByte, priorByte + 1)
    }

    func testOfflineRestartRestoresCommittedDraftAndSyncsAfterFolderReturns() async throws {
        let environment = try makeEnvironment()
        let file = environment.folder.appendingPathComponent("inbox.org")
        try "* Original\n".write(to: file, atomically: true, encoding: .utf8)
        let first = makeStore(environment.cache)
        await first.connectFolder(environment.folder, defaults: environment.defaults)
        first.updateDocument(path: "inbox.org", contents: "* Offline draft 中文\n")
        await first.persistFileEdits()
        first.fileSaveTask?.cancel()
        XCTAssertTrue(first.dirtyFilePaths.isEmpty)
        XCTAssertEqual(first.pendingUploadPaths, ["inbox.org"])
        try FileManager.default.removeItem(at: environment.folder)

        let reopened = makeStore(environment.cache)
        await reopened.startWorkspace(arguments: [], defaults: environment.defaults,
                                      localWorkspaceURL: environment.folder)
        XCTAssertTrue(reopened.isWorkspaceReady)
        XCTAssertEqual(reopened.documents.first?.contents, "* Offline draft 中文\n")
        XCTAssertEqual(reopened.pendingUploadCount, 1)
        await reopened.synchronizeFiles()
        XCTAssertEqual(reopened.documents.first?.contents, "* Offline draft 中文\n")
        XCTAssertEqual(reopened.saveStatus(for: "inbox.org"), .pendingSync)

        try FileManager.default.createDirectory(at: environment.folder, withIntermediateDirectories: true)
        try "* Original\n".write(to: file, atomically: true, encoding: .utf8)
        await reopened.connectFolder(environment.folder, defaults: environment.defaults)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "* Offline draft 中文\n")
        XCTAssertEqual(reopened.pendingUploadCount, 0)
    }

    func testFailedNewConnectionLeavesCurrentWorkspaceAndDescriptor() async throws {
        let environment = try makeEnvironment()
        try "* Keep me\n".write(to: environment.folder.appendingPathComponent("inbox.org"), atomically: true, encoding: .utf8)
        let store = makeStore(environment.cache)
        await store.connectFolder(environment.folder, defaults: environment.defaults)
        let connection = store.storageConnection
        let persisted = environment.defaults.data(forKey: WorkspaceStore.storageConnectionKey)
        let broken = environment.folder.appendingPathComponent("missing")
        await store.connectFolder(broken, defaults: environment.defaults)
        XCTAssertEqual(store.storageConnection, connection)
        XCTAssertEqual(environment.defaults.data(forKey: WorkspaceStore.storageConnectionKey), persisted)
        XCTAssertEqual(store.documents.first?.contents, "* Keep me\n")
        XCTAssertNotNil(store.fileSyncError)
    }

    func testChangingLocationRequiresPreservingConflictAndDoesNotUploadItToNewFolder() async throws {
        let environment = try makeEnvironment()
        let file = environment.folder.appendingPathComponent("inbox.org")
        try "* Base\n".write(to: file, atomically: true, encoding: .utf8)
        let nextFolder = environment.cache.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: nextFolder, withIntermediateDirectories: true)
        let store = makeStore(environment.cache)
        await store.connectFolder(environment.folder, remember: false)
        let old = try XCTUnwrap(store.workspaceSession)
        store.updateDocument(path: "inbox.org", contents: "* My draft\n")
        try "* Remote version\n".write(to: file, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        await store.connectFolder(nextFolder, remember: false)
        XCTAssertEqual(store.storageConnection?.rootID, environment.folder.path)
        XCTAssertEqual(store.syncConflicts.count, 1)

        await store.connectFolder(nextFolder, remember: false, preservePending: true)
        XCTAssertEqual(store.storageConnection?.rootID, nextFolder.path)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: nextFolder.path).isEmpty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "* Remote version\n")
        let retired = try await old.snapshot()
        XCTAssertTrue(retired.pendingPaths.isEmpty)
        XCTAssertTrue(retired.conflicts.isEmpty)
    }

    func testStaleConflictConfirmationDoesNotDiscardUpdatedDraft() async throws {
        let environment = try makeEnvironment()
        let file = environment.folder.appendingPathComponent("inbox.org")
        try "* Base\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore(environment.cache)
        await store.connectFolder(environment.folder, remember: false)
        store.updateDocument(path: "inbox.org", contents: "* Local\n")
        try "* Remote\n".write(to: file, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        let shown = try XCTUnwrap(store.syncConflicts.first)
        store.updateDocument(path: "inbox.org", contents: "* New local edit\n")
        await store.resolveSyncConflict(path: "inbox.org", resolution: .useRemote, expectedConflict: shown)
        XCTAssertEqual(store.documents.first?.contents, "* New local edit\n")
        XCTAssertEqual(store.syncConflicts.count, 1)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "* Remote\n")
        store.fileSaveTask?.cancel()
    }

    private struct Environment {
        let folder: URL
        let cache: URL
        let defaults: UserDefaults
    }

    private func makeStore(_ cache: URL) -> WorkspaceStore {
        let store = WorkspaceStore()
        store.storageCacheDirectory = cache
        return store
    }

    private func makeEnvironment() throws -> Environment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Workspace", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "WorkspaceStorageIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return Environment(folder: folder, cache: cache, defaults: defaults)
    }
}
