import XCTest
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

    func testPlanningEditsPreserveCombiningMarksOutsideDateTokens() throws {
        for body in ["Sa\u{301}b 09:30", "Sat 0\u{301}9:30"] {
            let source = "说明🙂 SCHEDULED:\t<2026-09-19 \(body) +1d>\t"
            var draft = try XCTUnwrap(OrgPlanningEntryDraft(source: source))
            XCTAssertEqual(draft.source, source)
            XCTAssertFalse(draft.timestamps[0].includesTime)
            XCTAssertEqual(draft.timestamps[0].recurrence, "+1d")
            draft.timestamps[0].recurrence = "++2w"
            XCTAssertEqual(draft.source, source.replacingOccurrences(of: "+1d", with: "++2w"))
        }

        let source = "<2026-09-19 Sat 09:30 +1d\u{301}>"
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(timestampSource: source))
        XCTAssertNil(draft.timestamps[0].recurrence)
        draft.timestamps[0].recurrence = "+2w"
        XCTAssertEqual(draft.source, "<2026-09-19 Sat 09:30 +2w +1d\u{301}>")
    }

    func testRejectsNegativeUnorderedOutOfBoundsAndMidScalarRanges() {
        let cases: [(Int, Int, OrgSourceMutationError)] = [
            (-1, 1, .negativeByteOffset(startByte: -1, endByte: 1)),
            (4, 1, .unorderedByteRange(startByte: 4, endByte: 1)),
            (0, 10, .byteRangeOutOfBounds(startByte: 0, endByte: 10, sourceUTF8Count: 9)),
            (2, 4, .invalidStringBoundary(byteOffset: 2)),
            (4, 7, .invalidStringBoundary(byteOffset: 7))
        ]
        for (start, end, expected) in cases {
            XCTAssertThrowsError(try OrgSourceMutation(startByte: start, endByte: end, replacement: "文").applied(to: "A你🙂B")) {
                XCTAssertEqual($0 as? OrgSourceMutationError, expected)
            }
        }
    }

}

final class OrgRepeaterTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return value
    }

    func testCompletionDatesRespectCumulativeCatchUpAndRestartRules() throws {
        let cases: [(String, Date, Date, Date)] = [
            ("+1w", date(2026, 9, 25), date(2026, 9, 1, 9), date(2026, 9, 8, 9)),
            ("++1w", date(2026, 9, 12, 10), date(2026, 9, 1, 9), date(2026, 9, 15, 9)),
            ("++1d", date(2026, 9, 12, 10), date(2026, 9, 1, 20), date(2026, 9, 12, 20)),
            ("++1d", date(2026, 9, 12, 20), date(2026, 9, 1, 20), date(2026, 9, 13, 20)),
            ("++1d", date(2026, 9, 1, 10), date(2026, 9, 12, 20), date(2026, 9, 13, 20)),
            (".+1d", date(2026, 9, 12, 10, 30), date(2026, 9, 1, 20), date(2026, 9, 13, 20)),
            (".+2h", date(2026, 9, 12, 10, 30), date(2026, 9, 1, 20), date(2026, 9, 12, 12, 30)),
            (".+1m", date(2026, 1, 31, 10), date(2025, 8, 1, 9), date(2026, 2, 28, 9))
        ]
        for (token, completion, base, expected) in cases {
            let repeater = try XCTUnwrap(OrgRepeater(token))
            XCTAssertEqual(repeater.nextDate(afterCompletion: completion, from: base, calendar: calendar),
                           expected, "\(token), base=\(base), completion=\(completion)")
        }
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
