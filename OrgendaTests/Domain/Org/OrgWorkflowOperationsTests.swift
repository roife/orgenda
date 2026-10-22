import XCTest
@testable import Orgenda

final class OrgWorkflowOperationsTests: XCTestCase {
    func testAmbiguousOrUnclosedDrawerDoesNotWrite() throws {
        for suffix in [":LOGBOOK:\nunfinished\n", ":LOGBOOK:\n:END:\n:LOGBOOK:\n:END:\n",
                       ":END:\n", "#+BEGIN_SRC org\nunfinished\n", "#+BEGIN_note\n#+END_other\n",
                       ":PROPERTIES:\n:ID: unfinished\n"] {
            XCTAssertThrowsError(try OrgWorkflowOperations.applyingLogs(
                to: "* DONE Example\n" + suffix, headingStartByte: 0,
                replacing: item(state: .todo), with: item(state: .done)
            )) { XCTAssertEqual($0 as? OrgWorkflowOperations.Failure, .ambiguousStructure) }
        }
    }

    func testMovingSubtreePreservesLiteralHeadingsAndCustomBlockControls() throws {
        let blocks = [
            ("#+BEGIN_SRC org", "#+END_SRC"),
            ("  #+BEGIN_QUOTE", "  #+END_QUOTE"),
            ("#+BEGIN_EXAMPLE", "#+END_EXAMPLE"),
            ("#+BEGIN_note", "#+END_note"),
            ("#+BEGIN_note\n#+BEGIN_nested", "#+END_nested\n#+END_note")
        ]
        for newline in ["\n", "\r\n"] {
            for (begin, end) in blocks {
                let literal = [begin, "* Literal 中文🙂", "- [ ] Keep checkbox", end]
                    .joined(separator: "\n").replacingOccurrences(of: "\n", with: newline) + newline
                let subtree = "* TODO Move" + newline + literal + "** Child" + newline + "Body" + newline
                let source = document("agenda/inbox.org", subtree + "* Neighbor" + newline)
                let destination = document("agenda/actions.org", "* Destination" + newline)
                let plan = try OrgWorkflowOperations.move(source: source, headingStartByte: 0,
                                                          destination: destination, targetHeadingStartByte: 0)
                XCTAssertEqual(plan.source.contents, "* Neighbor" + newline)
                XCTAssertEqual(plan.destination.contents, destination.contents + "** TODO Move" + newline
                               + literal + "*** Child" + newline + "Body" + newline)
                let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([plan.destination]).first)
                XCTAssertEqual(parsed.headings.map(\.title), ["Destination", "Move", "Child"])
                if begin.contains("BEGIN_note") {
                    let checkbox = try XCTUnwrap(parsed.root.descendantsByID.values.first { $0.type == "checkbox" })
                    let toggled = try OrgSourceMutation.checkboxToggle(in: plan.destination.contents,
                                                                      startByte: checkbox.startByte, endByte: checkbox.endByte)
                        .applied(to: plan.destination.contents)
                    XCTAssertEqual(toggled, plan.destination.contents.replacingOccurrences(of: "[ ]", with: "[X]"))
                }
            }
        }
    }

    func testArchiveUsesParsedPropertyInheritanceWithoutLiteralOverrides() throws {
        let source = """
        #+PROPERTY: ARCHIVE files.org::* File archive
        #+BEGIN_note
        #+PROPERTY: ARCHIVE wrong.org::* Wrong
        #+END_note
        * Parent
        :PROPERTIES:
        :ARCHIVE: inherited.org::* Parent archive
        :END:
        ** TODO Child
        #+BEGIN_SRC org
        :PROPERTIES:
        :ARCHIVE: wrong.org::* Wrong
        :END:
        #+END_SRC
        * Neighbor
        """ + "\n"
        let child = try OrgWorkflowOperations.archiveDestination(sourcePath: "agenda/inbox.org", source: source,
                                                                 headingStartByte: byteOffset(of: "** TODO Child", in: source))
        XCTAssertEqual(child, OrgArchiveDestination(path: "agenda/inherited.org", outline: "* Parent archive"))
        let neighbor = try OrgWorkflowOperations.archiveDestination(sourcePath: "agenda/inbox.org", source: source,
                                                                    headingStartByte: byteOffset(of: "* Neighbor", in: source))
        XCTAssertEqual(neighbor, OrgArchiveDestination(path: "agenda/files.org", outline: "* File archive"))
    }

    func testLogsPreserveMetadataAndOriginalPlanningRange() throws {
        let source = "* TODO 中文🙂\r\nSCHEDULED: <2026-10-22 Thu +1w -2d>--<2026-10-23 Fri>\r\n"
            + ":PROPERTIES:\r\n:ID: keep\r\n:END:\r\nBody\r\n* Neighbor\r\n"
        var original = item(state: .todo)
        original.scheduled = Date(timeIntervalSince1970: 1_792_627_200)
        var edited = original
        edited.scheduled = original.scheduled!.addingTimeInterval(86400)
        let updated = try OrgWorkflowOperations.applyingLogs(to: source, headingStartByte: 0,
                                                            replacing: original, with: edited, originalSource: source)
        XCTAssertTrue(updated.contains("[2026-10-22 Thu +1w -2d]--[2026-10-23 Fri]"))
        XCTAssertTrue(updated.hasPrefix(source.components(separatedBy: "Body")[0] + ":LOGBOOK:\r\n"))
        XCTAssertTrue(updated.hasSuffix(":END:\r\nBody\r\n* Neighbor\r\n"))
        XCTAssertFalse(updated.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    func testSameFileRefilePreservesNeighborsInBothDirectionsAndWhenAdjacent() throws {
        let cases = [
            ("later target", "** TODO Move",
             "* Inbox\n** TODO Move\nBody\n*** Child\nChild body\n* Destination\nExisting\n* Neighbor\nUntouched\n",
             "* Inbox\n* Destination\nExisting\n** TODO Move\nBody\n*** Child\nChild body\n* Neighbor\nUntouched\n"),
            ("earlier target", "* TODO Move",
             "* Destination\nExisting\n* Middle\nKeep\n* TODO Move\nBody\n",
             "* Destination\nExisting\n** TODO Move\nBody\n* Middle\nKeep\n"),
            ("adjacent target", "* TODO Move",
             "* Destination\nExisting\n* TODO Move\nBody\n",
             "* Destination\nExisting\n** TODO Move\nBody\n")
        ]
        for (name, heading, contents, expected) in cases {
            try XCTContext.runActivity(named: name) { _ in
                let source = document("agenda/actions.org", contents)
                let target = try XCTUnwrap(OrgWorkflowOperations.refileTargets(in: [source]).first { $0.title == "Destination" })
                let plan = try OrgWorkflowOperations.refile(source: source, headingStartByte: byteOffset(of: heading, in: contents), destination: source, target: target)
                XCTAssertEqual(plan.source, plan.destination)
                XCTAssertEqual(plan.source.contents, expected)
            }
        }
    }

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
