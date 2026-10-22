import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceDocumentCreationTests: XCTestCase {
    func testNewTaskBeforeExistingFileDoesNotOverwriteThatFile() throws {
        let existing = WorkspaceDocument(path: "z.org", title: "Existing", contents: "* Keep this file\n", kind: .org)
        let store = WorkspaceStore(documents: [existing])
        let draft = OrgItem(
            id: UUID(), title: "New task", state: store.configuration.workflow.initial,
            kind: .task, priority: .none, tags: [], scheduled: nil, deadline: nil,
            hasTime: false, durationMinutes: 0, recurrence: nil, body: "Task notes.",
            source: SourceLocation(file: "a.org", startByte: 0, endByte: 0, startLine: 1),
            habitHistory: []
        )

        XCTAssertTrue(store.save(draft))
        XCTAssertEqual(store.documentsByPath[existing.path], existing)
        XCTAssertEqual(store.documentsByPath["a.org"]?.contents, "* TODO New task\nTask notes.")
        store.parseWorkspace()
        let saved = try XCTUnwrap(store.items.first { $0.title == draft.title })
        XCTAssertEqual(saved.source.file, "a.org")
        XCTAssertEqual(saved.body, draft.body)
    }

    func testNewJournalBeforeExistingFileDoesNotOverwriteThatFile() throws {
        let existing = WorkspaceDocument(path: "z.org", title: "Existing", contents: "* Keep this file\n", kind: .org)
        let store = WorkspaceStore(documents: [existing])
        let date = try XCTUnwrap(Date.orgTimestamp(year: 2026, month: 10, day: 22))
        let path = "\(store.configuration.files.journal)/\(Calendar.autoupdatingCurrent.component(.year, from: date)).org"

        store.addJournalEntry(title: "New entry", body: "Journal notes.", date: date)
        XCTAssertEqual(store.documentsByPath[existing.path], existing)
        XCTAssertTrue(try XCTUnwrap(store.documentsByPath[path]?.contents).contains("New entry\nJournal notes."))
        store.parseWorkspace()
        let entry = try XCTUnwrap(store.journalEntries.first { $0.title == "New entry" })
        XCTAssertEqual(entry.source.file, path)
        XCTAssertEqual(entry.body, "Journal notes.")
    }
}
