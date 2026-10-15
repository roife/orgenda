import XCTest
@testable import Orgenda

final class OrgWorkflowOperationsTests: XCTestCase {
    func testAmbiguousOrUnclosedDrawerDoesNotWrite() throws {
        for suffix in [":LOGBOOK:\nunfinished\n", ":LOGBOOK:\n:END:\n:LOGBOOK:\n:END:\n"] {
            XCTAssertThrowsError(try OrgWorkflowOperations.applyingLogs(
                to: "* DONE Example\n" + suffix, headingStartByte: 0,
                replacing: item(state: .todo), with: item(state: .done)
            )) { XCTAssertEqual($0 as? OrgWorkflowOperations.Failure, .ambiguousStructure) }
        }
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
