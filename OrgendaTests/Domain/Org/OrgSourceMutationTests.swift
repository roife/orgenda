import XCTest
import UIKit
@testable import Orgenda

final class OrgSourceMutationTests: XCTestCase {
    func testEditingNotesPreservesDrawersClocksAndLiteralBlocks() throws {
        let source = """
        * TODO 原文🙂
          :PROPERTIES:
          :ID: stable-id
          :END:
        Before.
          :LOGBOOK:
          CLOCK: [2026-09-19 Sat 09:00]--[2026-09-19 Sat 10:00] => 1:00
          - State "DONE" from "TODO" [2026-09-19 Sat]
          <2026-09-20 Sun>
          :END:
        :CUSTOM-NOTES:
        SCHEDULED: <2026-09-21 Mon>
        Keep this note.
        :END:
        CLOCK: => 0:30
        #+BEGIN_EXAMPLE
        * TODO Not a heading
        <2026-09-22 Tue>
        #+END_EXAMPLE
        #+BEGIN_COMMENT
        * TODO Also not a heading
        #+END_COMMENT
        After.
        """ + "\n"
        let (parsed, original) = try workflowFixture(source)
        XCTAssertFalse(parsed.hasError)
        XCTAssertEqual(parsed.headings.count, 1)
        XCTAssertNil(parsed.headings[0].eventDate)
        XCTAssertNil(parsed.headings[0].scheduled)
        XCTAssertEqual(parsed.headings[0].properties["ID"], "stable-id")
        XCTAssertEqual(original.body, "Before.\n\nAfter.")
        var edited = original
        edited.body = "Updated 中文🙂."
        let patches = try XCTUnwrap(OrgSourceMutation.itemEdits(
            replacing: original, with: edited, heading: parsed.root.children[0],
            following: Array(parsed.root.children.dropFirst())
        ))
        let updated = try patches.reduce(source) { try $1.applied(to: $0) }
        XCTAssertEqual(updated, source.replacingOccurrences(of: "Before.", with: edited.body)
            .replacingOccurrences(of: "After.\n", with: ""))
    }

    func testEditingIndentedPropertyKeepsIndentation() throws {
        let source = "* TODO Work\n  :PROPERTIES:\n  :ID: old-id\n  :END:\n"
        let (parsed, fixture) = try workflowFixture(source)
        var original = fixture
        original.properties = ["ID": "old-id"]
        var edited = original
        edited.properties["ID"] = "new-id"
        let patches = try XCTUnwrap(OrgSourceMutation.itemEdits(
            replacing: original, with: edited, heading: parsed.root.children[0],
            following: Array(parsed.root.children.dropFirst())
        ))
        let updated = try patches.reduce(source) { try $1.applied(to: $0) }
        XCTAssertEqual(updated, source.replacingOccurrences(of: "old-id", with: "new-id"))
    }

    func testRemovedWorkflowKeywordsRemainOrdinaryHeadingText() throws {
        let keywords = [
            "WAITING", "DELEGATED", "HOLD", "IMMEDIATE", "PROPOSED", "PLANNED",
            "ACTIVE", "BLOCKED", "PROJECT", "COMPLETED", "CANCELLED", "ABANDONED"
        ]
        let source = keywords.map { "* \($0) Work item\n" }.joined()
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "workflow.org", title: "Workflow", contents: source, kind: .org)
        ]).first)

        XCTAssertFalse(parsed.hasError)
        XCTAssertEqual(parsed.headings.map(\.title), keywords.map { "\($0) Work item" })
        XCTAssertTrue(parsed.headings.allSatisfy { $0.state == nil && $0.kind == .task })
        XCTAssertTrue(keywords.allSatisfy { OrgWorkflowState(rawValue: $0) == nil })
    }

    func testCurrentWorkflowUsesProjectTagForEveryStateIncludingUrgent() throws {
        let states: [OrgWorkflowState] = [.todo, .next, .wait, .someday, .urgent, .done, .canceled]
        let source = states.map { "* \($0.rawValue) Work item\n" }.joined()
            + states.map { "* \($0.rawValue) Project item :project:\n" }.joined()
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "workflow.org", title: "Workflow", contents: source, kind: .org)
        ]).first)

        XCTAssertEqual(parsed.headings.compactMap(\.state), states + states)
        XCTAssertEqual(parsed.headings.map(\.kind),
                       Array(repeating: .task, count: states.count)
                       + Array(repeating: .project, count: states.count))
        XCTAssertEqual(states.filter(\.isTerminal), [.done, .canceled])
    }

    func testOrdinaryUppercaseHeadingRemainsPartOfTitle() throws {
        let document = WorkspaceDocument(
            path: "notes.org", title: "Notes", contents: "* BUGS To investigate\n", kind: .org
        )
        let heading = try XCTUnwrap(OrgIndexService.parseSynchronously([document]).first?.headings.first)
        XCTAssertNil(heading.state)
        XCTAssertEqual(heading.title, "BUGS To investigate")
    }

    func testEditingWorkflowHeadingPreservesItsTokenAndOtherSource() throws {
        for state in OrgWorkflowState.allCases {
            let source = "#+CUSTOM: 保留🙂\n* \(state.rawValue) [#A] Original :work:\n:PROPERTIES:\n:ID: stable-id\n:END:\nBody.\n** Child\nUntouched.\n"
            let (parsed, original) = try workflowFixture(source)
            var edited = original
            edited.title = "更新的標題 🧪"
            let headingIndex = try XCTUnwrap(parsed.root.children.firstIndex(where: { $0.type == "heading" }))
            let heading = parsed.root.children[headingIndex]
            let following = Array(parsed.root.children.dropFirst(headingIndex + 1).prefix { $0.type != "heading" })
            let patches = try XCTUnwrap(OrgSourceMutation.itemEdits(
                replacing: original, with: edited, heading: heading, following: following
            ))
            let updated = try patches.reduce(source) { try $1.applied(to: $0) }
            XCTAssertEqual(updated, source.replacingOccurrences(of: "Original", with: "更新的標題 🧪"))
        }
    }

    private func workflowFixture(_ source: String) throws -> (ParsedOrgDocument, OrgItem) {
        let document = WorkspaceDocument(path: "workflow.org", title: "Workflow", contents: source, kind: .org)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([document]).first)
        let heading = try XCTUnwrap(parsed.headings.first)
        let item = OrgItem(
            id: UUID(), title: heading.title, state: try XCTUnwrap(heading.state), kind: heading.kind,
            priority: heading.priority, tags: heading.tags, scheduled: heading.scheduled,
            deadline: heading.deadline, hasTime: heading.hasTime, durationMinutes: 30,
            recurrence: heading.recurrence, body: heading.body, source: heading.source, habitHistory: []
        )
        return (parsed, item)
    }

    func testPlanningDraftAtomicallyChangesKeywordAndDateWithoutLosingSourceDetails() throws {
        var draft = try XCTUnwrap(
            OrgPlanningEntryDraft(source: "SCHEDULED:\t<2026-08-31 Mon 09:30 +1d>  ")
        )
        draft.keyword = .deadline
        draft.timestamps[0].date = try date(year: 2026, month: 9, day: 2, hour: 9, minute: 30)

        XCTAssertEqual(
            draft.source,
            "DEADLINE:\t<2026-09-02 Wed 09:30 +1d>  "
        )
    }

    func testPlainYearlyTimestampCanBeEditedWithoutAddingPlanningKeyword() throws {
        let source = "<2019-05-20 Mon +1y>"
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(timestampSource: source))
        XCTAssertNil(draft.keyword)
        XCTAssertEqual(draft.timestamps[0].recurrence, "+1y")
        XCTAssertEqual(draft.source, source)
        draft.timestamps[0].recurrence = "++2y"
        draft.timestamps[0].date = try date(year: 2019, month: 5, day: 21)
        XCTAssertEqual(draft.source, "<2019-05-21 Tue ++2y>")
        XCTAssertNil(OrgPlanningEntryDraft(timestampSource: "Text <2019-05-20 Mon +1y>"))
    }

    func testRecurrenceEditingPreservesWarningTimeRangeAndWhitespace() throws {
        let source = "DEADLINE:\t<2019-05-20  Mon\t09:00-10:30  .+2d/3d\t-2d>  "
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(source: source))
        XCTAssertEqual(draft.source, source)
        XCTAssertEqual(draft.timestamps[0].recurrence, ".+2d/3d")
        // Typing a custom rule passes through incomplete tokens; these must
        // replace the original token rather than accumulate in the suffix.
        for partial in ["", "+", "+1", "+1y"] {
            draft.timestamps[0].recurrence = partial
        }
        XCTAssertEqual(draft.source, source.replacingOccurrences(of: ".+2d/3d", with: "+1y"))
        draft.timestamps[0].setRecurrence(nil)
        XCTAssertEqual(draft.source, "DEADLINE:\t<2019-05-20  Mon\t09:00-10:30 \t-2d>  ")
    }

    func testAddingRepeaterPlacesItAfterTimeRangeAndBeforeWarning() throws {
        for time in ["", " 09:00-10:30"] {
            var draft = try XCTUnwrap(OrgPlanningEntryDraft(source: "SCHEDULED: <2019-05-20 Mon\(time) -2d>"))
            draft.timestamps[0].recurrence = "+1y"
            XCTAssertEqual(draft.source, "SCHEDULED: <2019-05-20 Mon\(time) +1y -2d>")
        }
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(timestampSource: "<2019-05-20 Mon 09:00-10:30>"))
        draft.timestamps[0].recurrence = "+1y"
        XCTAssertEqual(draft.source, "<2019-05-20 Mon 09:00-10:30 +1y>")
    }

    func testRepeatRulesRoundTripForEveryModeUnitAndRangeEndpoint() throws {
        for mode in ["+", "++", ".+"] {
            for unit in ["h", "d", "w", "m", "y"] {
                let token = "\(mode)2\(unit)"
                var draft = try XCTUnwrap(OrgPlanningEntryDraft(
                    timestampSource: "[2019-05-20 Mon +1y]--[2019-05-22 Wed .+2d/3d]"
                ))
                draft.timestamps[0].recurrence = token
                let updated = try XCTUnwrap(OrgPlanningEntryDraft(timestampSource: draft.source))
                XCTAssertEqual(updated.timestamps.map(\.recurrence), [token, ".+2d/3d"])
                XCTAssertEqual(updated.source, "[2019-05-20 Mon \(token)]--[2019-05-22 Wed .+2d/3d]")
            }
        }
    }

    func testInlineRecurringTimestampPatchPreservesUnicodeAndOtherDates() throws {
        let source = "* Anniversary\n纪念日 🎉 <2019-05-20 Mon +1y>，另一天 <2020-01-01 Wed +1m>。\n"
        let document = WorkspaceDocument(path: "calendar.org", title: "Calendar", contents: source, kind: .org)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([document]).first)
        XCTAssertEqual(parsed.headings.first?.kind, .event)
        XCTAssertEqual(parsed.headings.first?.recurrence, "+1y")
        let timestamp = try XCTUnwrap(OrgHeadingBody.firstActiveTimestamp(in: parsed.root.children))
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(timestampSource: timestamp.text))
        draft.timestamps[0].recurrence = "++1y"
        let patch = OrgSourceMutation(startByte: timestamp.startByte, endByte: timestamp.endByte,
                                      replacement: draft.source)
        XCTAssertEqual(try patch.applied(to: source), source.replacingOccurrences(of: "+1y", with: "++1y"))
    }

    func testPlanningRangePreservesEachTimestampDelimiterWhenMarkedClosed() throws {
        var draft = try XCTUnwrap(
            OrgPlanningEntryDraft(
                source: "DEADLINE: <2026-08-31 Mon>--<2026-09-02 Wed>"
            )
        )
        XCTAssertTrue(draft.isRange)

        draft.keyword = .closed
        draft.timestamps[1].date = try date(year: 2026, month: 9, day: 3)

        XCTAssertEqual(
            draft.source,
            "CLOSED: <2026-08-31 Mon>--<2026-09-03 Thu>"
        )
    }

    func testInactivePlanningTimestampRemainsInactiveWhenTypeChanges() throws {
        var draft = try XCTUnwrap(
            OrgPlanningEntryDraft(source: "CLOSED: [2026-08-31 Mon 18:00]")
        )
        draft.keyword = .scheduled
        draft.timestamps[0].date = try date(year: 2026, month: 9, day: 1, hour: 18)

        XCTAssertEqual(draft.source, "SCHEDULED: [2026-09-01 Tue 18:00]")
    }

    func testPlanningTimeCanBeAddedAndRemovedWithoutTouchingRepeater() throws {
        var draft = try XCTUnwrap(
            OrgPlanningEntryDraft(source: "SCHEDULED: <2026-08-31 Mon +1w>")
        )
        draft.timestamps[0].includesTime = true
        draft.timestamps[0].date = try date(year: 2026, month: 8, day: 31, hour: 8, minute: 45)
        XCTAssertEqual(draft.source, "SCHEDULED: <2026-08-31 Mon 08:45 +1w>")

        draft.timestamps[0].includesTime = false
        XCTAssertEqual(draft.source, "SCHEDULED: <2026-08-31 Mon +1w>")
    }

    func testPlanningTypeOnlyChangePreservesTimestampBytesAndDateKeepsStyle() throws {
        var draft = try XCTUnwrap(
            OrgPlanningEntryDraft(
                source: "SCHEDULED:\t<2026-08-31  MON\t09:30 ++1m -2d>  "
            )
        )
        draft.keyword = .deadline
        XCTAssertEqual(
            draft.source,
            "DEADLINE:\t<2026-08-31  MON\t09:30 ++1m -2d>  "
        )

        draft.timestamps[0].date = try date(
            year: 2026,
            month: 9,
            day: 2,
            hour: 9,
            minute: 30
        )
        XCTAssertEqual(
            draft.source,
            "DEADLINE:\t<2026-09-02  WED\t09:30 ++1m -2d>  "
        )
    }

    func testWorkflowToggleUsesUTF8OffsetsAfterCJKAndEmojiAndPreservesWhitespace() throws {
        let source = "#+未知: 保留🙂\n* TODO \t写 parser\n"
        let token = "TODO \t"
        let range = try byteRange(of: token, in: source)

        let next = try OrgSourceMutation.workflowToggle(
            in: source,
            startByte: range.start,
            endByte: range.end
        ).applied(to: source)

        XCTAssertEqual(next, "#+未知: 保留🙂\n* DONE \t写 parser\n")
        XCTAssertEqual(next.utf8.count, source.utf8.count)
    }

    func testWorkflowToggleCompletesOpenStatesAndReopensTerminalStates() throws {
        let expected = [
            "TODO": "DONE", "NEXT": "DONE", "WAIT": "DONE", "SOMEDAY": "DONE",
            "URGENT": "DONE", "DONE": "TODO", "CANCELED": "TODO",
        ]

        for (current, next) in expected {
            let source = "* \(current) \t标题\n"
            let range = try byteRange(of: "\(current) \t", in: source)
            let updated = try OrgSourceMutation.workflowToggle(
                in: source,
                startByte: range.start,
                endByte: range.end
            ).applied(to: source)

            XCTAssertEqual(updated, "* \(next) \t标题\n", current)
        }
    }

    func testCheckboxToggleSupportsUncheckedCheckedAndIndeterminateTokens() throws {
        XCTAssertEqual(
            try toggledCheckbox(in: "- [ ]  未完成\n", token: "[ ]  "),
            "- [X]  未完成\n"
        )
        XCTAssertEqual(
            try toggledCheckbox(in: "- [X]\t完成\n", token: "[X]\t"),
            "- [ ]\t完成\n"
        )
        XCTAssertEqual(
            try toggledCheckbox(in: "- [-] 部分完成\n", token: "[-] "),
            "- [X] 部分完成\n"
        )
    }

    func testRejectsNegativeUnorderedOutOfBoundsAndMidScalarRanges() {
        let source = "A你🙂B"

        XCTAssertThrowsError(
            try OrgSourceMutation(startByte: -1, endByte: 1, replacement: "").applied(to: source)
        ) { error in
            XCTAssertEqual(
                error as? OrgSourceMutationError,
                .negativeByteOffset(startByte: -1, endByte: 1)
            )
        }

        XCTAssertThrowsError(
            try OrgSourceMutation(startByte: 4, endByte: 1, replacement: "").applied(to: source)
        ) { error in
            XCTAssertEqual(
                error as? OrgSourceMutationError,
                .unorderedByteRange(startByte: 4, endByte: 1)
            )
        }

        XCTAssertThrowsError(
            try OrgSourceMutation(startByte: 0, endByte: 10, replacement: "").applied(to: source)
        ) { error in
            XCTAssertEqual(
                error as? OrgSourceMutationError,
                .byteRangeOutOfBounds(startByte: 0, endByte: 10, sourceUTF8Count: 9)
            )
        }

        // `你` occupies bytes 1..<4; byte 2 is in the middle of its scalar.
        XCTAssertThrowsError(
            try OrgSourceMutation(startByte: 2, endByte: 4, replacement: "文").applied(to: source)
        ) { error in
            XCTAssertEqual(
                error as? OrgSourceMutationError,
                .invalidStringBoundary(byteOffset: 2)
            )
        }

        // `🙂` occupies bytes 4..<8; byte 7 is in the middle of its scalar.
        XCTAssertThrowsError(
            try OrgSourceMutation(startByte: 4, endByte: 7, replacement: "😀").applied(to: source)
        ) { error in
            XCTAssertEqual(
                error as? OrgSourceMutationError,
                .invalidStringBoundary(byteOffset: 7)
            )
        }
    }

    func testUnknownSyntaxBeforeAndAfterReplacementIsByteForBytePreserved() throws {
        let prefix = "#+CUSTOM_ODD: 🧪 原样\n<<opaque::语法>>\n* "
        let suffix = " 标题 :奇怪:tag:\n%% raw 🚀 bytes %%\n"
        let source = prefix + "TODO" + suffix
        let startByte = prefix.utf8.count
        let endByte = startByte + "TODO".utf8.count

        let next = try OrgSourceMutation.workflowToggle(
            in: source,
            startByte: startByte,
            endByte: endByte
        ).applied(to: source)

        XCTAssertEqual(next, prefix + "DONE" + suffix)
        XCTAssertEqual(Array(next.utf8.prefix(prefix.utf8.count)), Array(prefix.utf8))
        XCTAssertEqual(Array(next.utf8.suffix(suffix.utf8.count)), Array(suffix.utf8))
    }

    func testMultipleEqualLengthPatchesKeepOriginalTreeSitterOffsetsStable() throws {
        let original = "说明🙂\n* TODO 第一项\n* NEXT 第二项\n- [ ] 清单\n"
        let todoRange = try byteRange(of: "TODO", in: original)
        let nextRange = try byteRange(of: "NEXT", in: original)
        let checkboxRange = try byteRange(of: "[ ]", in: original)

        // Every mutation replaces its node with the same UTF-8 byte length, so
        // all three ranges captured from the original parse remain valid.
        var source = original
        source = try OrgSourceMutation.workflowToggle(
            in: source,
            startByte: todoRange.start,
            endByte: todoRange.end
        ).applied(to: source)
        source = try OrgSourceMutation.workflowToggle(
            in: source,
            startByte: nextRange.start,
            endByte: nextRange.end
        ).applied(to: source)
        source = try OrgSourceMutation.checkboxToggle(
            in: source,
            startByte: checkboxRange.start,
            endByte: checkboxRange.end
        ).applied(to: source)

        XCTAssertEqual(source, "说明🙂\n* DONE 第一项\n* DONE 第二项\n- [X] 清单\n")
        XCTAssertEqual(source.utf8.count, original.utf8.count)
    }

    func testUnsupportedSemanticTokenReturnsExplicitErrorWithoutChangingSource() throws {
        let source = "前缀🙂\n* WAITING 保持\n后缀🧷\n"
        let range = try byteRange(of: "WAITING ", in: source)

        XCTAssertThrowsError(
            try OrgSourceMutation.workflowToggle(
                in: source,
                startByte: range.start,
                endByte: range.end
            ).applied(to: source)
        ) { error in
            XCTAssertEqual(
                error as? OrgSourceMutationError,
                .unsupportedWorkflowToken("WAITING")
            )
        }
        XCTAssertEqual(source, "前缀🙂\n* WAITING 保持\n后缀🧷\n")
    }

    private func toggledCheckbox(in source: String, token: String) throws -> String {
        let range = try byteRange(of: token, in: source)
        return try OrgSourceMutation.checkboxToggle(
            in: source,
            startByte: range.start,
            endByte: range.end
        ).applied(to: source)
    }

    private func byteRange(of token: String, in source: String) throws -> (start: Int, end: Int) {
        let stringRange = try XCTUnwrap(source.range(of: token))
        let start = source.utf8.distance(
            from: source.utf8.startIndex,
            to: stringRange.lowerBound
        )
        let length = token.utf8.count
        return (start, start + length)
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: .autoupdatingCurrent,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}

final class EmacsOrgSemanticsTests: XCTestCase {
    func testAllDayCompletionWritesClosedTimeAndUnchangedClosedKeepsLiteral() throws {
        let source = "* TODO Review\nSCHEDULED: <2026-09-12 Sat>\n"
        let updated = try edited(source) { item in
            item.state = .done
            item.closed = date(12, hour: 18, minute: 45)
        }
        XCTAssertTrue(updated.contains("CLOSED: [2026-09-12 Sat 18:45]"))
        XCTAssertTrue(updated.contains("SCHEDULED: <2026-09-12 Sat>"))
        let legacy = "* DONE Review\nCLOSED: [2026-09-11 Fri]\n"
        let renamed = try edited(legacy) { $0.title = "Renamed" }
        XCTAssertEqual(renamed, legacy.replacingOccurrences(of: "Review", with: "Renamed"))
        let newCompletion = try edited(legacy) { $0.closed = date(12, hour: 7, minute: 30) }
        XCTAssertTrue(newCompletion.contains("CLOSED: [2026-09-12 Sat 07:30]"))
    }

    func testCalendarCaptureUsesActiveTimestampAndMetadata() throws {
        let source = "* 设计评审🙂\n:PROPERTIES:\n:CREATED: [2026-09-01 Tue 09:00]\n:APPT_WARNTIME: 20\n:END:\n<2026-09-12 Sat 10:15-11:45 ++1w>\nBring drawings.\n"
        let (_, item) = try fixture(source)
        XCTAssertEqual(item.kind, .event)
        XCTAssertNil(item.scheduled)
        XCTAssertNil(item.deadline)
        XCTAssertEqual(item.eventDate, date(12, hour: 10, minute: 15))
        XCTAssertEqual(item.agendaDate, item.eventDate)
        XCTAssertEqual(item.durationMinutes, 90)
        XCTAssertEqual(item.recurrence, "++1w")
        XCTAssertEqual(item.body, "Bring drawings.")
        XCTAssertEqual(item.appointmentWarningMinutes, 20)
        XCTAssertEqual(item.properties["CREATED"], "[2026-09-01 Tue 09:00]")
    }

    func testOnlyRealActiveBodyTimestampsCreateEvents() throws {
        let sources = [
            "* Note\n:PROPERTIES:\n:CREATED: <2026-09-12 Sat 10:00>\n:END:\n",
            "* Note\n:LOGBOOK:\n- Changed at <2026-09-12 Sat 10:00>\n:END:\n",
            "* Note\n#+begin_src org\n<2026-09-12 Sat 10:00>\n#+end_src\n",
            "* Note\n~<2026-09-12 Sat 10:00>~ and =<2026-09-12 Sat 11:00>=\n",
            "* Note\n[2026-09-12 Sat 10:00]\n",
            "* Note\n:PROPERTIES:\n:APPT_WARNTIME: -2\n:END:\n<2026-02-30 Mon>\n"
        ]
        for source in sources {
            let (_, item) = try fixture(source)
            XCTAssertNil(item.eventDate, source)
            XCTAssertNil(item.appointmentWarningMinutes, source)
        }
        let (_, item) = try fixture("* Meet\n:LOGBOOK:\n- Old <2026-09-01 Tue>\n:END:\n<2026-09-12 Sat>\n")
        XCTAssertEqual(item.eventDate, date(12))
        XCTAssertEqual(item.body, "")
    }

    func testHabitRequiresStyleOrExplicitTagInsteadOfRepeater() throws {
        let (_, repeating) = try fixture("* TODO Weekly reminder\nSCHEDULED: <2026-09-12 Sat 09:00 .+1w>\n")
        XCTAssertEqual(repeating.kind, .task)
        let (_, habit) = try fixture("* TODO Walk\nSCHEDULED: <2026-09-12 Sat .+2d/3d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n")
        XCTAssertEqual(habit.kind, .habit)
        XCTAssertEqual(habit.recurrence, ".+2d/3d")
        let (_, note) = try fixture("* Reference :note:\n")
        XCTAssertEqual(note.kind, .note)
    }

    func testEditingEventKeepsTimestampInBodyAndPreservesItsRangeAndDrawer() throws {
        let source = "#+CUSTOM: 保留🙂\n* 设计会\n:PROPERTIES:\n:CREATED: [2026-09-01 Tue]\n:APPT_WARNTIME: 15\n:END:\n<2026-09-12 Sat 10:15-11:45 ++1w -2d>\nOld notes.\n:LOGBOOK:\n- Preserved [2026-09-01 Tue]\n:END:\n** Child\nUntouched.\n"
        let updated = try edited(source) { item in
            item.eventDate = date(13, hour: 12, minute: 0)
            item.body = "New notes 中文."
            item.properties["APPT_WARNTIME"] = "25"
        }
        XCTAssertEqual(updated, source
            .replacingOccurrences(of: "<2026-09-12 Sat 10:15-11:45 ++1w -2d>", with: "<2026-09-13 Sun 12:00-13:30 ++1w -2d>")
            .replacingOccurrences(of: "Old notes.", with: "New notes 中文.")
            .replacingOccurrences(of: ":APPT_WARNTIME: 15", with: ":APPT_WARNTIME: 25"))
        XCTAssertFalse(updated.contains("SCHEDULED:"))
    }

    func testMovingTimestampRangeKeepsItsDurationAndAllDayRemovesTimes() throws {
        let source = "* Conference\n<2026-09-12 Sat 09:00>--<2026-09-13 Sun 17:00>\n"
        let (_, original) = try fixture(source)
        XCTAssertEqual(original.durationMinutes, 32 * 60)
        let updated = try edited(source) { $0.eventDate = date(14, hour: 9) }
        XCTAssertEqual(updated, "* Conference\n<2026-09-14 Mon 09:00>--<2026-09-15 Tue 17:00>\n")
        let allDay = try edited("* Lunch\n<2026-09-12 Sat 12:00-13:00 +1w>\n") {
            $0.hasTime = false
            $0.eventDate = date(12)
        }
        XCTAssertEqual(allDay, "* Lunch\n<2026-09-12 Sat +1w>\n")
    }

    func testEditingInlineDateAndNotesProducesNonoverlappingPatches() throws {
        let source = "* Meeting\nDiscuss launch on <2026-09-12 Sat 09:00-10:00>.\n"
        let updated = try edited(source) {
            $0.eventDate = date(13, hour: 11)
            $0.body = "Discuss release on <2026-09-12 Sat 09:00-10:00>."
        }
        XCTAssertEqual(updated, "* Meeting\nDiscuss release on <2026-09-13 Sun 11:00-12:00>.\n")
    }

    func testAddingEventTimestampAndPropertiesDoesNotCreateScheduledPlanning() throws {
        let source = "* Meeting\nNotes.\n"
        let updated = try edited(source) {
            $0.kind = .event
            $0.eventDate = date(12, hour: 9)
            $0.hasTime = true
            $0.properties["APPT_WARNTIME"] = "15"
        }
        XCTAssertTrue(updated.contains(":PROPERTIES:\n:APPT_WARNTIME: 15\n:END:\n"))
        XCTAssertTrue(updated.contains("<2026-09-12 Sat 09:00>"))
        XCTAssertFalse(updated.contains("SCHEDULED:"))
        let (_, item) = try fixture(updated)
        XCTAssertEqual(item.eventDate, date(12, hour: 9))
        XCTAssertEqual(item.body, "Notes.")
    }

    func testChangingHabitRepeaterReplacesEntireMinimumMaximumToken() throws {
        let source = "* TODO Walk\nSCHEDULED: <2026-09-12 Sat .+2d/3d -1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"
        let updated = try edited(source) { $0.recurrence = ".+1w" }
        XCTAssertEqual(updated, source.replacingOccurrences(of: ".+2d/3d", with: ".+1w"))
    }

    func testPlanningRangeIndexesTimeAndDurationWithoutCreatingEvent() throws {
        let (_, item) = try fixture("* TODO Review\nSCHEDULED: <2026-09-12 Sat 09:30>--<2026-09-12 Sat 11:00>\n")
        XCTAssertEqual(item.scheduled, date(12, hour: 9, minute: 30))
        XCTAssertNil(item.eventDate)
        XCTAssertEqual(item.durationMinutes, 90)
    }

    private func fixture(_ source: String) throws -> (ParsedOrgDocument, OrgItem) {
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "agenda/calendar.org", title: "Calendar", contents: source, kind: .org)
        ]).first)
        let heading = try XCTUnwrap(parsed.headings.first)
        return (parsed, OrgItem(
            id: UUID(), title: heading.title, state: heading.state ?? .todo, kind: heading.kind,
            priority: heading.priority, tags: heading.tags, scheduled: heading.scheduled,
            deadline: heading.deadline, closed: heading.closed, eventDate: heading.eventDate,
            hasTime: heading.hasTime, durationMinutes: heading.durationMinutes, recurrence: heading.recurrence,
            body: heading.body, source: heading.source, habitHistory: [], properties: heading.properties
        ))
    }

    private func edited(_ source: String, change: (inout OrgItem) -> Void) throws -> String {
        let (parsed, original) = try fixture(source)
        var item = original
        change(&item)
        let index = try XCTUnwrap(parsed.root.children.firstIndex { $0.type == "heading" })
        let heading = parsed.root.children[index]
        let following = Array(parsed.root.children.dropFirst(index + 1).prefix { $0.type != "heading" })
        let patches = try XCTUnwrap(OrgSourceMutation.itemEdits(replacing: original, with: item, heading: heading, following: following))
        return try patches.reduce(source) { try $1.applied(to: $0) }
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
}

final class OrgRepeaterTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return value
    }

    func testStrictRepeaterParsingAcceptsConfiguredAndHabitIntervals() throws {
        for token in ["+1h", "++2d", ".+1w", "+3m", "++1y", ".+2d/3d"] {
            XCTAssertNotNil(OrgRepeater(token), token)
        }
        for token in ["+0d", "+-1d", "+1q", "+1d junk", "+1d\n", "++9999999999999999999999h", ".+1d/0d", "1d"] {
            XCTAssertNil(OrgRepeater(token), token)
        }
        XCTAssertEqual(OrgRepeater(".+2d/3d")?.maximumInterval, 3)
        XCTAssertEqual(OrgRepeater(".+2d/3d")?.maximumUnit, .day)
    }

    func testCumulativeAdvancesExactlyOnceEvenWhenStillOverdue() throws {
        let repeater = try XCTUnwrap(OrgRepeater("+1w"))
        XCTAssertEqual(repeater.nextDate(afterCompletion: date(2026, 9, 25), from: date(2026, 9, 1, 9), calendar: calendar),
                       date(2026, 9, 8, 9))
    }

    func testCatchUpKeepsCadenceAndCanUseLaterTimeToday() throws {
        let repeater = try XCTUnwrap(OrgRepeater("++1w"))
        XCTAssertEqual(repeater.nextDate(afterCompletion: date(2026, 9, 12, 10), from: date(2026, 9, 1, 9), calendar: calendar),
                       date(2026, 9, 15, 9))
        let daily = try XCTUnwrap(OrgRepeater("++1d"))
        XCTAssertEqual(daily.nextDate(afterCompletion: date(2026, 9, 12, 10), from: date(2026, 9, 1, 20), calendar: calendar),
                       date(2026, 9, 12, 20))
        XCTAssertEqual(daily.nextDate(afterCompletion: date(2026, 9, 12, 20), from: date(2026, 9, 1, 20), calendar: calendar),
                       date(2026, 9, 13, 20))
        XCTAssertEqual(daily.nextDate(afterCompletion: date(2026, 9, 1, 10), from: date(2026, 9, 12, 20), calendar: calendar),
                       date(2026, 9, 13, 20))
    }

    func testRestartPreservesBaseClockExceptForHourlyRepeater() throws {
        let daily = try XCTUnwrap(OrgRepeater(".+1d"))
        XCTAssertEqual(daily.nextDate(afterCompletion: date(2026, 9, 12, 10, 30), from: date(2026, 9, 1, 20), calendar: calendar),
                       date(2026, 9, 13, 20))
        let hourly = try XCTUnwrap(OrgRepeater(".+2h"))
        XCTAssertEqual(hourly.nextDate(afterCompletion: date(2026, 9, 12, 10, 30), from: date(2026, 9, 1, 20), calendar: calendar),
                       date(2026, 9, 12, 12, 30))
        let monthly = try XCTUnwrap(OrgRepeater(".+1m"))
        XCTAssertEqual(monthly.nextDate(afterCompletion: date(2026, 1, 31, 10), from: date(2025, 8, 1, 9), calendar: calendar),
                       date(2026, 2, 28, 9))
    }

    func testOccurrenceLookupIsBoundedToRequestedDayAndKeepsOriginalAnchor() throws {
        let monthly = try XCTUnwrap(OrgRepeater("+1m"))
        let base = date(2026, 1, 31, 9)
        XCTAssertEqual(monthly.occurrences(on: date(2026, 2, 28), from: base, calendar: calendar), [date(2026, 2, 28, 9)])
        XCTAssertEqual(monthly.occurrences(on: date(2026, 3, 31), from: base, calendar: calendar), [date(2026, 3, 31, 9)])
        XCTAssertTrue(monthly.occurrences(on: date(2026, 3, 30), from: base, calendar: calendar).isEmpty)
        XCTAssertTrue(monthly.occurrences(on: date(2025, 12, 31), from: base, calendar: calendar).isEmpty)
        let hourly = try XCTUnwrap(OrgRepeater("+2h"))
        let occurrences = hourly.occurrences(on: date(2026, 9, 12), from: date(1970, 1, 1, 1), calendar: calendar)
        XCTAssertEqual(occurrences.count, 12)
        XCTAssertEqual(occurrences.first, date(2026, 9, 12, 1))
        XCTAssertEqual(occurrences.last, date(2026, 9, 12, 23))
    }

    func testRepeatingDatesRespectDSTAndLeapYears() throws {
        var newYork = calendar
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let yearly = try XCTUnwrap(OrgRepeater("+1y"))
        let leap = date(2024, 2, 29, 9)
        XCTAssertEqual(yearly.occurrences(on: date(2028, 2, 29), from: leap, calendar: calendar), [date(2028, 2, 29, 9)])
        let daily = try XCTUnwrap(OrgRepeater("+1d"))
        let base = newYork.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!
        let next = try XCTUnwrap(daily.nextDate(afterCompletion: base, from: base, calendar: newYork))
        XCTAssertEqual(newYork.component(.hour, from: next), 9)
        XCTAssertEqual(next.timeIntervalSince(base), 23 * 3600)
        let restart = try XCTUnwrap(OrgRepeater(".+1d"))
        let beforeDST = newYork.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 2, minute: 30))!
        let completionOnDST = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let resumed = try XCTUnwrap(restart.nextDate(afterCompletion: completionOnDST, from: beforeDST, calendar: newYork))
        XCTAssertEqual(newYork.component(.hour, from: resumed), 2)
        XCTAssertEqual(newYork.component(.minute, from: resumed), 30)
        let hourly = try XCTUnwrap(OrgRepeater("+1h"))
        let fallDay = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        XCTAssertEqual(hourly.occurrences(on: fallDay, from: fallDay, calendar: newYork).count, 25)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

final class OrgPreviewPresentationTests: XCTestCase {
    func testPlainLinkPreviewPreservesURLAndSurroundingItalicText() throws {
        let target = "https://example.com/a_b/c_d?q=one+two&next=/docs/#section"
        let source = "中文🙂 (\(target)). /斜体/\r\n"
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "links.org", title: "Links", contents: source, kind: .org)
        ]).first)
        let paragraph = try XCTUnwrap(document.root.children.first)
        let rendered = OrgPreviewMarkup.attributed(paragraph)
        let linkedRuns = rendered.runs.filter { $0.link != nil }
        let italicRuns = rendered.runs.filter { $0.inlinePresentationIntent?.contains(.emphasized) == true }

        XCTAssertEqual(String(rendered.characters), "中文🙂 (\(target)). 斜体")
        XCTAssertEqual(linkedRuns.map { String(rendered[$0.range].characters) }, [target])
        XCTAssertEqual(linkedRuns.map(\.link), [URL(string: target)])
        XCTAssertEqual(italicRuns.map { String(rendered[$0.range].characters) }, ["斜体"])
        XCTAssertEqual(paragraph.text, source)
    }

    func testLinkPreviewKeepsExistingFormsAndSchemeRestrictions() throws {
        let source = """
        [[https://example.com/a/b][Label /literal/]]
        <https://example.com/a/b>
        mailto:first_last@example.com
        custom://example.com/a/b
        ~https://example.com/a/b~ =https://example.com/a/b=
        """
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "links.org", title: "Links", contents: source, kind: .org)
        ]).first)
        let rendered = document.root.children.map { OrgPreviewMarkup.attributed($0) }

        XCTAssertEqual(rendered.map { String($0.characters) }, [
            "Label /literal/",
            "https://example.com/a/b",
            "mailto:first_last@example.com",
            "custom://example.com/a/b",
            "https://example.com/a/b https://example.com/a/b",
        ])
        XCTAssertEqual(rendered.map { $0.runs.compactMap(\.link).count }, [1, 1, 1, 0, 0])
        for value in rendered {
            XCTAssertFalse(value.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        }
    }

    func testReadableDateKeepsTimeRangeRepeatModesWarningsAndSource() throws {
        let source = "SCHEDULED: <2026-09-19 Sat 09:30-11:00 .+2d/3d -1d>"
        let draft = try XCTUnwrap(OrgPlanningEntryDraft(source: source))
        let text = OrgPreviewDateText(draft: draft, locale: Locale(identifier: "en_GB"), now: draft.timestamps[0].date)
        XCTAssertEqual(text.keyword, "Scheduled")
        XCTAssertTrue(text.date.contains("09:30–11:00"))
        XCTAssertFalse(text.date.contains("2026"))
        XCTAssertEqual(text.details, ["Every 2 days after completion · maximum 3 days", "-1d"])
        XCTAssertEqual(draft.source, source)
        let chinese = OrgPreviewDateText(draft: draft, locale: Locale(identifier: "zh_CN"))
        XCTAssertEqual(chinese.keyword, "计划")
        XCTAssertTrue(chinese.details[0].contains("从完成时算起"))
    }

    func testReadableRangeKeepsDifferentYearsAndAllDayDates() throws {
        let source = "<2025-12-31 Wed>--<2026-01-02 Fri ++1y>"
        let draft = try XCTUnwrap(OrgPlanningEntryDraft(timestampSource: source))
        let text = OrgPreviewDateText(draft: draft, locale: Locale(identifier: "en_GB"), now: draft.timestamps[1].date)
        XCTAssertTrue(text.date.contains("2025"))
        XCTAssertTrue(text.date.contains(" → "))
        XCTAssertFalse(text.date.contains("00:00"))
        XCTAssertEqual(text.details, ["Every year · skip missed dates"])
        XCTAssertEqual(draft.source, source)
        let daily = try XCTUnwrap(OrgPlanningEntryDraft(source: "SCHEDULED: <2026-09-19 Sat +1d>"))
        XCTAssertEqual(OrgPreviewDateText(draft: daily, locale: Locale(identifier: "zh_CN")).details, ["每天重复"])
        XCTAssertEqual(OrgPreviewDateText(draft: daily, locale: Locale(identifier: "zh_TW")).details, ["每天重複"])
    }

    func testBodyAlignmentUsesActualParentLevelIncludingSkippedLevels() throws {
        let source = "Preamble\n* TODO Parent\nBody\n*** TODO Nested\nSCHEDULED: <2026-09-19 Sat>\nNested body\n* Sibling\nSibling body\n"
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "alignment.org", title: "Alignment", contents: source, kind: .org)
        ]).first)
        let rows = OrgPreviewOutline.rows(from: document.root.children)
        var contentAxis: CGFloat = 0
        for row in rows {
            if row.headingLevel != nil {
                // Body text follows the compact disclosure axis introduced by
                // the preview indentation change, not the old 48-point gutter.
                contentAxis = row.indentation + 14
            } else {
                XCTAssertEqual(row.indentation, contentAxis)
            }
        }
    }

    func testPreviewPlacesPlanningBelowHeadingDrawers() throws {
        let source = """
        * TODO With metadata
        SCHEDULED: <2026-09-20 Sun>
        DEADLINE: <2026-09-21 Mon>
        :PROPERTIES:
        :ID: preview-order
        :END:
        :LOGBOOK:
        Note
        :END:
        Body
        * TODO Planning only
        SCHEDULED: <2026-09-22 Tue>
        Body
        """ + "\n"
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "preview-order.org", title: "Preview Order", contents: source, kind: .org)
        ]).first)

        XCTAssertEqual(OrgPreviewOutline.rows(from: document.root.children).map(\.node.type), [
            "heading", "property_drawer", "drawer", "planning", "planning", "paragraph",
            "heading", "planning", "paragraph",
        ])
    }

    func testPreviewTextContrastOnLightAndDarkSurfaces() {
        func luminance(_ color: UIColor, _ traits: UITraitCollection) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return zip([r, g, b], [0.2126, 0.7152, 0.0722]).reduce(0) { total, pair in
                let channel = Double(pair.0)
                return total + (channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)) * pair.1
            }
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for foreground in [OrgendaTheme.previewMetadataColor, UIColor.label] {
                for background in [UIColor.systemBackground, .systemGroupedBackground, .secondarySystemGroupedBackground] {
                    let a = luminance(foreground, traits), b = luminance(background, traits)
                    let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5)
                    print("Preview contrast style=\(style.rawValue): \(ratio)")
                }
            }
        }
    }
}
