import XCTest
@testable import Orgenda

@MainActor
final class EmacsProfileIntegrationTests: XCTestCase {
    func testRepeatingCompletionRollsBackWhenMetadataCannotBePatched() async throws {
        let source = "* TODO Repeat\nSCHEDULED: <2026-09-01 Tue 09:00 .+1d>\n:PROPERTIES:\n:LAST_REPEAT: [2026-08-31 Mon 09:00]\n:LAST_REPEAT: [2026-08-30 Sun 09:00]\n:END:\n"
        let store = makeStore(["agenda/routines.org": source])
        store.toggleDone(try XCTUnwrap(store.items.first))
        await store.waitForWorkspaceIndex()
        XCTAssertEqual(store.documents.first?.contents, source)
        XCTAssertEqual(store.items.first?.state, .todo)
        XCTAssertNotNil(store.operationError)
    }

    func testMultipleIndependentRepeatersAreKeptInsteadOfPartlyAdvanced() throws {
        let source = "* TODO Repeat\nSCHEDULED: <2026-09-01 Tue +1d> DEADLINE: <2026-09-03 Thu +1d>\n"
        let store = makeStore(["agenda/routines.org": source])
        store.toggleDone(try XCTUnwrap(store.items.first))
        XCTAssertEqual(store.documents.first?.contents, source)
        XCTAssertNotNil(store.operationError)
    }

    func testMoveWaitsForExternalHeadingChangesBeforeUsingOffsets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agenda"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("agenda/actions.org")
        try "* TODO A\n".write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        let baseline = try XCTUnwrap(store.items.first)
        try "* TODO B\n".write(to: url, atomically: true, encoding: .utf8)
        let success = await store.archiveItem(baseline)
        XCTAssertFalse(success)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "* TODO B\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("agenda/archives/actions-\(Calendar(identifier: .gregorian).component(.year, from: .now)).org").path))
    }

    private func makeStore(_ sources: [String: String]) -> WorkspaceStore {
        let store = WorkspaceStore(documents: sources.map { WorkspaceDocument(path: $0.key, title: $0.key, contents: $0.value, kind: .org) })
        store.usesEmacsConfiguration = true
        store.parseWorkspace()
        return store
    }

}
