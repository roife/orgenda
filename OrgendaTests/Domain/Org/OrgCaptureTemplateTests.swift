import XCTest
@testable import Orgenda

final class OrgCaptureTemplateTests: XCTestCase {
    func testCalendarCaptureKeepsItsSelectedDateInInboxSource() {
        var original = fixture()
        original.scheduled = date
        let result = OrgCaptureTemplate.inboxTask.applyingDefaults(
            to: original, date: date, preservingPlanning: true)
        XCTAssertEqual(result.scheduled, date)
        XCTAssertFalse(result.hasTime)
        XCTAssertTrue(OrgCaptureTemplate.inboxTask.source(for: result, createdAt: date).contains("SCHEDULED:"))
    }

    func testSwitchingTemplatesPreservesPlanningAndMapsEventTimestamp() {
        var original = fixture()
        original.scheduled = date
        original.deadline = date.addingTimeInterval(86_400)
        original.hasTime = true
        original.recurrence = "++1w"
        for template in OrgCaptureTemplate.allCases {
            let result = template.applyingDefaults(to: original, date: .distantFuture, preservingPlanning: true)
            XCTAssertEqual(result.deadline, original.deadline, template.rawValue)
            XCTAssertEqual(result.recurrence, "++1w", template.rawValue)
            XCTAssertTrue(result.hasTime, template.rawValue)
            XCTAssertEqual(template == .calendarEvent ? result.eventDate : result.scheduled, date, template.rawValue)
        }
        let event = OrgCaptureTemplate.calendarEvent.applyingDefaults(to: original, preservingPlanning: true)
        let inbox = OrgCaptureTemplate.inboxTask.applyingDefaults(to: event, preservingPlanning: true)
        XCTAssertEqual(inbox.scheduled, date)
        XCTAssertNil(inbox.eventDate)
        XCTAssertEqual(inbox.deadline, original.deadline)
        XCTAssertEqual(inbox.recurrence, original.recurrence)
    }

    @MainActor
    func testSavingRemovedItemAsAnEditDoesNotCreateDuplicateCapture() {
        let store = WorkspaceStore.preview()
        let original = store.items[0]
        var draft = original
        draft.title = "Unsaved changes"
        let documents = store.documents
        store.items.removeAll { $0.id == original.id }
        XCTAssertFalse(store.save(draft, original: original))
        XCTAssertEqual(store.documents, documents)
        XCTAssertFalse(store.items.contains { $0.id == original.id })
    }

    func testAllConfiguredDestinationsAndParentHeadings() {
        let templates = OrgCaptureTemplate.allCases
        XCTAssertEqual(templates.map(\.destinationPath), [
            "agenda/inbox.org", "agenda/inbox.org", "agenda/actions.org",
            "agenda/work.org", "agenda/personal.org",
            "agenda/inbox.org", "agenda/routines.org", "agenda/someday.org", "agenda/calendar.org"
        ])
        XCTAssertEqual(templates.compactMap(\.parentHeading), ["Actions", "Recurring", "Someday / Maybe"])
    }

    func testInboxTaskIsUnscheduledAndHasCreatedMetadata() {
        var original = fixture()
        original.scheduled = date
        original.recurrence = "+1w"
        original.tags = ["@home", "project"]
        let item = OrgCaptureTemplate.inboxTask.applyingDefaults(to: original, date: date)
        let source = OrgCaptureTemplate.inboxTask.source(for: item, createdAt: date)
        XCTAssertEqual(item.source.file, "agenda/inbox.org")
        XCTAssertEqual(item.state, .todo)
        XCTAssertNil(item.scheduled)
        XCTAssertNil(item.recurrence)
        XCTAssertEqual(item.tags, ["@home"])
        XCTAssertTrue(source.hasPrefix("* TODO Test capture :@home:\n:PROPERTIES:\n:CREATED: ["))
        XCTAssertFalse(source.contains("SCHEDULED:"))
        XCTAssertTrue(source.hasSuffix(":END:\nContext\n"))
    }

    func testNoteAndEventHaveNoTodoKeyword() {
        let note = OrgCaptureTemplate.inboxNote.applyingDefaults(to: fixture(), date: date)
        let noteSource = OrgCaptureTemplate.inboxNote.source(for: note, createdAt: date)
        XCTAssertTrue(noteSource.hasPrefix("* Test capture :note:\n"))
        XCTAssertFalse(noteSource.contains("TODO"))
        let event = OrgCaptureTemplate.calendarEvent.applyingDefaults(to: fixture(), date: date)
        let eventSource = OrgCaptureTemplate.calendarEvent.source(for: event, createdAt: date)
        XCTAssertTrue(eventSource.hasPrefix("* Test capture\n:PROPERTIES:"))
        XCTAssertTrue(eventSource.contains(":APPT_WARNTIME: 15\n:END:\n<"))
        XCTAssertFalse(eventSource.contains("TODO"))
        XCTAssertFalse(eventSource.contains("SCHEDULED:"))
        XCTAssertEqual(event.eventDate, date)
        XCTAssertNil(event.scheduled)
    }

    func testNamedParentEntriesUseSecondLevel() {
        for template in [OrgCaptureTemplate.nextAction, .repeatingReminder, .someday] {
            let item = template.applyingDefaults(to: fixture(), date: date)
            let source = template.source(for: item, createdAt: date)
            XCTAssertTrue(source.hasPrefix("** \(item.state.rawValue) Test capture\n"))
        }
    }

    func testProjectAddsNextActionWithoutRepeatingCreatedProperty() {
        for template in [OrgCaptureTemplate.workProject, .personalProject] {
            let item = template.applyingDefaults(to: fixture(), date: date)
            let source = template.source(for: item, createdAt: date, firstAction: "  Outline scope\nThen discuss ")
            XCTAssertEqual(item.state, .todo)
            XCTAssertEqual(item.kind, .project)
            XCTAssertTrue(source.hasPrefix("* TODO Test capture :project:\n"))
            XCTAssertTrue(source.hasSuffix("** NEXT Outline scope Then discuss\n"))
            XCTAssertEqual(source.components(separatedBy: ":CREATED:").count - 1, 1)
        }
    }

    func testRepeatingReminderKeepsConfiguredRepeaterAndIsNotHabit() {
        var item = OrgCaptureTemplate.repeatingReminder.applyingDefaults(to: fixture(), date: date)
        XCTAssertEqual(item.kind, .task)
        XCTAssertEqual(item.recurrence, ".+1d")
        XCTAssertEqual(OrgCaptureTemplate.repeatingIntervals, [".+1d", ".+1w", ".+1m", "++1w", "++1m", "++1y"])
        for interval in OrgCaptureTemplate.repeatingIntervals {
            item.recurrence = interval
            item.properties["APPT_WARNTIME"] = "30"
            let source = OrgCaptureTemplate.repeatingReminder.source(for: item, createdAt: date)
            XCTAssertTrue(source.contains(" \(interval)>\n"))
            XCTAssertTrue(source.contains(":APPT_WARNTIME: 30\n"))
            XCTAssertFalse(source.contains(":STYLE: habit"))
        }
    }

    func testTemplateSwitchKeepsUserContentAndRemovesOldTemplateMetadata() {
        var original = OrgCaptureTemplate.calendarEvent.applyingDefaults(to: fixture(), date: date)
        original.tags = ["@work", "important"]
        original.properties["CUSTOM"] = "Keep this"
        let result = OrgCaptureTemplate.workProject.applyingDefaults(to: original, date: date)
        XCTAssertEqual(result.title, original.title)
        XCTAssertEqual(result.body, original.body)
        XCTAssertEqual(result.properties["CUSTOM"], "Keep this")
        XCTAssertNil(result.properties["APPT_WARNTIME"])
        XCTAssertNil(result.eventDate)
        XCTAssertEqual(result.tags, ["@work", "important", "project"])
    }

    func testUrgentProjectCapturePreservesSharedWorkflowKeywordAndProjectTag() {
        var item = OrgCaptureTemplate.workProject.applyingDefaults(to: fixture(), date: date)
        item.state = .urgent
        let source = OrgCaptureTemplate.workProject.source(for: item, createdAt: date, firstAction: "Check scope")
        XCTAssertEqual(item.source.file, "agenda/work.org")
        XCTAssertTrue(source.hasPrefix("* URGENT Test capture :project:\n"))
        XCTAssertTrue(source.hasSuffix("** NEXT Check scope\n"))
    }

    private var date: Date { Date(timeIntervalSince1970: 1_789_185_600) }

    private func fixture() -> OrgItem {
        OrgItem(
            id: UUID(), title: "Test capture", state: .todo, kind: .task,
            priority: .none, tags: [], scheduled: nil, deadline: nil,
            hasTime: false, durationMinutes: 30, recurrence: nil, body: "Context",
            source: SourceLocation(file: "inbox.org", startByte: 0, endByte: 0, startLine: 1),
            habitHistory: []
        )
    }
}

final class LocalizationBundleTests: XCTestCase {
    func testChineseResourcesAreBundledAndPreserveFormatArguments() throws {
        let appBundle = Bundle(for: WorkspaceStore.self)
        for (language, expectedFiles) in [("zh-Hans", "文件"), ("zh-Hant", "檔案")] {
            let url = try XCTUnwrap(appBundle.url(forResource: language, withExtension: "lproj"))
            let bundle = try XCTUnwrap(Bundle(url: url))
            XCTAssertEqual(bundle.localizedString(forKey: "Files", value: nil, table: nil), expectedFiles)
            XCTAssertEqual(bundle.localizedString(forKey: "Light", value: nil, table: nil), language == "zh-Hans" ? "浅色" : "淺色")
            let key = "No matches for “%@” in %@. Try searching all categories."
            let format = bundle.localizedString(forKey: key, value: nil, table: nil)
            let result = String(format: format, "my query", "my category")
            XCTAssertTrue(result.hasPrefix("在“my category”"))
            XCTAssertTrue(result.contains("“my query”"))
            XCTAssertFalse(result.contains("%@"))
        }
        XCTAssertEqual(OrgWorkflowState.todo.rawValue, "TODO")
        XCTAssertEqual(OrgPlanningKeyword.scheduled.sourceToken, "SCHEDULED:")
        XCTAssertEqual(OrgCaptureTemplate.nextAction.parentHeading, "Actions")
    }
}

@MainActor
final class OrgDraftRecoveryTests: XCTestCase {
    func testRecoveryPreservesEventWithoutAddingWorkflowAndItsOvernightDuration() throws {
        var item = fixture()
        item.hasWorkflowState = false
        item.kind = .event
        item.eventDate = date(day: 22, hour: 23, minute: 30)
        item.durationMinutes = 120
        item.recurrence = "++1w"
        item.priority = .high
        item.tags = ["work"]
        item.properties = ["APPT_WARNTIME": "20"]

        let source = OrgSourceView.source(for: item)
        let recovered = try heading(in: source)
        XCTAssertNil(recovered.state)
        XCTAssertEqual(recovered.title, item.title)
        XCTAssertEqual(recovered.priority, item.priority)
        XCTAssertEqual(recovered.tags, item.tags)
        XCTAssertEqual(recovered.eventDate, item.eventDate)
        XCTAssertEqual(recovered.durationMinutes, 120)
        XCTAssertEqual(recovered.recurrence, "++1w")
        XCTAssertEqual(recovered.properties, item.properties)
        XCTAssertEqual(recovered.body, item.body)
        XCTAssertTrue(source.contains("2026-09-23 Wed 01:30"))
    }

    func testRecoveryPreservesScheduledRangeClosedAndDeadline() throws {
        var item = fixture()
        item.state = .done
        item.scheduled = date(day: 22, hour: 10)
        item.deadline = date(day: 24, hour: 17)
        item.closed = date(day: 22, hour: 12, minute: 45)
        item.durationMinutes = 165
        item.recurrence = "+1w"

        let recovered = try heading(in: OrgSourceView.source(for: item))
        XCTAssertEqual(recovered.state, .done)
        XCTAssertEqual(recovered.scheduled, item.scheduled)
        XCTAssertEqual(recovered.deadline, item.deadline)
        XCTAssertEqual(recovered.closed, item.closed)
        XCTAssertEqual(recovered.durationMinutes, 165)
        XCTAssertEqual(recovered.recurrence, "+1w")
    }

    func testRecoveryPreservesDeadlineOnlyDurationAndAllDayEventRange() throws {
        var deadline = fixture()
        deadline.deadline = date(day: 22, hour: 23)
        deadline.durationMinutes = 90
        let recoveredDeadline = try heading(in: OrgSourceView.source(for: deadline))
        XCTAssertEqual(recoveredDeadline.deadline, deadline.deadline)
        XCTAssertEqual(recoveredDeadline.durationMinutes, 90)

        var event = fixture()
        event.hasWorkflowState = false
        event.hasTime = false
        event.eventDate = date(day: 22)
        event.durationMinutes = 2 * 24 * 60
        let recoveredEvent = try heading(in: OrgSourceView.source(for: event))
        XCTAssertFalse(recoveredEvent.hasTime)
        XCTAssertEqual(recoveredEvent.eventDate, event.eventDate)
        XCTAssertEqual(recoveredEvent.durationMinutes, event.durationMinutes)
    }

    func testRecoveryKeepsMultilineStatusNoteAsSafeComments() throws {
        var item = fixture()
        item.hasWorkflowState = false
        item.kind = .note
        item.tags = ["note"]
        let note = "Waiting for approval\n* TODO Keep this as note text\n#+title: Also note text\n\n中文理由"
        let source = OrgSourceView.source(for: item, stateNote: note)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "recovered.org", title: "Recovered", contents: source, kind: .org)
        ]).first)
        XCTAssertEqual(parsed.headings.count, 1)
        XCTAssertNil(parsed.headings.first?.state)
        for line in note.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            XCTAssertTrue(source.components(separatedBy: "\n").contains("# \(line)"))
        }
        XCTAssertEqual(parsed.headings.first?.body, item.body)
    }

    private func heading(in source: String) throws -> IndexedOrgHeading {
        try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "recovered.org", title: "Recovered", contents: source, kind: .org)
        ]).first?.headings.first)
    }

    private func date(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func fixture() -> OrgItem {
        OrgItem(id: UUID(), title: "Recover this draft", state: .todo, kind: .task, priority: .none,
                tags: [], scheduled: nil, deadline: nil, hasTime: true, durationMinutes: 30,
                recurrence: nil, body: "Unsaved notes 中文.",
                source: SourceLocation(file: "inbox.org", startByte: 0, endByte: 0, startLine: 1),
                habitHistory: [])
    }
}
