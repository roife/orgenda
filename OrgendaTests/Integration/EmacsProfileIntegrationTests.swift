import XCTest
@testable import Orgenda

@MainActor
final class EmacsProfileIntegrationTests: XCTestCase {
    func testOverdueRequiresAnExplicitOpenWorkflowState() throws {
        let store = makeStore([
            "agenda/calendar.org": "* Birthday\n<2019-05-20 Mon +1y>\n* Past event\n<2019-05-20 Mon>\n* Scheduled event\nSCHEDULED: <2019-05-20 Mon>\n",
            "agenda/actions.org": "* TODO Overdue task\nSCHEDULED: <2019-05-20 Mon>\n* DONE Finished\nSCHEDULED: <2019-05-20 Mon>\n* CANCELED Canceled\nDEADLINE: <2019-05-20 Mon>\n* TODO Undated\n",
            "agenda/routines.org": "* TODO Overdue habit\nSCHEDULED: <2019-05-20 Mon +1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"
        ])
        XCTAssertEqual(store.overdueCount, 2)
        XCTAssertEqual(Set(store.datedItems.filter(\.isOverdue).map(\.title)), ["Overdue task", "Overdue habit"])
        XCTAssertTrue(store.items.filter { !$0.hasWorkflowState }.allSatisfy { !$0.isOverdue })
    }

    func testOverduePerspectiveListsOpenDatedItemsOldestFirst() throws {
        let store = makeStore([
            "agenda/actions.org": "* TODO Older\nSCHEDULED: <2019-05-18 Sat>\n* TODO Newer\nDEADLINE: <2019-05-20 Mon>\n* DONE Past\nSCHEDULED: <2019-05-19 Sun>\n* TODO Future\nSCHEDULED: <2027-01-01 Fri>\n* TODO Undated\n",
            "agenda/someday.org": "* TODO Dated someday\nSCHEDULED: <2019-05-19 Sun>\n",
            "agenda/calendar.org": "* Plain past event\n<2019-05-20 Mon>\n"
        ])
        XCTAssertEqual(store.overdueItems.map(\.title), ["Older", "Newer"])
        XCTAssertEqual(store.agendaGroups(for: .overdue).flatMap(\.items).map(\.title), ["Older", "Newer"])
    }

    func testPlainRecurringEventCompletionPreservesSourceAndCanUndo() async throws {
        for time in ["", " 09:00-10:00"] {
            let source = "* Birthdays\n** Birthday 中文🙂\n:PROPERTIES:\n:APPLE_EVENT_ID: keep-id\n:APPLE_CALENDAR: Birthdays\n:END:\n<2019-05-20 Mon\(time) +1y -2d>\nKeep notes.\n*** Child\nKeep child.\n** Another event\n<2026-10-01 Thu>\n"
            let store = makeStore(["agenda/calendar.org": source])
            let item = try XCTUnwrap(store.items.first { $0.title == "Birthday 中文🙂" })
            XCTAssertFalse(item.hasWorkflowState)
            XCTAssertTrue(item.canComplete)
            XCTAssertFalse(item.isOverdue)
            let change = try XCTUnwrap(store.gestureChange(for: item, label: "Occurrence completed") {
                store.toggleDone(item)
            })
            await store.waitForWorkspaceIndex()
            let after = store.documents[0].contents
            XCTAssertTrue(after.contains("<2020-05-20 Wed\(time) +1y -2d>"))
            XCTAssertTrue(after.contains(":APPLE_EVENT_ID: keep-id\n:APPLE_CALENDAR: Birthdays"))
            XCTAssertTrue(after.contains("** Birthday 中文🙂\n"))
            XCTAssertTrue(after.hasSuffix("Keep notes.\n*** Child\nKeep child.\n** Another event\n<2026-10-01 Thu>\n"))
            XCTAssertFalse(after.contains("TODO"))
            XCTAssertFalse(after.contains("DONE"))
            XCTAssertFalse(after.contains("CLOSED:"))
            XCTAssertFalse(after.contains(":event:"))
            let completed = try XCTUnwrap(store.items.first { $0.title == item.title })
            XCTAssertEqual(completed.kind, .event)
            XCTAssertFalse(completed.hasWorkflowState)
            XCTAssertNotNil(completed.properties["LAST_REPEAT"])
            XCTAssertTrue(store.undoGesture(change))
            XCTAssertEqual(store.documents[0].contents, source)
        }
    }

    func testRecurringEventCompletionRejectsAmbiguousSourceAtomically() throws {
        for source in [
            "* Birthday\n<2019-05-20 Mon +1y>\n<2019-06-20 Thu +1y>\n",
            "* Birthday\n:PROPERTIES:\n:LAST_REPEAT: [2025-05-20 Tue]\n:LAST_REPEAT: [2024-05-20 Mon]\n:END:\n<2019-05-20 Mon +1y>\n"
        ] {
            let store = makeStore(["agenda/calendar.org": source])
            let item = try XCTUnwrap(store.items.first)
            store.toggleDone(item)
            XCTAssertEqual(store.documents[0].contents, source)
            XCTAssertEqual(store.items.first, item)
            XCTAssertNotNil(store.operationError)
        }
    }

    func testDashboardDateScopeDoesNotFilterTaskViews() throws {
        let store = makeStore(["agenda/actions.org": "* TODO Soon\nSCHEDULED: <2026-09-21 Mon>\n* NEXT Later\nSCHEDULED: <2026-10-20 Tue>\n"])
        let now = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 20)))
        let groups = store.agendaGroups(for: .dashboard, now: now)
        XCTAssertEqual(groups.filter(\.isDateGroup).flatMap(\.items).map(\.title), ["Soon"])
        XCTAssertEqual(groups.filter { !$0.isDateGroup && $0.title == "Next actions" }.flatMap(\.items).map(\.title), ["Later"])
        let empty = makeStore([:]).agendaGroups(for: .dashboard, now: now)
        XCTAssertTrue(empty.first?.isDateGroup == true)
        XCTAssertTrue(empty.allSatisfy { $0.items.isEmpty })
    }

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

    func testPreviewPlanningMutationKeepsItsLogbook() throws {
        let store = makeStore(["agenda/actions.org": "* NEXT Work\nSCHEDULED: <2026-09-01 Tue 09:00 +1w>\n"])
        let entry = try XCTUnwrap(store.parsedDocuments["agenda/actions.org"]?.root.children.first(where: { $0.type == "planning" })?.children.first(where: { $0.type == "planning_entry" }))
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(source: entry.text))
        draft.timestamps[0].date = draft.timestamps[0].date.addingTimeInterval(86_400)
        XCTAssertTrue(store.applyPlanningDraft(path: "agenda/actions.org", node: entry, draft: draft))
        let source = try XCTUnwrap(store.documents.first?.contents)
        XCTAssertTrue(source.contains("SCHEDULED: <2026-09-02 Wed 09:00 +1w>"))
        XCTAssertTrue(source.contains("- Rescheduled from \"[2026-09-01 Tue 09:00 +1w]\""))
    }

    private func makeStore(_ sources: [String: String]) -> WorkspaceStore {
        let store = WorkspaceStore(documents: sources.map { WorkspaceDocument(path: $0.key, title: $0.key, contents: $0.value, kind: .org) })
        store.usesEmacsConfiguration = true
        store.parseWorkspace()
        return store
    }

    func testAgendaScopeExcludesArchivesAndNotesAndCompletedItems() {
        let store = makeStore([
            "agenda/actions.org": "* NEXT Visible\nSCHEDULED: <2026-09-12 Sat>\n* DONE Complete\nSCHEDULED: <2026-09-12 Sat>\n",
            "agenda/archives/old.org": "* TODO Archived\nSCHEDULED: <2026-09-12 Sat>\n",
            "note/note.org": "* TODO Notes task\nSCHEDULED: <2026-09-12 Sat>\n"])
        XCTAssertEqual(store.items.count, 4, "Files and global search retain all headings")
        XCTAssertEqual(store.datedItems.map(\.title), ["Visible"])
        XCTAssertEqual(store.agendaSourceCount, 1)
    }

    func testCaptureInsertsIntoNamedParentAndWritesMetadata() async throws {
        let store = makeStore(["agenda/actions.org": "#+title: Actions\n* Actions\n** TODO Existing\n* Unrelated\nKeep this\n"])
        var draft = OrgCaptureTemplate.nextAction.applyingDefaults(to: Self.item())
        draft.title = "中文 capture"
        XCTAssertTrue(store.save(draft, captureTemplate: .nextAction))
        await store.waitForWorkspaceIndex()
        let source = try XCTUnwrap(store.documents.first?.contents)
        XCTAssertTrue(source.contains("** NEXT 中文 capture\n:PROPERTIES:\n:CREATED: ["))
        XCTAssertTrue(source.hasSuffix("* Unrelated\nKeep this\n"))
        XCTAssertEqual(source.components(separatedBy: "* Actions\n").count, 2)
        XCTAssertTrue(store.items.contains { $0.title == "中文 capture" && $0.source.file == "agenda/actions.org" })
    }

    func testCalendarCaptureUsesActiveTimestampAndAppearsInAgenda() async throws {
        let store = makeStore([:])
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        var item = OrgCaptureTemplate.calendarEvent.applyingDefaults(to: Self.item(), date: date)
        item.title = "Meeting"
        XCTAssertTrue(store.save(item, captureTemplate: .calendarEvent))
        await store.waitForWorkspaceIndex()
        let source = try XCTUnwrap(store.documents.first?.contents)
        XCTAssertFalse(source.contains("SCHEDULED:"))
        XCTAssertFalse(source.contains("* TODO"))
        XCTAssertTrue(source.contains(":APPT_WARNTIME: 15"))
        XCTAssertEqual(store.items(on: date).first?.title, "Meeting")
    }

    func testConfiguredCompletionHidesItemAndWritesTimedLogbook() throws {
        let store = makeStore(["agenda/actions.org": "* NEXT First\nSCHEDULED: <2026-09-12 Sat>\n* TODO Second\n"])
        let first = try XCTUnwrap(store.items.first { $0.title == "First" })
        store.toggleDone(first)
        XCTAssertFalse(store.datedItems.contains { $0.id == first.id })
        let source = try XCTUnwrap(store.documents.first?.contents)
        XCTAssertTrue(source.contains(":LOGBOOK:"))
        XCTAssertTrue(source.contains("- State \"DONE\" from \"NEXT\" ["))
        XCTAssertNotNil(source.range(of: #"CLOSED: \[\d{4}-\d{2}-\d{2} \w+ \d{2}:\d{2}\]"#, options: .regularExpression))
        var second = try XCTUnwrap(store.items.first { $0.title == "Second" })
        second.title = "Second edited immediately"
        XCTAssertTrue(store.save(second), "Inserted logs must rebase following headings before async parsing")
    }

    func testRepeatingCompletionAdvancesAndRemainsOpen() async throws {
        let store = makeStore(["agenda/routines.org": "* TODO Repeat\nSCHEDULED: <2026-09-01 Tue 09:00 .+1d>\n"])
        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.kind, .task, "A repeating reminder is not automatically a habit")
        store.toggleDone(item)
        await store.waitForWorkspaceIndex()
        let next = try XCTUnwrap(store.items.first)
        XCTAssertEqual(next.state, .todo)
        XCTAssertTrue(try XCTUnwrap(next.scheduled) > .now)
        XCTAssertNotNil(next.properties["LAST_REPEAT"])
        XCTAssertTrue(store.documents[0].contents.contains("from \"TODO\""))
        XCTAssertNil(next.closed)
    }

    func testConfiguredViewsUseTheirOwnSourceSetsAndUnifiedStates() {
        let store = makeStore([
            "agenda/actions.org": "* URGENT Action\n* NEXT Next\n* SOMEDAY Excluded someday\n",
            "agenda/calendar.org": "* URGENT Calendar-only\n",
            "agenda/work.org": "* TODO Project :project:\n* DONE Finished :project:\n* SOMEDAY Later\n",
            "agenda/personal.org": "* TODO Personal :project:\n",
            "agenda/someday.org": "* SOMEDAY Maybe\nSCHEDULED: <2026-09-19 Sat>\n",
            "agenda/extra.org": "* NEXT Extra file\n"])
        XCTAssertEqual(store.agendaGroups(for: .urgent).flatMap(\.items).map(\.title), ["Action"])
        XCTAssertEqual(store.agendaGroups(for: .projects).flatMap(\.items).map(\.title), ["Personal", "Project"])
        XCTAssertEqual(Set(store.agendaGroups(for: .someday).flatMap(\.items).map(\.title)), ["Later", "Maybe"])
        XCTAssertFalse(store.agendaItems.contains { $0.title == "Extra file" })
        XCTAssertFalse(store.datedItems.contains { $0.title == "Maybe" })
        XCTAssertEqual(OrgWorkspaceConfiguration.taskStates, [.todo, .next, .wait, .someday, .urgent, .done, .canceled])
        XCTAssertEqual(OrgWorkflowState.allCases.map(\.rawValue), ["TODO", "NEXT", "WAIT", "SOMEDAY", "URGENT", "DONE", "CANCELED"])
        let project = store.items.first { $0.title == "Project" }!
        store.toggleDone(project)
        XCTAssertEqual(store.items.first { $0.id == project.id }?.state, .done)
    }

    func testArchivePersistsDestinationBeforeRemovingSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agenda"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("agenda/actions.org")
        let source = "* TODO Archive me\n:PROPERTIES:\n:CUSTOM: keep\n:END:\n** NEXT Child\n* TODO Keep me\n"
        try source.write(to: url, atomically: true, encoding: .utf8)
        let store = WorkspaceStore()
        await store.connectFolder(root, remember: false)
        let item = try XCTUnwrap(store.items.first { $0.title == "Archive me" })
        let success = await store.archiveItem(item)
        XCTAssertTrue(success, store.operationError ?? "")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("Archive me"))
        let archive = try String(contentsOf: root.appendingPathComponent("agenda/archives/actions-\(Calendar(identifier: .gregorian).component(.year, from: .now)).org"), encoding: .utf8)
        XCTAssertTrue(archive.contains("** TODO Archive me"))
        XCTAssertTrue(archive.contains(":CUSTOM: keep"))
        XCTAssertTrue(archive.contains("*** NEXT Child"))
        XCTAssertFalse(store.agendaItems.contains { $0.title == "Archive me" })
        XCTAssertTrue(store.documents.contains { $0.path == "agenda/archives/actions-\(Calendar(identifier: .gregorian).component(.year, from: .now)).org" })
    }

    func testReminderUsesPerEntryWarningAndFiveMinuteCadence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var item = Self.item(); item.hasTime = true; item.scheduled = now.addingTimeInterval(3_600)
        item.properties["APPT_WARNTIME"] = "10"
        let plan = OrgReminderPlan.reminders(for: [item], now: now)
        XCTAssertEqual(plan.map { Int($0.date.timeIntervalSince(now)) }, [3_000, 3_300, 3_600])
        item.state = .done
        XCTAssertTrue(OrgReminderPlan.reminders(for: [item], now: now).isEmpty)
    }

    func testReminderUsesEachTimestampTimeAndOwnRepeater() throws {
        let store = makeStore(["agenda/actions.org": "* TODO Mixed\nSCHEDULED: <2026-09-19 Sat 10:00 +1d>\nDEADLINE: <2026-09-20 Sun>\nA record [2026-09-20 Sun 16:00]--[2026-09-21 Mon 16:00].\n"])
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 9)))
        let reminders = OrgReminderPlan.reminders(for: store.items, documents: store.documents, now: now)
        XCTAssertEqual(reminders.count, 4)
        XCTAssertTrue(reminders.allSatisfy { calendar.isDate($0.date, inSameDayAs: now) })
        XCTAssertEqual(reminders.map { calendar.component(.hour, from: $0.date) }, [9, 9, 9, 10])
    }

    private static func item() -> OrgItem {
        OrgItem(id: UUID(), title: "Fixture", state: .todo, kind: .task, priority: .none,
                tags: [], scheduled: nil, deadline: nil, hasTime: false, durationMinutes: 30,
                recurrence: nil, body: "", source: SourceLocation(file: "agenda/inbox.org", startByte: 0, endByte: 0, startLine: 1), habitHistory: [])
    }
}
