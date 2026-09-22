import Observation
import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceConnectionTests: XCTestCase {
    func testWorkspaceStartsInLoadingStateBeforeStartupTaskRuns() {
        XCTAssertTrue(WorkspaceStore().isStartingWorkspace)
        XCTAssertTrue(WorkspaceStore.preview().isStartingWorkspace)
    }

    #if DEBUG
    func testUITestStartupWaitsForInitialIndexWithoutOpeningUserWorkspace() async throws {
        let arguments = ["--ui-test-workspace"]
        let store = WorkspaceStore.startup(arguments: arguments)
        let defaults = try startupDefaults()
        defaults.set(Data("invalid bookmark".utf8), forKey: "workspaceFolderBookmark")
        let localURL = try folder().appendingPathComponent("Workspace")
        await store.startWorkspace(arguments: arguments, defaults: defaults, localWorkspaceURL: localURL)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertFalse(store.isFolderConnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
        XCTAssertNil(store.fileSyncError)
        XCTAssertNil(store.parseTask)
        XCTAssertNotNil(store.parsedDocuments["inbox.org"])
        XCTAssertTrue(store.items.contains { $0.title == "Review quarterly roadmap" })
    }
    #endif

    func testFirstLaunchCreatesEmptyPersistentLocalWorkspace() async throws {
        let root = try folder()
        let localURL = root.appendingPathComponent("Workspace", isDirectory: true)
        let defaults = try startupDefaults()
        let store = WorkspaceStore.startup(arguments: [])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        await store.startWorkspace(
            arguments: [],
            defaults: defaults,
            localWorkspaceURL: localURL
        )
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertTrue(store.isFolderConnected)
        XCTAssertTrue(store.usesEmacsConfiguration)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(store.journalEntries.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: localURL.path).isEmpty)
        XCTAssertNil(defaults.data(forKey: "workspaceFolderBookmark"))
        XCTAssertNil(store.fileSyncError)
        XCTAssertNil(store.parseTask)
    }

    func testFirstTaskInLocalWorkspacePersistsAcrossStartup() async throws {
        let localURL = try folder().appendingPathComponent("Workspace", isDirectory: true)
        let defaults = try startupDefaults()
        let store = WorkspaceStore.startup(arguments: [])
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: localURL)
        let task = OrgItem(
            id: UUID(), title: "My first saved task 中文", state: .todo, kind: .task,
            priority: .none, tags: [], scheduled: nil, deadline: nil, hasTime: false,
            durationMinutes: 30, recurrence: nil, body: "Keep this after relaunch.",
            source: SourceLocation(file: OrgCaptureTemplate.inboxTask.destinationPath,
                                   startByte: 0, endByte: 0, startLine: 1), habitHistory: []
        )
        XCTAssertTrue(store.save(task))
        await store.synchronizeFiles()
        XCTAssertNil(store.fileSyncError)
        XCTAssertEqual(store.pendingFileCount, 0)
        let fileURL = localURL.appendingPathComponent(OrgCaptureTemplate.inboxTask.destinationPath)
        let savedContents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(savedContents.contains(task.title))

        let reopened = WorkspaceStore.startup(arguments: [])
        await reopened.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: localURL)
        XCTAssertTrue(reopened.isFolderConnected)
        XCTAssertEqual(reopened.items.map(\.title), [task.title])
        XCTAssertEqual(reopened.items.first?.body, task.body)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), savedContents)
        XCTAssertNil(reopened.fileSyncError)
    }

    func testExistingLocalWorkspaceContentsAreNeverSeededOrReplaced() async throws {
        let localURL = try folder()
        let fileURL = localURL.appendingPathComponent("inbox.org")
        let original = "#+title: Existing workspace\n* TODO Keep my existing task\n"
        try original.write(to: fileURL, atomically: true, encoding: .utf8)
        let attachmentURL = localURL.appendingPathComponent("attachment.bin")
        let attachment = Data([0, 255, 42, 128])
        try attachment.write(to: attachmentURL)
        let store = WorkspaceStore.startup(arguments: [])
        await store.startWorkspace(arguments: [], defaults: try startupDefaults(), localWorkspaceURL: localURL)
        XCTAssertTrue(store.isFolderConnected)
        XCTAssertEqual(store.items.map(\.title), ["Keep my existing task"])
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), original)
        XCTAssertEqual(try Data(contentsOf: attachmentURL), attachment)
        XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: localURL.path)),
                       ["inbox.org", "attachment.bin"])
    }

    func testSavedFolderTakesPrecedenceOverCreatingLocalWorkspace() async throws {
        let savedURL = try folder()
        let localURL = try folder().appendingPathComponent("Workspace", isDirectory: true)
        let defaults = try startupDefaults()
        let bookmark = try savedURL.bookmarkData(options: .minimalBookmark,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: "workspaceFolderBookmark")
        try "* TODO Saved folder task\n".write(to: savedURL.appendingPathComponent("inbox.org"),
                                               atomically: true, encoding: .utf8)
        let store = WorkspaceStore.startup(arguments: [])
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: localURL)
        XCTAssertEqual(store.items.map(\.title), ["Saved folder task"])
        XCTAssertTrue(store.isFolderConnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
        XCTAssertNil(store.fileSyncError)
    }

    func testLocalWorkspaceCreationFailureStaysEmptyAndCanRetry() async throws {
        let root = try folder()
        let localURL = root.appendingPathComponent("Workspace")
        try Data("Blocking file".utf8).write(to: localURL)
        let defaults = try startupDefaults()
        let store = WorkspaceStore.startup(arguments: [])
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: localURL)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertFalse(store.hasStarted)
        XCTAssertFalse(store.isFolderConnected)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertNotNil(store.fileSyncError)
        XCTAssertEqual(try String(contentsOf: localURL, encoding: .utf8), "Blocking file")

        try FileManager.default.removeItem(at: localURL)
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: localURL)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertTrue(store.isFolderConnected)
        XCTAssertTrue(store.hasStarted)
        XCTAssertNil(store.fileSyncError)
    }

    func testConnectedStartupKeepsLoadingUntilItemsAreIndexed() async throws {
        let root = try folder()
        try "* TODO From startup\n".write(to: root.appendingPathComponent("inbox.org"), atomically: true, encoding: .utf8)
        let store = WorkspaceStore.preview()
        let ready = expectation(description: "Initial index is published before loading ends")
        withObservationTracking {
            _ = store.isStartingWorkspace
        } onChange: {
            MainActor.assumeIsolated {
                XCTAssertTrue(store.isFolderConnected)
                XCTAssertEqual(store.items.map(\.title), ["From startup"])
                XCTAssertNotNil(store.parsedDocuments["inbox.org"])
                XCTAssertNil(store.parseTask)
                ready.fulfill()
            }
        }

        await store.startWorkspace(arguments: [], defaults: try startupDefaults(), localWorkspaceURL: root)
        await fulfillment(of: [ready], timeout: 1)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertNil(store.fileSyncError)

        try "* TODO Refreshed\n".write(to: root.appendingPathComponent("inbox.org"), atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        XCTAssertFalse(store.isStartingWorkspace)
        await store.waitForWorkspaceIndex()
        XCTAssertEqual(store.items.map(\.title), ["Refreshed"])
    }

    func testEmptyFolderFinishesStartupWithRealEmptyState() async throws {
        let root = try folder()
        let store = WorkspaceStore.preview()
        await store.startWorkspace(arguments: [], defaults: try startupDefaults(), localWorkspaceURL: root)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertTrue(store.isFolderConnected)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(store.journalEntries.isEmpty)
        XCTAssertNil(store.fileSyncError)
    }

    func testInvalidBookmarkEndsLoadingAndKeepsErrorAvailable() async throws {
        let defaults = try startupDefaults()
        defaults.set(Data("invalid bookmark".utf8), forKey: "workspaceFolderBookmark")
        let localURL = try folder().appendingPathComponent("Workspace", isDirectory: true)
        let store = WorkspaceStore.startup(arguments: [])
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: localURL)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertFalse(store.hasStarted)
        XCTAssertFalse(store.isFolderConnected)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
        XCTAssertNotNil(store.fileSyncError)
    }

    func testCancelledStartupKeepsLoadingAndCanRetry() async throws {
        let root = try folder()
        let defaults = try startupDefaults()
        let store = WorkspaceStore()
        store.isSynchronizing = true
        let startup = Task {
            await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: root)
        }
        while !store.hasStarted { await Task.yield() }
        XCTAssertTrue(store.isStartingWorkspace)

        // A repeated call must not dismiss the first call's loading state.
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: root)
        XCTAssertTrue(store.isStartingWorkspace)
        startup.cancel()
        await startup.value
        XCTAssertFalse(store.hasStarted)
        XCTAssertTrue(store.isStartingWorkspace)

        store.isSynchronizing = false
        await store.startWorkspace(arguments: [], defaults: defaults, localWorkspaceURL: root)
        XCTAssertTrue(store.hasStarted)
        XCTAssertFalse(store.isStartingWorkspace)
        XCTAssertTrue(store.isFolderConnected)
    }

    func testFileGesturesMoveDeleteRestoreAndReindexConnectedFolder() async throws {
        let root = try folder()
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("projects"), withIntermediateDirectories: true)
        try "* TODO Move me\n".write(to: root.appendingPathComponent("task.org"), atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        let task = try XCTUnwrap(store.documents.first { $0.path == "task.org" })
        let originalItemID = store.items.first?.id
        let moved = await store.moveFile(store.fileTransfer(task), to: "projects")
        XCTAssertTrue(moved, store.fileActionError ?? "")
        XCTAssertEqual(store.items.first?.source.file, "projects/task.org")
        XCTAssertEqual(store.items.first?.id, originalItemID)
        XCTAssertFalse(manager.fileExists(atPath: root.appendingPathComponent("task.org").path))
        await store.undoFileAction()
        XCTAssertEqual(store.items.first?.source.file, "task.org")
        let deleted = await store.deleteFile(store.fileTransfer(try XCTUnwrap(store.documents.first { $0.path == "task.org" })))
        XCTAssertTrue(deleted, store.fileActionError ?? "")
        XCTAssertTrue(store.items.isEmpty)
        let reopened = WorkspaceStore()
        await reopened.connectFolder(root, remember: false)
        await reopened.reloadDeletedFiles()
        let entry = try XCTUnwrap(reopened.recentlyDeleted.first)
        let restored = await reopened.restoreFile(entry)
        XCTAssertTrue(restored, reopened.fileActionError ?? "")
        XCTAssertEqual(reopened.items.first?.title, "Move me")
    }

    func testFileGestureRejectsExternalEditAndDifferentWorkspace() async throws {
        let root = try folder()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("target"), withIntermediateDirectories: true)
        let url = root.appendingPathComponent("task.org")
        try "* Original\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        let transfer = store.fileTransfer(try XCTUnwrap(store.documents.first { $0.path == "task.org" }))
        try "* External\n".write(to: url, atomically: true, encoding: .utf8)
        let moved = await store.moveFile(transfer, to: "target")
        XCTAssertFalse(moved)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* External\n")
        let other = try folder()
        await store.connectFolder(other, remember: false)
        let deleted = await store.deleteFile(transfer)
        XCTAssertFalse(deleted)
        XCTAssertTrue(store.documents.isEmpty)
    }

    func testDocumentStatusIsPerFileAndReflectsSaveFailureAndRetry() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* Original\n".write(to: url, atomically: true, encoding: .utf8)
        try "* Other\n".write(to: root.appendingPathComponent("other.org"), atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        XCTAssertEqual(store.saveStatus(for: "inbox.org"), .saved)
        let revision = store.externalDocumentRevisions["inbox.org"]
        store.updateDocument(path: "inbox.org", contents: "* My edit\n")
        XCTAssertEqual(store.saveStatus(for: "inbox.org"), .saving)
        XCTAssertEqual(store.saveStatus(for: "other.org"), .saved)
        try "* Conflict\n".write(to: url, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        guard case .failed = store.saveStatus(for: "inbox.org") else { return XCTFail("Missing failure status") }
        XCTAssertEqual(store.saveStatus(for: "other.org"), .saved)
        XCTAssertEqual(store.externalDocumentRevisions["inbox.org"], revision)
        try "* Original\n".write(to: url, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        XCTAssertEqual(store.saveStatus(for: "inbox.org"), .saved)
        XCTAssertNil(store.fileSaveErrors["inbox.org"])
        XCTAssertEqual(store.externalDocumentRevisions["inbox.org"], revision)
        _ = try recoveryFiles(for: root)
    }

    func testWorkspaceAndRecoveryFilesAreExposedToSystemFilesApp() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, true)
    }

    func testSourceJournalEditRebuildsCardsWithoutRestart() async throws {
        let root = try folder()
        let journal = root.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let original = "* 2027-01-05 Tue\n** Before\nOriginal body\n"
        try original.write(to: journal.appendingPathComponent("2027.org"), atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        XCTAssertEqual(store.journalEntries.first?.title, "Before")
        store.updateDocument(path: "journal/2027.org", contents: "* 2027-01-05 Tue\n** After\nEdited body\n")
        await store.waitForWorkspaceIndex()
        XCTAssertEqual(store.journalEntries.first?.title, "After")
        XCTAssertEqual(store.journalEntries.first?.body, "Edited body")
        await store.synchronizeFiles()
        let empty = try folder()
        await store.connectFolder(empty, remember: false)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.journalEntries.isEmpty)
        XCTAssertTrue(store.parsedDocuments.isEmpty)
    }

    private func startupDefaults() throws -> UserDefaults {
        let suiteName = "WorkspaceStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func recoveryFiles(for root: URL) throws -> [URL] {
        let recovery = WorkspaceStore.unsavedEditsFolder(for: root.resolvingSymlinksInPath().standardizedFileURL.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: recovery) }
        return try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
    }

    func testConnectedFolderSavesAndReloadsWithoutDemoData() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* TODO From disk\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore.preview()
        await store.connectFolder(root, remember: false)
        store.parseWorkspace()
        XCTAssertEqual(store.items.map(\.title), ["From disk"])
        var item = try XCTUnwrap(store.items.first)
        item.title = "Saved 中文"
        XCTAssertTrue(store.save(item))
        await store.synchronizeFiles()
        XCTAssertNil(store.fileSyncError)
        XCTAssertEqual(store.pendingFileCount, 0)
        let second = WorkspaceStore()
        await second.connectFolder(root, remember: false)
        second.parseWorkspace()
        XCTAssertEqual(second.items.map(\.title), ["Saved 中文"])
    }

    func testExternalEditAndDeletionReplaceIndex() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* TODO Original\n* TODO Remove me\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        store.parseWorkspace()
        try "* TODO Externally edited\n".write(to: url, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        store.parseWorkspace()
        XCTAssertEqual(store.items.map(\.title), ["Externally edited"])
        try FileManager.default.removeItem(at: url)
        await store.synchronizeFiles()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
    }

    func testConflictPreservesRemoteAndKeepsLocalPending() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* TODO Original\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        store.parseWorkspace()
        try "* TODO Remote\n".write(to: url, atomically: true, encoding: .utf8)
        store.updateDocument(path: "inbox.org", contents: "* TODO Local\n")
        await store.synchronizeFiles()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* TODO Remote\n")
        XCTAssertEqual(store.documents.first?.contents, "* TODO Local\n")
        XCTAssertEqual(store.pendingFileCount, 1)
        XCTAssertNotNil(store.fileSyncError)
    }

    func testAdoptFolderVersionsArchivesLocalDraftAndAllowsNextSave() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* TODO Original\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        store.updateDocument(path: "inbox.org", contents: "* TODO Local draft\n")
        try "* TODO Remote edit\n".write(to: url, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        XCTAssertEqual(store.pendingFileCount, 1)

        let adopted = await store.adoptFolderVersions()
        XCTAssertTrue(adopted)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* TODO Remote edit\n")
        XCTAssertEqual(store.documents.first?.contents, "* TODO Remote edit\n")
        XCTAssertEqual(store.items.map(\.title), ["Remote edit"])
        XCTAssertEqual(store.pendingFileCount, 0)
        XCTAssertNil(store.fileSyncError)
        let savedDrafts = try recoveryFiles(for: root).map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(savedDrafts, ["* TODO Local draft\n"])

        store.updateDocument(path: "inbox.org", contents: "* DONE Remote edit\n")
        await store.synchronizeFiles()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* DONE Remote edit\n")
        XCTAssertEqual(store.pendingFileCount, 0)
        XCTAssertNil(store.fileSyncError)
    }

    func testMatchingRemoteAndLocalEditClearsPendingSave() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* TODO Original\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        store.updateDocument(path: "inbox.org", contents: "* TODO Same edit\n")
        try "* TODO Same edit\n".write(to: url, atomically: true, encoding: .utf8)
        await store.synchronizeFiles()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* TODO Same edit\n")
        XCTAssertEqual(store.pendingFileCount, 0)
        XCTAssertNil(store.fileSyncError)
    }

    func testRecoveryKeepsDistinctDraftsAndSeparatesWorkspaces() async throws {
        let firstRoot = try folder()
        let secondRoot = try folder()
        for root in [firstRoot, secondRoot] {
            let url = root.appendingPathComponent("inbox.org")
            try "* TODO Original\n".write(to: url, atomically: true, encoding: .utf8)
            let store = WorkspaceStore()
            await store.connectFolder(root, remember: false)
            try "* TODO Remote\n".write(to: url, atomically: true, encoding: .utf8)
            store.updateDocument(path: "inbox.org", contents: "* TODO First draft\n")
            await store.synchronizeFiles()
            store.updateDocument(path: "inbox.org", contents: "* TODO Second draft\n")
            await store.synchronizeFiles()
            // Repeated refresh preserves the same versions without duplicates.
            await store.synchronizeFiles()
            let savedDrafts = try Set(recoveryFiles(for: root).map { try String(contentsOf: $0, encoding: .utf8) })
            XCTAssertEqual(savedDrafts, ["* TODO First draft\n", "* TODO Second draft\n"])
        }
        let firstPaths = try Set(recoveryFiles(for: firstRoot))
        let secondPaths = try Set(recoveryFiles(for: secondRoot))
        XCTAssertTrue(firstPaths.isDisjoint(with: secondPaths))
    }

    func testFailedAdoptionKeepsPendingDraft() async throws {
        let root = try folder()
        let url = root.appendingPathComponent("inbox.org")
        try "* TODO Original\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        store.updateDocument(path: "inbox.org", contents: "* TODO Pending draft\n")
        try FileManager.default.removeItem(at: root)
        let adopted = await store.adoptFolderVersions()
        XCTAssertFalse(adopted)
        XCTAssertEqual(store.documents.first?.contents, "* TODO Pending draft\n")
        XCTAssertEqual(store.pendingFileCount, 1)
        XCTAssertNotNil(store.fileSyncError)
        let savedDrafts = try recoveryFiles(for: root).map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(savedDrafts, ["* TODO Pending draft\n"])
    }

    func testNewJournalFilePersistsAndRestoresInSelectedYear() async throws {
        let root = try folder()
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2027, month: 1, day: 5)))
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        store.addJournalEntry(title: "Disk journal", body: "中文 and source", date: date)
        await store.synchronizeFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("journal/2027.org").path))
        let next = WorkspaceStore()
        await next.connectFolder(root, remember: false)
        XCTAssertEqual(next.journal(on: date).first?.title, "Disk journal")
        XCTAssertEqual(next.journal(on: date).first?.body, "中文 and source")
    }

    func testRootFolderRowsDoNotRepeatNestedFiles() {
        let docs = [WorkspaceDocument(path: "agenda", title: "agenda", contents: "", kind: .folder),
                    WorkspaceDocument(path: "agenda/tasks.org", title: "tasks", contents: "", kind: .org),
                    WorkspaceDocument(path: "inbox.org", title: "inbox", contents: "", kind: .org)]
        XCTAssertEqual(visibleFolderDocuments(docs, folderPath: "").map(\.path), ["agenda", "inbox.org"])
    }
}
