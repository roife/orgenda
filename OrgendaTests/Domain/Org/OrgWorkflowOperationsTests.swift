import XCTest
@testable import Orgenda

final class OrgWorkflowOperationsTests: XCTestCase {
    func testStateReasonIsRequiredOnlyForConfiguredEntryFlags() throws {
        for state in [OrgWorkflowState.wait, .canceled] {
            XCTAssertTrue(OrgWorkflowOperations.requiresNote(from: .todo, to: state))
            XCTAssertFalse(OrgWorkflowOperations.requiresNote(from: state, to: state))
        }
        let old = item(state: .todo)
        XCTAssertThrowsError(try OrgWorkflowOperations.applyingLogs(
            to: "* WAIT Example\n", headingStartByte: 0, replacing: old, with: item(state: .wait), note: "  \n"
        )) { XCTAssertEqual($0 as? OrgWorkflowOperations.Failure, .noteRequired) }
    }

    func testOpenStatesFollowConfiguredLoggingWithoutClosingTimestamp() throws {
        for state in [OrgWorkflowState.todo, .next, .someday] {
            XCTAssertFalse(OrgWorkflowOperations.requiresNote(from: .todo, to: state))
            let source = "* \(state.rawValue) Example\nBody.\n"
            XCTAssertEqual(try OrgWorkflowOperations.applyingLogs(
                to: source, headingStartByte: 0, replacing: item(state: .todo), with: item(state: state), now: now
            ), source)
            XCTAssertNil(OrgWorkflowOperations.normalized(item(state: state), replacing: item(state: .todo), now: now).closed)
        }
        let source = "* URGENT Example\n"
        let logged = try OrgWorkflowOperations.applyingLogs(
            to: source, headingStartByte: 0, replacing: item(state: .todo), with: item(state: .urgent), now: now
        )
        XCTAssertTrue(logged.contains("- State \"URGENT\" from \"TODO\" \(stamp)"))
    }

    func testNewLogbookPreservesPropertiesRawBlockAndChildren() throws {
        let source = "* WAIT Example :@work:\nSCHEDULED: <2026-09-12 Sat>\n:PROPERTIES:\n:ID: abc\n:CREATED: [2026-09-01 Tue]\n:END:\nBody.\n#+begin_src text\n* literal\n:LOGBOOK:\n#+end_src\n** Child\nChild body.\n"
        let result = try OrgWorkflowOperations.applyingLogs(
            to: source, headingStartByte: 0, replacing: item(state: .todo), with: item(state: .wait),
            note: "Waiting for reply\n:END:\n* literal note", now: now
        )
        let insertion = ":LOGBOOK:\n- State \"WAIT\" from \"TODO\" \(stamp) \\\\\n  Waiting for reply\n  ,:END:\n  * literal note\n:END:\n"
        XCTAssertEqual(result, source.replacingOccurrences(of: ":END:\nBody.", with: ":END:\n" + insertion + "Body."))
        XCTAssertNoThrow(try OrgWorkflowOperations.applyingLogs(
            to: result, headingStartByte: 0, replacing: item(state: .wait), with: item(state: .done), now: now
        ))
    }

    func testExistingLogbookPrependsWithoutReplacingClocksOrOtherDrawers() throws {
        let source = "* DONE Example\r\n:PROPERTIES:\r\n:ID: a\r\n:END:\r\n:LOGBOOK:\r\nCLOCK: [2026-09-12 Sat 10:00]--[2026-09-12 Sat 10:10] =>  0:10\r\n- old history\r\n:END:\r\n:RESULTS:\r\n1\r\n:END:\r\n"
        let result = try OrgWorkflowOperations.applyingLogs(
            to: source, headingStartByte: 0, replacing: item(state: .todo), with: item(state: .done), now: now
        )
        XCTAssertEqual(result, source.replacingOccurrences(of: ":LOGBOOK:\r\n", with: ":LOGBOOK:\r\n- State \"DONE\" from \"TODO\" \(stamp)\r\n"))
    }

    func testOnlyWaitExitLogsWhenMovingToNext() throws {
        for old in OrgWorkflowState.allCases {
            let source = "* NEXT Example\nBody.\n"
            let result = try OrgWorkflowOperations.applyingLogs(
                to: source, headingStartByte: 0, replacing: item(state: old), with: item(state: .next), now: now
            )
            XCTAssertEqual(result != source, old == .wait)
        }
    }

    func testConfiguredCompletionAndReopenNormalizeClosedTimestamp() {
        for state in [OrgWorkflowState.done, .canceled] {
            let closed = OrgWorkflowOperations.normalized(item(state: state), replacing: item(state: .todo), now: now)
            XCTAssertEqual(closed.closed, now)
            let reopened = OrgWorkflowOperations.normalized(item(state: .todo), replacing: closed, now: now)
            XCTAssertNil(reopened.closed)
        }
    }

    func testReschedulingUsesExactOldInactiveTimestampAndPreservesRepeater() throws {
        let source = "* TODO Example\nSCHEDULED: <2026-09-12 Sat 10:00 ++1w -2d> DEADLINE: <2026-09-15 Tue>\nBody\n"
        var old = item(state: .todo)
        old.scheduled = now
        old.deadline = now.addingTimeInterval(3 * 86400)
        old.hasTime = true
        var changed = old
        changed.scheduled = now.addingTimeInterval(86400)
        changed.deadline = nil
        let result = try OrgWorkflowOperations.applyingLogs(
            to: source, headingStartByte: 0, replacing: old, with: changed, now: now, originalSource: source
        )
        XCTAssertTrue(result.contains("- Rescheduled from \"[2026-09-12 Sat 10:00 ++1w -2d]\" on \(stamp)"))
        XCTAssertTrue(result.contains("- Removed deadline, was \"[2026-09-15 Tue]\" on \(stamp)"))
        XCTAssertTrue(result.contains("SCHEDULED: <2026-09-12 Sat 10:00 ++1w -2d> DEADLINE: <2026-09-15 Tue>"))
    }

    func testInitialPlanningDoesNotCreateHistory() throws {
        let old = item(state: .todo)
        var changed = old
        changed.scheduled = now
        changed.deadline = now
        let source = "* TODO Example\n"
        XCTAssertEqual(try OrgWorkflowOperations.applyingLogs(
            to: source, headingStartByte: 0, replacing: old, with: changed
        ), source)
    }

    func testAmbiguousOrUnclosedDrawerDoesNotWrite() throws {
        for suffix in [":LOGBOOK:\nunfinished\n", ":LOGBOOK:\n:END:\n:LOGBOOK:\n:END:\n"] {
            XCTAssertThrowsError(try OrgWorkflowOperations.applyingLogs(
                to: "* DONE Example\n" + suffix, headingStartByte: 0,
                replacing: item(state: .todo), with: item(state: .done)
            )) { XCTAssertEqual($0 as? OrgWorkflowOperations.Failure, .ambiguousStructure) }
        }
    }

    func testEverySourceUsesSiblingYearlyArchiveNamedAfterItsBasename() throws {
        for (path, expected) in [("agenda/inbox.org", "agenda/archives/inbox-2026.org"),
                                 ("agenda/actions.org", "agenda/archives/actions-2026.org"),
                                 ("agenda/work.org", "agenda/archives/work-2026.org"),
                                 ("agenda/personal.org", "agenda/archives/personal-2026.org"),
                                 ("notes.org", "archives/notes-2026.org")] {
            let location = try OrgWorkflowOperations.archiveDestination(sourcePath: path, source: "* DONE Work\n", headingStartByte: 0, now: now)
            XCTAssertEqual(location.path, expected)
            XCTAssertEqual(location.outline, "* Archived")
        }
    }

    func testInheritedArchivePropertyAndOwnOverride() throws {
        let source = "* Parent\n:PROPERTIES:\n:ARCHIVE: archives/family.org::* Family\n:END:\n** DONE Child\n:PROPERTIES:\n:ID: untouched\n:END:\n*** DONE Grandchild\n:PROPERTIES:\n:ARCHIVE: ../custom.org::* My archive\n:END:\n"
        let childStart = byteOffset(of: "** DONE Child", in: source)
        let grandchildStart = byteOffset(of: "*** DONE Grandchild", in: source)
        XCTAssertEqual(try OrgWorkflowOperations.archiveDestination(
            sourcePath: "agenda/work.org", source: source, headingStartByte: childStart, now: now
        ), OrgArchiveDestination(path: "agenda/archives/family.org", outline: "* Family"))
        XCTAssertEqual(try OrgWorkflowOperations.archiveDestination(
            sourcePath: "agenda/work.org", source: source, headingStartByte: grandchildStart, now: now
        ), OrgArchiveDestination(path: "custom.org", outline: "* My archive"))
    }

    func testArchiveRefusesPathsOutsideWorkspace() {
        for location in ["../../escape.org::* Archived", "/tmp/escape.org::* Archived", "~/escape.org::* Archived", "remote:file.org::* Archived"] {
            let source = "* DONE Work\n:PROPERTIES:\n:ARCHIVE: \(location)\n:END:\n"
            XCTAssertThrowsError(try OrgWorkflowOperations.archiveDestination(sourcePath: "agenda/inbox.org", source: source, headingStartByte: 0, now: now))
        }
    }

    func testFileArchivePropertyIsInheritedWithoutReadingLiteralBlockProperties() throws {
        let source = "#+PROPERTY: ARCHIVE archive/all.org::* Old work\n#+begin_example\n#+PROPERTY: ARCHIVE ../../escape.org::* Escape\n#+end_example\n* DONE Work\n"
        XCTAssertEqual(try OrgWorkflowOperations.archiveDestination(
            sourcePath: "agenda/inbox.org", source: source,
            headingStartByte: byteOffset(of: "* DONE", in: source), now: now
        ), OrgArchiveDestination(path: "agenda/archive/all.org", outline: "* Old work"))
    }

    func testArchiveCreatesHeadingAndPreservesSubtreeBytesExceptLevels() throws {
        let subtree = "* DONE 中文🙂\n:PROPERTIES:\n:ID: stable\n:END:\n#+begin_example\n* do not indent\n#+end_example\n#+BEGIN: generated\n* literal dynamic output\n#+END:\n** Child\nBody\n"
        let source = document("agenda/inbox.org", "#+TITLE: Inbox\n" + subtree + "* TODO Keep\nKeep body\n")
        let destination = document("agenda/archives/inbox-2026.org", "#+TITLE: Archive\n")
        let plan = try OrgWorkflowOperations.archive(source: source, headingStartByte: byteOffset(of: "* DONE", in: source.contents), destination: destination, now: now)
        XCTAssertEqual(plan.source.contents, "#+TITLE: Inbox\n* TODO Keep\nKeep body\n")
        XCTAssertEqual(plan.destination.contents, "#+TITLE: Archive\n* Archived\n" + subtree
            .replacingOccurrences(of: "* DONE 中文🙂", with: "** DONE 中文🙂")
            .replacingOccurrences(of: "** Child", with: "*** Child"))
    }

    func testRefileTargetsUseOnlyConfiguredFilesAndFirstThreeLevels() throws {
        let source = "* First\n** Second\n*** Third\n**** Fourth\n#+begin_src text\n* Literal\n#+end_src\n"
        let targets = OrgWorkflowOperations.refileTargets(in: [document("agenda/actions.org", source), document("notes/actions.org", source)])
        XCTAssertEqual(targets.map(\.level), [1, 2, 3])
        XCTAssertEqual(targets.map(\.outline), ["First", "First/Second", "First/Second/Third"])
    }

    func testRefileTargetsUseWorkAndPersonalAndExcludeFormerProjectFilenames() {
        let configured = ["agenda/actions.org", "agenda/work.org", "agenda/personal.org", "agenda/routines.org", "agenda/someday.org"]
        let oldPaths = ["agenda/projects-work.org", "agenda/projects-personal.org"]
        let targets = OrgWorkflowOperations.refileTargets(in: (configured + oldPaths).map { document($0, "* Destination\n") })
        XCTAssertEqual(targets.map(\.path), configured.sorted())
    }

    func testSameFileRefileCombinesRemovalAndInsertionWithoutDroppingNeighbors() throws {
        let source = document("agenda/actions.org", "* Inbox\n** TODO Move\nBody\n*** Child\nChild body\n* Destination\nExisting\n* Neighbor\nUntouched\n")
        let target = try XCTUnwrap(OrgWorkflowOperations.refileTargets(in: [source]).first(where: { $0.title == "Destination" }))
        let plan = try OrgWorkflowOperations.refile(source: source, headingStartByte: byteOffset(of: "** TODO Move", in: source.contents), destination: source, target: target)
        XCTAssertEqual(plan.source, plan.destination)
        XCTAssertEqual(plan.source.contents, "* Inbox\n* Destination\nExisting\n** TODO Move\nBody\n*** Child\nChild body\n* Neighbor\nUntouched\n")
    }

    func testSameFileRefileToEarlierHeadingWorks() throws {
        let source = document("agenda/actions.org", "* Destination\nExisting\n* Middle\nKeep\n* TODO Move\nBody\n")
        let target = try XCTUnwrap(OrgWorkflowOperations.refileTargets(in: [source]).first)
        let plan = try OrgWorkflowOperations.refile(source: source, headingStartByte: byteOffset(of: "* TODO Move", in: source.contents), destination: source, target: target)
        XCTAssertEqual(plan.source.contents, "* Destination\nExisting\n** TODO Move\nBody\n* Middle\nKeep\n")
    }

    func testSameFileRefileDirectlyAdjacentSubtreeUsesOneFinalSnapshot() throws {
        let source = document("agenda/actions.org", "* Destination\nExisting\n* TODO Move\nBody\n")
        let target = try XCTUnwrap(OrgWorkflowOperations.refileTargets(in: [source]).first)
        let plan = try OrgWorkflowOperations.refile(source: source, headingStartByte: byteOffset(of: "* TODO Move", in: source.contents), destination: source, target: target)
        XCTAssertEqual(plan.source.contents, "* Destination\nExisting\n** TODO Move\nBody\n")
        XCTAssertEqual(plan.source, plan.destination)
    }

    func testRefileRejectsSelfDescendantAndStaleTarget() throws {
        let source = document("agenda/actions.org", "* Parent\n** Child\nBody\n")
        let target = try XCTUnwrap(OrgWorkflowOperations.refileTargets(in: [source]).last)
        XCTAssertThrowsError(try OrgWorkflowOperations.refile(source: source, headingStartByte: 0, destination: source, target: target)) {
            XCTAssertEqual($0 as? OrgWorkflowOperations.Failure, .targetInsideSubtree)
        }
        let changed = document(source.path, source.contents.replacingOccurrences(of: "Child", with: "Renamed"))
        XCTAssertThrowsError(try OrgWorkflowOperations.refile(source: source, headingStartByte: 0, destination: changed, target: target)) {
            XCTAssertEqual($0 as? OrgWorkflowOperations.Failure, .invalidTarget)
        }
    }

    private var now: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026; components.month = 9; components.day = 12
        components.hour = 10
        return components.date!
    }
    private var stamp: String { "[2026-09-12 Sat 10:00]" }
    private func document(_ path: String, _ source: String) -> WorkspaceDocument {
        WorkspaceDocument(path: path, title: path, contents: source, kind: .org)
    }
    private func item(state: OrgWorkflowState) -> OrgItem {
        OrgItem(id: UUID(), title: "Example", state: state, kind: .task, priority: .none,
                tags: [], scheduled: nil, deadline: nil, hasTime: false, durationMinutes: 30,
                recurrence: nil, body: "", source: SourceLocation(file: "agenda/inbox.org", startByte: 0, endByte: 0, startLine: 1), habitHistory: [])
    }
    private func byteOffset(of text: String, in source: String) -> Int {
        source[..<source.range(of: text)!.lowerBound].utf8.count
    }
}
