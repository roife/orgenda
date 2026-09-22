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

    func testMovesWholeSubtreeAndPreservesPreambleAndExactBytes() throws {
        let prefix = "#+TITLE: Tasks\n\n"
        let first = """
        * TODO First :project:
        SCHEDULED: <2026-09-20 Sun +1w>
        :PROPERTIES:
        :ID: first
        :END:
        Body \u{4e2d}\u{6587} \u{1f600}
        - [ ] Checklist
        ** Child
        #+BEGIN_SRC text
        * Not a heading
        #+END_SRC
        *** Grandchild
        :LOGBOOK:
        Private note
        :END:


        """
        let second = "* Second\nOther body\n** Other child\nChild body\n"
        let third = "* Third\nTail\n"
        let source = prefix + first + second + third
        XCTAssertEqual(try move(source, from: 0, to: 3, placement: .after),
                       prefix + second + first + third)
        XCTAssertEqual(try move(source, from: 3, to: 0, placement: .before),
                       prefix + second + first + third)
    }

    func testReordersChildrenWithoutMovingParentOrChangingLevels() throws {
        let prefix = "* Parent\nParent body\n"
        let first = "** First\nOwn body\n*** Child\nNested body\n"
        let second = "** Second\nSecond body\n"
        let suffix = "* Next parent\n"
        XCTAssertEqual(try move(prefix + first + second + suffix, from: 1, to: 3, placement: .after),
                       prefix + second + first + suffix)
    }

    func testRejectsSelfDescendantsAndNoOp() throws {
        let document = try parsed("* Parent\n** Child\n** Sibling\n* Other\n** Cousin\n")
        let headings = document.root.children.filter { $0.type == "heading" }
        for (from, to, placement) in [(0, 0, OrgHeadingPlacement.before), (0, 1, .after),
                                      (0, 1, .child), (1, 2, .before), (2, 1, .after)] {
            XCTAssertNil(OrgHeadingMove.plan(in: document, headingID: headings[from].id,
                                            targetID: headings[to].id, placement: placement))
        }
        XCTAssertNil(OrgHeadingMove.plan(in: document, headingID: "missing",
                                        targetID: headings[0].id, placement: .before))
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

    func testMovesAcrossParentsAndPromotesWholeSubtree() throws {
        let source = "* A\n** First\nFirst body\n*** Nested\nNested body\n* B\n** Second\nSecond body\n* C\n"
        XCTAssertEqual(try move(source, from: 1, to: 4, placement: .before),
                       "* A\n* B\n** First\nFirst body\n*** Nested\nNested body\n** Second\nSecond body\n* C\n")
        XCTAssertEqual(try move(source, from: 1, to: 0, placement: .after),
                       "* A\n* First\nFirst body\n** Nested\nNested body\n* B\n** Second\nSecond body\n* C\n")
        XCTAssertEqual(try move(source, from: 1, to: 0, placement: .before),
                       "* First\nFirst body\n** Nested\nNested body\n* A\n* B\n** Second\nSecond body\n* C\n")
        XCTAssertEqual(try move("* A\n* B\n", from: 1, to: 0, placement: .child), "* A\n** B\n")
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

    func testDropZonesSeparateNestingFromReorderingAndAllowCrossParentMoves() throws {
        let bounds = CGRect(x: 48, y: 8, width: 240, height: 28)
        XCTAssertEqual(OrgHeadingDropZone.placement(at: 10, titleBounds: bounds), .before)
        XCTAssertEqual(OrgHeadingDropZone.placement(at: 22, titleBounds: bounds), .child)
        XCTAssertEqual(OrgHeadingDropZone.placement(at: 35, titleBounds: bounds), .after)
        XCTAssertEqual(OrgHeadingDropZone.placement(at: 70, titleBounds: bounds), .after)
        let rows = OrgPreviewOutline.rows(from: try parsed("* A\n** B\n* C\n** D\n").root.children)
            .filter { $0.headingLevel != nil }
        func accepts(_ source: Int, _ target: Int) -> Bool {
            OrgHeadingDropZone.accepts(headingID: rows[source].id, targetID: rows[target].id,
                                      parentHeadingIDs: rows[target].parentHeadingIDs)
        }
        XCTAssertFalse(accepts(0, 1))
        XCTAssertFalse(accepts(0, 0))
        XCTAssertTrue(accepts(1, 3))
        XCTAssertTrue(accepts(1, 0))
    }

    func testAllSiblingPermutationsAndByteMappings() throws {
        let prefix = "#+TITLE: Reorder\n"
        let blocks = ["* TODO A\nBody A\n", "* TODO B\n** TODO Child\nBody B\n",
                      "* TODO C\nBody C\n", "* TODO D\nBody D\n"]
        let document = try parsed(prefix + blocks.joined())
        let headings = document.root.children.filter { $0.type == "heading" && $0.text.hasPrefix("* ") }
        for from in headings.indices {
            for to in headings.indices where from != to {
                for placement in [OrgHeadingPlacement.before, .after] {
                    var expected = blocks
                    let moved = expected.remove(at: from)
                    let target = to - (from < to ? 1 : 0) + (placement == .after ? 1 : 0)
                    expected.insert(moved, at: target)
                    let plan = OrgHeadingMove.plan(in: document, headingID: headings[from].id,
                                                  targetID: headings[to].id, placement: placement)
                    if expected == blocks { XCTAssertNil(plan); continue }
                    let move = try XCTUnwrap(plan)
                    let contents = try move.mutation.applied(to: document.root.text)
                    XCTAssertEqual(contents, prefix + expected.joined())
                    let after = try parsed(contents)
                    for heading in document.headings {
                        let relocated = move.relocatedSource(heading.source)
                        let actual = try XCTUnwrap(after.headings.first { $0.title == heading.title })
                        XCTAssertEqual(relocated.startByte, actual.source.startByte)
                        XCTAssertEqual(relocated.endByte, actual.source.endByte)
                    }
                }
            }
        }
    }

    func testCRLFAndUnterminatedFinalSubtree() throws {
        let first = "* TODO A\r\nBody A\r\n"
        let second = "* TODO B\r\nBody B"
        XCTAssertEqual(try move(first + second, from: 1, to: 0, placement: .before),
                       second + "\r\n" + first)
        XCTAssertEqual(try move(first + second, from: 0, to: 1, placement: .after),
                       second + "\r\n" + first)
        XCTAssertEqual(try move("* A\n* B", from: 1, to: 0, placement: .before), "* B\n* A\n")
    }

    func testStorePreservesDuplicateItemIdentityAndRebasedEditing() async throws {
        let first = "* TODO Same\n:PROPERTIES:\n:ID: first\n:END:\nFirst body\n"
        let second = "* TODO Same\n:PROPERTIES:\n:ID: second\n:END:\nSecond body"
        let document = try parsed(first + second)
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: document.path, title: "Tasks", contents: document.root.text, kind: .org)
        ])
        store.parseWorkspace()
        let before = Dictionary(uniqueKeysWithValues: store.items.map { ($0.properties["ID"]!, $0.id) })
        let headings = document.root.children.filter { $0.type == "heading" }
        XCTAssertNotNil(store.moveHeading(in: document, headingID: headings[1].id,
                                          targetID: headings[0].id, placement: .before))
        XCTAssertEqual(store.documents[0].contents, second + "\n" + first)
        let moved = try XCTUnwrap(store.items.first { $0.properties["ID"] == "second" })
        XCTAssertEqual(moved.source.startByte, 0)
        XCTAssertEqual(moved.source.endByte, second.utf8.count + 1)
        await store.waitForWorkspaceIndex()
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: store.items.map { ($0.properties["ID"]!, $0.id) }), before)
        var draft = try XCTUnwrap(store.items.first { $0.properties["ID"] == "second" })
        draft.title = "Moved"
        XCTAssertTrue(store.save(draft))
        await store.waitForWorkspaceIndex()
        XCTAssertTrue(store.documents[0].contents.hasPrefix("* TODO Moved\n"))
        XCTAssertTrue(store.documents[0].contents.hasSuffix(first))
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

    func testInvalidDropDoesNotReuseUnrelatedOperationError() throws {
        let document = try parsed("* A\n** Child\n* B\n")
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: document.path, title: "Tasks", contents: document.root.text, kind: .org)
        ])
        let headings = document.root.children.filter { $0.type == "heading" }
        store.operationError = "An earlier operation failed."
        XCTAssertNil(store.moveHeading(in: document, headingID: headings[0].id,
                                       targetID: headings[1].id, placement: .after))
        XCTAssertNil(store.operationError)
        XCTAssertEqual(store.documents[0].contents, document.root.text)
    }

    func testHeadingContinuityPreservesSelectionsAcrossOutlineReparenting() throws {
        let document = try parsed("* A\n** Child\nA body\n* B\n** Child\nB body\n")
        let nodes = document.root.children.filter { $0.type == "heading" }
        let move = try XCTUnwrap(OrgHeadingMove.plan(in: document, headingID: nodes[0].id,
                                                   targetID: nodes[2].id, placement: .child))
        let updated = try parsed(move.mutation.applied(to: document.root.text))
        let after = updated.root.children.filter { $0.type == "heading" }
        XCTAssertEqual(OrgHeadingContinuity.remap([nodes[0].id, nodes[1].id], from: document,
                                                  to: updated, move: move), [after[2].id, after[3].id])
        XCTAssertEqual(OrgHeadingContinuity.remap([nodes[2].id, nodes[3].id], from: document,
                                                  to: updated, move: move), [after[0].id, after[1].id])
        let edited = try parsed(document.root.text.replacingOccurrences(of: "A body", with: "Longer body"))
        XCTAssertEqual(OrgHeadingContinuity.remap([nodes[2].id], from: document, to: edited, move: move),
                       [edited.root.children.filter { $0.type == "heading" }[2].id])
    }

    func testFilteredOutlineMoveIncludesHiddenChildrenAndRebuildsTree() async throws {
        let first = "* TODO Visible\nBody\n** DONE Hidden child\nHidden body\n"
        let second = "* TODO Target\nTarget body\n"
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: "tasks.org", title: "Tasks", contents: first + second, kind: .org)
        ])
        store.parseWorkspace()
        let document = try XCTUnwrap(store.parsedDocuments["tasks.org"])
        var filter = DocumentOutlineFilter()
        filter.states = [.todo]
        let outline = filter.apply(to: DocumentOutlineNode.tree(from: document.root.children, items: store.items))
        XCTAssertEqual(outline.count, 2)
        XCTAssertTrue(outline[0].children.isEmpty)
        XCTAssertNotNil(store.moveHeading(in: document, headingID: outline[0].id,
                                          targetID: outline[1].id, placement: .child))
        await store.waitForWorkspaceIndex()
        let updated = try XCTUnwrap(store.parsedDocuments["tasks.org"])
        let tree = DocumentOutlineNode.tree(from: updated.root.children, items: store.items)
        XCTAssertEqual(tree.map(\.title), ["Target"])
        XCTAssertEqual(tree[0].children.map(\.title), ["Visible"])
        XCTAssertEqual(tree[0].children[0].children.map(\.title), ["Hidden child"])
        XCTAssertEqual(store.documents[0].contents,
                       second + "** TODO Visible\nBody\n*** DONE Hidden child\nHidden body\n")
        XCTAssertEqual(updated.root.text, store.documents[0].contents)
    }
}
