import XCTest
@testable import Orgenda

@MainActor
final class OrgHeadingMoveTests: XCTestCase {
    private func parsed(_ source: String) throws -> ParsedOrgDocument {
        try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "tasks.org", title: "Tasks", contents: source, kind: .org)
        ]).first)
    }

    private func move(_ source: String, from: Int, to: Int,
                      placement: OrgHeadingPlacement) throws -> String {
        let document = try parsed(source)
        let headings = document.root.children.filter { $0.type == "heading" }
        let plan = try XCTUnwrap(OrgHeadingMove.plan(in: document, headingID: headings[from].id,
                                                   targetID: headings[to].id, placement: placement))
        return try plan.mutation.applied(to: source)
    }

    func testNestsSubtreeWithoutChangingBodyBlocksOrRelativeDepth() throws {
        let a = "* TODO Alpha\n:PROPERTIES:\n:ID: a\n:END:\nBody \u{4e2d}\u{6587}\n"
            + "** Child\n#+BEGIN_SRC text\n* Literal\n#+END_SRC\n**** Deep\n- [ ] Keep\n"
        let b = "* Beta\nParent body\n** Existing\nExisting body\n"
        let nested = "** TODO Alpha\n:PROPERTIES:\n:ID: a\n:END:\nBody \u{4e2d}\u{6587}\n"
            + "*** Child\n#+BEGIN_SRC text\n* Literal\n#+END_SRC\n***** Deep\n- [ ] Keep\n"
        XCTAssertEqual(try move(a + b, from: 0, to: 3, placement: .child), b + nested)
        XCTAssertEqual(try move(b + a, from: 2, to: 0, placement: .child), b + nested)
    }

    func testEveryReparentingPreservesHeadingSourceRangesAndDestinationLevel() throws {
        for newline in ["\n", "\r\n"] {
            let source = ["#+TITLE: Test", "* TODO A", "Body", "** TODO B", "Body B",
                          "*** TODO C", "* TODO D", "Body D", "** TODO E", "Body E"]
                .joined(separator: newline)
            let document = try parsed(source)
            let sections = OrgHeadingSection.sections(in: document)
            for from in sections {
                for to in sections where !(from.startByte..<from.endByte).contains(to.startByte) {
                    for placement in [OrgHeadingPlacement.before, .after, .child] {
                        guard let plan = OrgHeadingMove.plan(in: document, headingID: from.id,
                                                            targetID: to.id, placement: placement) else { continue }
                        let result = try parsed(plan.mutation.applied(to: source))
                        XCTAssertEqual(result.headings.count, document.headings.count)
                        for old in document.headings {
                            let new = try XCTUnwrap(result.headings.first { $0.title == old.title })
                            let relocated = plan.relocatedSource(old.source)
                            XCTAssertEqual(relocated.startByte, new.source.startByte)
                            XCTAssertEqual(relocated.endByte, new.source.endByte,
                                           "\(old.title), \(from.id) -> \(to.id), \(placement)")
                        }
                        let moved = try XCTUnwrap(OrgHeadingSection.sections(in: result).first {
                            $0.startByte == plan.relocatedStartByte(from.startByte)
                        })
                        XCTAssertEqual(moved.level, to.level + (placement == .child ? 1 : 0))
                        if placement == .child {
                            let parent = try XCTUnwrap(result.root.children.first {
                                $0.type == "heading" && $0.startByte == plan.relocatedStartByte(to.startByte)
                            })
                            XCTAssertEqual(moved.parentID, parent.id)
                        }
                    }
                }
            }
        }
    }

    func testStoreRejectsStaleSnapshotIncludingCanonicallyEqualUnicode() throws {
        let original = "* Caf\u{e9}\nBody\n* Other\n"
        let document = try parsed(original)
        let headings = document.root.children.filter { $0.type == "heading" }
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: document.path, title: "Tasks", contents: original, kind: .org)
        ])
        for changed in [original + "New content\n", original.replacingOccurrences(of: "\u{e9}", with: "e\u{301}")] {
            store.documents[0].contents = changed
            XCTAssertNil(store.moveHeading(in: document, headingID: headings[1].id,
                                           targetID: headings[0].id, placement: .before))
            XCTAssertTrue(store.documents[0].contents.utf8.elementsEqual(changed.utf8))
            XCTAssertNotNil(store.operationError)
        }
    }

    func testNestingDuplicateTitlesPreservesIDsAndSupportsImmediateEdit() async throws {
        let source = "* TODO Same\n:PROPERTIES:\n:ID: parent\n:END:\n"
            + "* TODO Same\n:PROPERTIES:\n:ID: child\n:END:\n** TODO Nested\nNested body\n"
        let document = try parsed(source)
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: document.path, title: "Tasks", contents: source, kind: .org)
        ])
        store.parseWorkspace()
        let before = Dictionary(uniqueKeysWithValues: store.items.map { ($0.properties["ID"] ?? $0.title, $0.id) })
        let headings = document.root.children.filter { $0.type == "heading" }
        XCTAssertNotNil(store.moveHeading(in: document, headingID: headings[1].id,
                                          targetID: headings[0].id, placement: .child))
        var child = try XCTUnwrap(store.items.first { $0.properties["ID"] == "child" })
        child.state = .next
        XCTAssertTrue(store.save(child))
        await store.waitForWorkspaceIndex()
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: store.items.map { ($0.properties["ID"] ?? $0.title, $0.id) }), before)
        XCTAssertTrue(store.documents[0].contents.contains("\n** NEXT Same\n"))
        XCTAssertTrue(store.documents[0].contents.hasSuffix("*** TODO Nested\nNested body\n"))
        XCTAssertTrue(store.documents[0].contents.hasPrefix("* TODO Same\n"))
    }

}
