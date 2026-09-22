import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_788_048_000)

    func testDemoWaitingTaskAndProjectsSurviveReindexing() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        for reindex in [false, true] {
            if reindex { store.parseWorkspace() }
            let waiting = try XCTUnwrap(store.items.first { $0.title == "Renew library card" })
            XCTAssertEqual(waiting.state, .wait)
            let project = try XCTUnwrap(store.items.first { $0.title == "Write tree-sitter Org queries" })
            XCTAssertEqual(project.state, .todo)
            XCTAssertEqual(project.kind, .project)
            XCTAssertTrue(project.tags.contains("project"))
        }
        let personal = try XCTUnwrap(store.documents.first { $0.path == "personal.org" })
        let configured = WorkspaceStore(documents: [
            WorkspaceDocument(path: "agenda/personal.org", title: personal.title, contents: personal.contents, kind: .org)
        ])
        configured.usesEmacsConfiguration = true
        configured.parseWorkspace()
        XCTAssertEqual(configured.agendaGroups(for: .waiting).flatMap(\.items).map(\.title), ["Renew library card"])
    }

    func testChangingProjectToTaskPreservesEveryWorkflowState() throws {
        for state in OrgWorkflowState.allCases {
            let store = parsedStore("* \(state.rawValue) Work :project:\n")
            var item = try XCTUnwrap(store.items.first)
            item.kind = .task
            XCTAssertTrue(store.save(item))
            store.parseWorkspace()
            XCTAssertEqual(store.items.first?.kind, .task)
            XCTAssertEqual(store.items.first?.state, state)
            XCTAssertEqual(store.documents.first?.contents, "* \(state.rawValue) Work \n")
        }
    }

    func testFileGestureUndoRestoresImplicitDemoParent() async throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        let file = try XCTUnwrap(store.documents.first { $0.path == "notes/reading.org" })
        let moved = await store.moveFile(store.fileTransfer(file), to: "projects")
        XCTAssertTrue(moved)
        XCTAssertTrue(store.documents.contains { $0.path == "notes" && $0.kind == .folder })
        await store.undoFileAction()
        XCTAssertTrue(store.documents.contains { $0.path == file.path && $0.contents == file.contents })
        XCTAssertNil(store.fileActionError)
    }

    func testGestureReschedulePreservesDeadlineTimeRepeaterAndWarningAndCanUndo() throws {
        let source = "* TODO Task\nSCHEDULED: <2026-09-20 Sun 09:30-10:30 ++1w -2d> DEADLINE: <2026-10-01 Thu 17:00 -3d>\nBody 中文\n"
        let store = WorkspaceStore(documents: [WorkspaceDocument(path: "agenda/actions.org", title: "Tasks", contents: source, kind: .org)])
        store.parseWorkspace()
        store.usesEmacsConfiguration = true
        let item = try XCTUnwrap(store.items.first)
        let change = try XCTUnwrap(store.reschedule(item, to: item.scheduled!.adding(days: 2)))
        let updated = store.documents[0].contents
        XCTAssertTrue(updated.contains("SCHEDULED: <2026-09-22 Tue 09:30-10:30 ++1w -2d>"))
        XCTAssertTrue(updated.contains("DEADLINE: <2026-10-01 Thu 17:00 -3d>"))
        XCTAssertTrue(updated.contains("Rescheduled from"))
        XCTAssertTrue(store.undoGesture(change))
        XCTAssertEqual(store.documents[0].contents, source)
    }

    func testGestureUndoRestoresRepeatedCompletionAndRejectsNewerEdits() throws {
        let source = "* TODO Habit\nSCHEDULED: <2026-09-20 Sun +1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"
        let store = WorkspaceStore(documents: [WorkspaceDocument(path: "agenda/routines.org", title: "Habits", contents: source, kind: .org)])
        store.parseWorkspace()
        store.usesEmacsConfiguration = true
        let item = try XCTUnwrap(store.items.first)
        let change = try XCTUnwrap(store.gestureChange(for: item, label: "Done") { store.toggleDone(item) })
        XCTAssertNotEqual(store.documents[0].contents, source)
        XCTAssertTrue(store.undoGesture(change))
        XCTAssertEqual(store.documents[0].contents, source)
        XCTAssertEqual(store.items.first?.habitHistory, item.habitHistory)
        let again = try XCTUnwrap(store.gestureChange(for: item, label: "Done") { store.toggleDone(item) })
        let newer = store.documents[0].contents + "\n* New task\n"
        store.updateDocument(path: again.path, contents: newer)
        XCTAssertFalse(store.undoGesture(again))
        XCTAssertEqual(store.documents[0].contents, newer)
    }

    func testGestureRescheduleRejectsStaleTaskAndPlainEvents() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        store.parseWorkspace()
        let item = try XCTUnwrap(store.items.first(where: { $0.title == "Review quarterly roadmap" }))
        var edited = item
        edited.title = "Changed elsewhere"
        XCTAssertTrue(store.save(edited, original: item))
        let before = store.documents
        XCTAssertNil(store.reschedule(item, to: referenceDate.adding(days: 1)))
        XCTAssertNotNil(store.operationError)
        XCTAssertEqual(store.documents, before)
        let event = try XCTUnwrap(store.items.first(where: { $0.kind == .event }))
        XCTAssertNil(store.reschedule(event, to: referenceDate))
        XCTAssertEqual(store.documents, before)
    }

    func testGestureSchedulingUnscheduledTaskRetainsDeadline() throws {
        let source = "* TODO Task\nDEADLINE: <2026-10-01 Thu>\n"
        let store = WorkspaceStore(documents: [WorkspaceDocument(path: "tasks.org", title: "Tasks", contents: source, kind: .org)])
        store.parseWorkspace()
        let item = try XCTUnwrap(store.items.first)
        XCTAssertNotNil(store.reschedule(item, to: item.deadline!.adding(days: -2)))
        XCTAssertTrue(store.documents[0].contents.contains("DEADLINE: <2026-10-01 Thu>"))
        XCTAssertTrue(store.documents[0].contents.contains("SCHEDULED: <2026-09-29 Tue>"))
    }

    func testGestureDropDoesNotRecreateDeletedTask() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        store.parseWorkspace()
        let task = try XCTUnwrap(store.items.first(where: { $0.title == "Review quarterly roadmap" }))
        store.updateDocument(path: task.source.file, contents: "* TODO Replacement\n")
        store.parseWorkspace()
        let before = store.documents
        XCTAssertNil(store.reschedule(task, to: referenceDate))
        XCTAssertNotNil(store.operationError)
        XCTAssertEqual(store.documents, before)
    }

    func testGestureUndoChecksExactUnicodeBytes() throws {
        let source = "* TODO Café\n"
        let store = WorkspaceStore(documents: [WorkspaceDocument(path: "tasks.org", title: "Tasks", contents: source, kind: .org)])
        store.parseWorkspace()
        let task = try XCTUnwrap(store.items.first)
        let change = try XCTUnwrap(store.gestureChange(for: task, label: "Done") { store.toggleDone(task) })
        let changedBytes = store.documents[0].contents.replacingOccurrences(of: "é", with: "e\u{301}")
        store.documents[0].contents = changedBytes
        XCTAssertFalse(store.undoGesture(change))
        XCTAssertTrue(store.documents[0].contents.utf8.elementsEqual(changedBytes.utf8))
    }

    func testFolderRowsDoNotDuplicateFilesInsideExplicitSubfolders() {
        let documents = [
            WorkspaceDocument(path: "projects/design", title: "Design", contents: "", kind: .folder),
            WorkspaceDocument(path: "projects/design/brief.org", title: "Brief", contents: "", kind: .org),
            WorkspaceDocument(path: "projects/loose/notes.org", title: "Notes", contents: "", kind: .org),
            WorkspaceDocument(path: "personal.org", title: "Personal", contents: "", kind: .org)
        ]
        XCTAssertEqual(
            visibleFolderDocuments(documents, folderPath: "projects").map(\.path),
            ["projects/design", "projects/loose/notes.org"]
        )
        XCTAssertEqual(
            visibleFolderDocuments(documents, folderPath: "projects/design").map(\.path),
            ["projects/design/brief.org"]
        )
    }

    func testPreviewSeparatesAgendaAndUnscheduledTodos() {
        let store = WorkspaceStore.preview(now: referenceDate)

        XCTAssertFalse(store.datedItems.isEmpty)
        XCTAssertEqual(store.openTodos.map(\.title), ["Plan iPad reading workflow"])
        XCTAssertTrue(store.datedItems.allSatisfy { $0.agendaDate != nil })
    }

    func testTogglingTaskWritesTerminalState() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        let task = try XCTUnwrap(store.items.first(where: { $0.state == .todo }))

        store.toggleDone(task)

        XCTAssertEqual(store.items.first(where: { $0.id == task.id })?.state, .done)
    }

    func testSearchPreservesSourceLocation() throws {
        let store = WorkspaceStore.preview(now: referenceDate)

        let result = try XCTUnwrap(store.search("tree-sitter", scope: .all).first)
        guard case .item(let item) = result else {
            return XCTFail("Expected a task search result")
        }
        XCTAssertEqual(item.source.file, "inbox.org")
        XCTAssertGreaterThan(item.source.startLine, 0)
    }

    func testSettingsSearchOnlyReturnsExistingDestinations() {
        let store = WorkspaceStore()
        for destination in SettingsDestination.allCases {
            let results = store.search(destination.title, scope: .settings)
            XCTAssertTrue(results.contains(.setting(destination)))
            XCTAssertTrue(results.allSatisfy {
                if case .setting = $0 { return true }
                return false
            })
        }
        for unsupportedSetting in ["workflow", "capture", "language", "fonts"] {
            XCTAssertTrue(store.search(unsupportedSetting, scope: .settings).isEmpty)
        }
        XCTAssertEqual(store.search(SettingsDestination.reminders.subtitle, scope: .settings), [.setting(.reminders)])
        XCTAssertEqual(store.search(SettingsDestination.appearance.subtitle, scope: .settings), [.setting(.appearance)])
    }

    func testDisconnectedDocumentDoesNotReportSavedOrSessionOnly() {
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "", kind: .org)
        ])
        XCTAssertEqual(store.saveStatus(for: "inbox.org"), .unavailable)
    }

    func testOrgHeadingRoundTripsVisibleMetadata() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        let task = try XCTUnwrap(store.items.first(where: { $0.title == "Review quarterly roadmap" }))

        XCTAssertTrue(task.orgHeading.hasPrefix("* TODO [#A]"))
        XCTAssertTrue(task.orgHeading.hasSuffix(":work:focus:"))
    }

    func testClosedPlanningTimestampClearsAStaleAgendaDateWhenReindexed() throws {
        let staleDate = Date(timeIntervalSince1970: 1_788_048_000)
        let item = OrgItem(
            id: UUID(),
            title: "Archived event",
            state: .done,
            kind: .event,
            priority: .none,
            tags: [],
            scheduled: staleDate,
            deadline: nil,
            hasTime: false,
            durationMinutes: 0,
            recurrence: nil,
            body: "",
            source: SourceLocation(file: "closed.org", startByte: 0, endByte: 48, startLine: 1),
            habitHistory: []
        )
        let document = WorkspaceDocument(
            path: "closed.org",
            title: "Closed",
            contents: "* DONE Archived event\nCLOSED: [2026-08-31 Mon]\n",
            kind: .org
        )
        let store = WorkspaceStore(
            items: [item],
            documents: [document],
            selectedDate: staleDate
        )

        store.parseWorkspace()

        let refreshed = try XCTUnwrap(store.items.first)
        XCTAssertNil(refreshed.scheduled)
        XCTAssertNil(refreshed.deadline)
        XCTAssertNotNil(refreshed.closed)
        XCTAssertNil(refreshed.agendaDate)
    }

    func testTreeSitterIndexesWorkspaceAndDrivesTaskMetadata() throws {
        let store = WorkspaceStore.preview(now: referenceDate)

        store.parseWorkspace()

        XCTAssertTrue(store.parserStatus.hasPrefix("Ready"))
        XCTAssertGreaterThanOrEqual(store.parsedDocuments.count, 5)
        let inbox = try XCTUnwrap(store.parsedDocuments["inbox.org"])
        XCTAssertFalse(inbox.hasError)
        XCTAssertTrue(inbox.root.children.contains(where: { $0.type == "heading" }))
        let project = try XCTUnwrap(store.items.first(where: { $0.title == "Write tree-sitter Org queries" }))
        XCTAssertEqual(project.state, .todo)
        XCTAssertEqual(project.priority, .medium)
        XCTAssertEqual(project.source.file, "inbox.org")
    }

    func testExactSourceReplacementPreservesUnknownDocumentContent() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        store.parseWorkspace()
        let parsed = try XCTUnwrap(store.parsedDocuments["inbox.org"])
        let todo = try XCTUnwrap(firstNode(ofType: "todo_keyword", in: parsed.root))
        let original = try XCTUnwrap(store.documents.first(where: { $0.path == "inbox.org" })?.contents)

        XCTAssertTrue(
            store.applySourceReplacement(
                path: "inbox.org",
                startByte: todo.startByte,
                endByte: todo.endByte,
                expectedText: todo.text,
                replacement: "NEXT" + trailingWhitespace(in: todo.text)
            )
        )

        let updated = try XCTUnwrap(store.documents.first(where: { $0.path == "inbox.org" })?.contents)
        XCTAssertTrue(updated.contains("#+startup: overview"))
        XCTAssertTrue(updated.contains("* NEXT [#A] Review quarterly roadmap"))
        XCTAssertEqual(updated.utf8.count, original.utf8.count)

        let beforeRejectedMutation = updated
        XCTAssertFalse(
            store.applySourceReplacement(
                path: "inbox.org",
                startByte: todo.startByte,
                endByte: todo.endByte,
                expectedText: todo.text,
                replacement: "DONE "
            )
        )
        XCTAssertEqual(
            store.documents.first(where: { $0.path == "inbox.org" })?.contents,
            beforeRejectedMutation
        )
    }

    func testRapidMutationsInTwoFilesBothRefreshTheirParsedDocuments() async throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        store.parseWorkspace()
        let inboxTree = try XCTUnwrap(store.parsedDocuments["inbox.org"]?.root)
        let notesTree = try XCTUnwrap(store.parsedDocuments["notes/reading.org"]?.root)
        let todo = try XCTUnwrap(firstNode(ofType: "todo_keyword", in: inboxTree))
        let checkbox = try XCTUnwrap(
            allNodes(ofType: "checkbox", in: notesTree).first(where: {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "[ ]"
            })
        )

        XCTAssertTrue(
            store.applySourceReplacement(
                path: "inbox.org",
                startByte: todo.startByte,
                endByte: todo.endByte,
                expectedText: todo.text,
                replacement: "NEXT" + trailingWhitespace(in: todo.text)
            )
        )
        XCTAssertTrue(
            store.applySourceReplacement(
                path: "notes/reading.org",
                startByte: checkbox.startByte,
                endByte: checkbox.endByte,
                expectedText: checkbox.text,
                replacement: "[X]" + trailingWhitespace(in: checkbox.text)
            )
        )

        for _ in 0..<30 {
            let todoText = store.parsedDocuments["inbox.org"]
                .flatMap { firstNode(ofType: "todo_keyword", in: $0.root)?.text }
            let checkedExists = store.parsedDocuments["notes/reading.org"]
                .map { allNodes(ofType: "checkbox", in: $0.root) }
                .map { nodes in
                    nodes.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "[X]" }
                } ?? false
            if todoText?.trimmingCharacters(in: .whitespacesAndNewlines) == "NEXT", checkedExists {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(
            firstNode(ofType: "todo_keyword", in: try XCTUnwrap(store.parsedDocuments["inbox.org"]?.root))?
                .text.trimmingCharacters(in: .whitespacesAndNewlines),
            "NEXT"
        )
        XCTAssertTrue(
            allNodes(ofType: "checkbox", in: try XCTUnwrap(store.parsedDocuments["notes/reading.org"]?.root))
                .contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "[X]" }
        )
    }

    func testSavingNonInboxItemPreservesOtherFilesMetadataAndChildHeadings() throws {
        let source = """
        #+title: 原始🙂
        * WAIT [#A] Parent :work:
        SCHEDULED: <2026-08-31 Mon 09:30 ++1w -2d> DEADLINE: <2026-09-04 Fri>
        :PROPERTIES:
        :CUSTOM: 保留🙂
        :END:
        #+begin_src swift
        print("untouched")
        #+end_src
        Original notes.
        ** TODO Child
        Child notes.
        * TODO Sibling
        """
        let store = parsedStore(source, path: "projects/work.org")
        let inbox = WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "#+CUSTOM: keep\n", kind: .org)
        store.documents.append(inbox)
        var parent = try XCTUnwrap(store.items.first { $0.title == "Parent" })
        let id = parent.id
        parent.title = "Edited parent 🧪"
        parent.body = "Updated notes."

        XCTAssertTrue(store.save(parent))
        let updated = try XCTUnwrap(store.documents.first { $0.path == "projects/work.org" }?.contents)
        XCTAssertTrue(updated.contains("#+title: 原始🙂"))
        XCTAssertTrue(updated.contains("* WAIT [#A] Edited parent 🧪 :work:"))
        XCTAssertTrue(updated.contains("SCHEDULED: <2026-08-31 Mon 09:30 ++1w -2d> DEADLINE: <2026-09-04 Fri>"))
        XCTAssertTrue(updated.contains(":PROPERTIES:\n:CUSTOM: 保留🙂\n:END:"))
        XCTAssertTrue(updated.contains("#+begin_src swift\nprint(\"untouched\")\n#+end_src"))
        XCTAssertTrue(updated.hasSuffix("** TODO Child\nChild notes.\n* TODO Sibling"))
        XCTAssertEqual(store.documents.first { $0.path == "inbox.org" }, inbox)

        store.parseWorkspace()
        let reparsed = try XCTUnwrap(store.items.first { $0.id == id })
        XCTAssertEqual(reparsed.title, "Edited parent 🧪")
        XCTAssertEqual(reparsed.body, "Updated notes.")
        XCTAssertEqual(reparsed.recurrence, "++1w")
        XCTAssertNotNil(reparsed.deadline)
    }

    func testTogglingLongWorkflowTokenPreservesSourceAndAllowsImmediateSecondEdit() throws {
        let source = "#+CUSTOM: 保留🙂\n* SOMEDAY First\nDEADLINE: <2026-09-04 Fri>\n* TODO Second\n"
        let store = parsedStore(source, path: "personal.org")
        let first = try XCTUnwrap(store.items.first { $0.title == "First" })
        let second = try XCTUnwrap(store.items.first { $0.title == "Second" })

        store.toggleDone(first)
        store.toggleDone(second)
        XCTAssertEqual(store.documents.first?.contents, source
            .replacingOccurrences(of: "SOMEDAY", with: "DONE")
            .replacingOccurrences(of: "TODO", with: "DONE"))

        store.parseWorkspace()
        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(store.items.allSatisfy { $0.state == .done })
        XCTAssertNotNil(store.items.first { $0.id == first.id }?.deadline)
    }

    func testEditingScheduleAndRepeaterPreservesWarningAndDeadline() throws {
        let store = parsedStore("* TODO Walk :habit:\nSCHEDULED:\t<2026-08-31 Mon 09:30 ++1w -2d> DEADLINE: <2026-09-04 Fri>\n")
        var item = try XCTUnwrap(store.items.first)
        item.scheduled = try XCTUnwrap(Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: try XCTUnwrap(item.scheduled)))
        item.recurrence = "+1d"
        XCTAssertTrue(store.save(item))
        XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).contains(
            "SCHEDULED:\t<2026-09-01 Tue 09:30 +1d -2d> DEADLINE: <2026-09-04 Fri>"
        ))
        store.parseWorkspace()
        XCTAssertEqual(store.items.first?.recurrence, "+1d")
        XCTAssertEqual(store.items.first?.scheduled, item.scheduled)
    }

    func testRemovingNotesAndSchedulePersistsWithoutRemovingOpaqueBlocks() throws {
        let store = parsedStore("* TODO Walk\nSCHEDULED: <2026-08-31 Mon> DEADLINE: <2026-09-04 Fri>\n:PROPERTIES:\n:CUSTOM: keep\n:END:\nNotes to clear.\n")
        var item = try XCTUnwrap(store.items.first)
        item.scheduled = nil
        item.body = ""
        XCTAssertTrue(store.save(item))
        store.parseWorkspace()
        XCTAssertNil(store.items.first?.scheduled)
        XCTAssertNotNil(store.items.first?.deadline)
        XCTAssertEqual(store.items.first?.body, "")
        XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).contains(":CUSTOM: keep"))
    }

    func testNewEntryAppendsWithoutReserializingExistingContent() throws {
        let source = "#+CUSTOM: preserve\n* TODO Existing\nDEADLINE: <2026-09-04 Fri>\n"
        let store = parsedStore(source)
        var item = try XCTUnwrap(store.items.first)
        item.id = UUID()
        item.title = "New all-day habit"
        item.kind = .habit
        item.scheduled = referenceDate.startOfDay
        item.hasTime = false
        item.recurrence = "+1d"
        XCTAssertTrue(store.save(item))
        XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).hasPrefix(source))
        store.parseWorkspace()
        let saved = try XCTUnwrap(store.items.first { $0.id == item.id })
        XCTAssertEqual(saved.kind, .habit)
        XCTAssertFalse(saved.hasTime)
        XCTAssertEqual(saved.recurrence, "+1d")
        XCTAssertNotNil(saved.deadline)
    }

    func testSaveRejectsAnUnresolvableHeadingWithoutOverwritingSourceOrDraft() throws {
        let store = parsedStore("* TODO Original\n")
        var draft = try XCTUnwrap(store.items.first)
        draft.title = "My draft"
        store.updateDocument(path: "inbox.org", contents: "* TODO Replaced externally\n")

        XCTAssertFalse(store.save(draft))
        XCTAssertEqual(store.documents.first?.contents, "* TODO Replaced externally\n")
        XCTAssertEqual(store.items.first?.title, "Original")
        XCTAssertEqual(draft.title, "My draft")
    }

    func testTaskSearchIncludesOnlyTasksProjectsAndHabits() throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        let base = try XCTUnwrap(store.items.first)
        store.items = OrgItemKind.allCases.map { kind in
            var item = base
            item.id = UUID()
            item.title = "Match \(kind.rawValue)"
            item.kind = kind
            return item
        }
        let kinds = store.search("Match", scope: .tasks).compactMap { result -> OrgItemKind? in
            if case .item(let item) = result { return item.kind }
            return nil
        }
        XCTAssertEqual(Set(kinds), Set([.task, .project, .habit]))
        XCTAssertEqual(store.search("Match", scope: .all).count, OrgItemKind.allCases.count)
    }

    func testChangingEventsAndProjectsToTasksRoundTrips() throws {
        for source in [
            "* Meeting :event:\nSCHEDULED: <2026-08-31 Mon 09:30>\n",
            "* TODO Meeting :project:\n"
        ] {
            let store = parsedStore(source)
            var item = try XCTUnwrap(store.items.first)
            item.kind = .task
            XCTAssertTrue(store.save(item))
            store.parseWorkspace()
            XCTAssertEqual(store.items.first?.kind, .task)
            XCTAssertEqual(store.items.first?.state, .todo)
            XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).contains("* TODO Meeting"))
        }
    }

    func testStaleEditorBaselineRejectsNewerSourceNotesBeforeAndAfterReindex() throws {
        for reindex in [false, true] {
            let store = parsedStore("* TODO Original\nOriginal notes.\n")
            let baseline = try XCTUnwrap(store.items.first)
            var draft = baseline
            draft.title = "Edited title"
            store.updateDocument(path: "inbox.org", contents: "* TODO Original\nNewer source notes.\n")
            if reindex { store.parseWorkspace() }

            XCTAssertFalse(store.save(draft, original: baseline))
            XCTAssertEqual(store.documents.first?.contents, "* TODO Original\nNewer source notes.\n")
            XCTAssertEqual(draft.body, "Original notes.")
        }
    }

    func testInsertingHeadingRetainsExistingItemIdentityAndAllowsSafeDraftSave() throws {
        let store = parsedStore("* TODO A\n* TODO B\n")
        let originalA = try XCTUnwrap(store.items.first { $0.title == "A" })
        let originalB = try XCTUnwrap(store.items.first { $0.title == "B" })
        store.updateDocument(path: "inbox.org", contents: "* TODO X\n* TODO A\n* TODO B\n")
        store.parseWorkspace()
        XCTAssertEqual(store.items.first { $0.title == "A" }?.id, originalA.id)
        XCTAssertEqual(store.items.first { $0.title == "B" }?.id, originalB.id)
        XCTAssertNotEqual(store.items.first { $0.title == "X" }?.id, originalA.id)

        var draft = originalB
        draft.title = "Edited B"
        XCTAssertTrue(store.save(draft, original: originalB))
        XCTAssertEqual(store.documents.first?.contents, "* TODO X\n* TODO A\n* TODO Edited B\n")
    }

    func testUnscheduledNoteSurvivesFreshIndex() throws {
        let store = parsedStore("* TODO Seed\n")
        var note = try XCTUnwrap(store.items.first)
        note.id = UUID()
        note.title = "Saved note"
        note.kind = .note
        XCTAssertTrue(store.save(note))

        let reopened = WorkspaceStore(documents: store.documents)
        reopened.parseWorkspace()
        XCTAssertEqual(reopened.items.first { $0.title == "Saved note" }?.kind, .note)
    }

    func testDeadlineTimeAndGlobalTimeTogglePersistAcrossBothPlanningEntries() throws {
        let store = parsedStore("* TODO Meeting\nSCHEDULED: <2026-08-31 Mon 09:30>\nDEADLINE: <2026-09-04 Fri>\n")
        var item = try XCTUnwrap(store.items.first)
        item.deadline = try XCTUnwrap(Calendar.autoupdatingCurrent.date(
            bySettingHour: 14, minute: 45, second: 0, of: try XCTUnwrap(item.deadline)
        ))
        XCTAssertTrue(store.save(item))
        XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).contains("DEADLINE: <2026-09-04 Fri 14:45>"))
        store.parseWorkspace()
        item = try XCTUnwrap(store.items.first)
        item.hasTime = false
        XCTAssertTrue(store.save(item))
        XCTAssertEqual(store.documents.first?.contents,
            "* TODO Meeting\nSCHEDULED: <2026-08-31 Mon>\nDEADLINE: <2026-09-04 Fri>\n")
    }

    func testMultilineTitleIsStoredAsOneHeading() throws {
        let store = parsedStore("* TODO Original\n* TODO Sibling\n")
        var draft = try XCTUnwrap(store.items.first { $0.title == "Original" })
        draft.title = "  First line\nsecond\tline  "
        XCTAssertTrue(store.save(draft))
        store.parseWorkspace()
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first { $0.id == draft.id }?.title, "First line second line")
        XCTAssertEqual(store.documents.first?.contents, "* TODO First line second line\n* TODO Sibling\n")
    }

    private func parsedStore(_ contents: String, path: String = "inbox.org") -> WorkspaceStore {
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: path, title: path, contents: contents, kind: .org)
        ], selectedDate: referenceDate)
        store.parseWorkspace()
        return store
    }

    private func trailingWhitespace(in token: String) -> String {
        String(token.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
    }

    private func firstNode(ofType type: String, in node: ParsedOrgNode) -> ParsedOrgNode? {
        if node.type == type { return node }
        return node.children.lazy.compactMap { self.firstNode(ofType: type, in: $0) }.first
    }

    private func allNodes(ofType type: String, in node: ParsedOrgNode) -> [ParsedOrgNode] {
        (node.type == type ? [node] : []) + node.children.flatMap { self.allNodes(ofType: type, in: $0) }
    }
}
