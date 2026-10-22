import XCTest
@testable import Orgenda

final class OrgIncrementalSourceTests: XCTestCase {
    func testDocumentCachesKeepIndependentSnapshotsAndConfiguration() async throws {
        let service = OrgIndexService()
        let first = WorkspaceDocument(path: "a.org", title: "A", contents: "* TODO 中文\n- [ ] first\n", kind: .org)
        let second = WorkspaceDocument(path: "b.org", title: "B", contents: "* TODO 🙂\n- [ ] second\n", kind: .org)
        let initial = await service.parse([first, second])
        let retained = try XCTUnwrap(initial.first)
        var changed = first
        changed.contents = "前言\n" + first.contents.replacingOccurrences(of: "[ ]", with: "[X]")
        _ = await service.parse([changed])
        let secondResult = await service.parse([second])
        XCTAssertEqual(secondResult.first, initial.last)
        XCTAssertEqual(Array(retained.root.text.utf8), Array(first.contents.utf8))
        let reconfigured = await service.parse([second], configuration: .standard)
        XCTAssertEqual(reconfigured.first?.headings,
                       OrgIndexService.parseSynchronously([second], configuration: .standard).first?.headings)
        await service.remove(paths: [first.path])
        let restored = await service.parse([first], configuration: .standard)
        let fresh = OrgIndexService.parseSynchronously([first], configuration: .standard)
        XCTAssertEqual(restored.first?.headings, fresh.first?.headings)
    }

    /// Cached byte ranges are used to write back to source. Every revision must
    /// resolve the same nodes and task fields as a fresh parse, including undo.
    func testCachedRevisionsKeepMutationTargetsAndJournalDatesCurrent() async throws {
        let service = OrgIndexService()
        var outline = OrgPreviewOutline.Cache()
        let original = "#+TODO: OPEN | DONE\n* 2026-10-22\n** 09:00 中文🙂\nBody\n* OPEN Parent\n** OPEN Child\nSCHEDULED: <2026-10-22 Thu>\n- [ ] text\n"
        let revisions = [
            original,
            "前言\n" + original,
            original.replacingOccurrences(of: "2026-10-22", with: "2026-10-23"),
            original.replacingOccurrences(of: "[ ]", with: "[X]"),
            original.replacingOccurrences(of: "Parent", with: "Renamed"),
            original.replacingOccurrences(of: "** OPEN Child", with: "* OPEN Child"),
            original.replacingOccurrences(of: "OPEN | DONE", with: "NEXT | DONE"),
            original.replacingOccurrences(of: "Body\n", with: "#+BEGIN_SRC org\nBody\n"),
            "", original,
        ]
        func signature(_ node: ParsedOrgNode) -> [String] {
            ["\(node.type):\(node.startByte):\(node.endByte):\(Array(node.text.utf8))"] + node.children.flatMap(signature)
        }
        for source in revisions {
            let input = WorkspaceDocument(path: "journal/2026.org", title: "2026", contents: source, kind: .org)
            let parsed = await service.parse([input])
            let cached = try XCTUnwrap(parsed.first)
            let fresh = try XCTUnwrap(OrgIndexService.parseSynchronously([input]).first)
            XCTAssertEqual(signature(cached.root), signature(fresh.root))
            XCTAssertEqual(cached.headings, fresh.headings)
            XCTAssertEqual(cached.journalEntries, fresh.journalEntries)
            let rows = outline.rows(from: cached.root.children)
            let freshRows = OrgPreviewOutline.rows(from: cached.root.children)
            XCTAssertEqual(rows.map(\.node), freshRows.map(\.node))
            XCTAssertEqual(rows.map(\.parentHeadingIDs), freshRows.map(\.parentHeadingIDs))
            if let checkbox = cached.root.descendantsByID.values.first(where: { $0.type == "checkbox" }) {
                let mutation = try OrgSourceMutation.checkboxToggle(in: source, startByte: checkbox.startByte, endByte: checkbox.endByte)
                let modified = try mutation.applied(to: source)
                XCTAssertEqual(Array(modified.utf8.prefix(checkbox.startByte)), Array(source.utf8.prefix(checkbox.startByte)))
                XCTAssertEqual(Array(modified.utf8.dropFirst(checkbox.endByte)), Array(source.utf8.dropFirst(checkbox.endByte)))
            }
        }
    }
}
