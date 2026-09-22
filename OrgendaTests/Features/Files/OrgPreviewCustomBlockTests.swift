import XCTest
@testable import Orgenda

@MainActor
final class OrgPreviewCustomBlockTests: XCTestCase {
    func testCustomPairKeepsTitleExactSourceAndUnicodeByteOffsets() throws {
        let prefix = "前言🙂\n\n"
        let blockSource = "#+BeGiN_Advice :title 使用说明\n中文 *重点*\n#+eNd_aDvIcE\n"
        let source = prefix + blockSource + "After\n"
        let nodes = try parsedNodes(source)
        let block = try XCTUnwrap(OrgPreviewCustomBlocks.group(nodes).first { $0.type == "custom_block" })

        XCTAssertEqual(OrgPreviewCustomBlocks.title(for: block), "Advice :title 使用说明")
        XCTAssertEqual(block.text, blockSource)
        XCTAssertEqual(block.startByte, prefix.utf8.count)
        XCTAssertEqual(block.endByte, (prefix + blockSource).utf8.count)
        XCTAssertEqual(sourceSlice(source, range: block.startByte..<block.endByte), blockSource)
        XCTAssertEqual(block.children.map(\.text), ["中文 *重点*\n"])
        XCTAssertEqual(block.children, nodes.filter {
            $0.startByte >= block.startByte + "#+BeGiN_Advice :title 使用说明\n".utf8.count
                && $0.endByte <= block.endByte - "#+eNd_aDvIcE\n".utf8.count
        })
    }

    func testNestedSameAndDifferentNamesUseNearestMatchingEnd() throws {
        let source = """
        #+begin_note
        Outer
        #+begin_note
        Same name
        #+end_note
        #+begin_tip
        Different name
        #+end_tip
        Tail
        #+end_note
        """ + "\n"
        let grouped = OrgPreviewCustomBlocks.group(try parsedNodes(source))
        let outer = try XCTUnwrap(grouped.first)

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(outer.type, "custom_block")
        XCTAssertEqual(outer.text, source)
        let nested = outer.children.filter { $0.type == "custom_block" }
        XCTAssertEqual(nested.map { OrgPreviewCustomBlocks.title(for: $0) }, ["note", "tip"])
        XCTAssertEqual(nested.map { $0.children.map(\.text).joined() }, ["Same name\n", "Different name\n"])
        XCTAssertEqual(outer.children.last?.text, "Tail\n")
    }

    func testIncompleteMismatchedAndNonExactNamesRemainUnchanged() throws {
        let sources = [
            "#+begin_note\nUnclosed\n",
            "#+end_note\nOrphan end\n",
            "#+begin_note\nWrong name\n#+end_notice\n",
            "#+begin_note\nPrefix is not a match\n#+end_notebook\n",
            "#+begin_note\n#+begin_tip\nCrossed\n#+end_note\n#+end_tip\n",
            "  #+begin_note\nIndented but unclosed\n",
            "#+begin_src_extra\nReserved prefix but unclosed\n",
        ]
        for source in sources {
            let nodes = try parsedNodes(source)
            XCTAssertEqual(OrgPreviewCustomBlocks.group(nodes), nodes, source)
        }
    }

    func testStandardBlocksRemainOpaqueEvenWhenTheyContainCustomDelimiters() throws {
        for name in ["src", "quote", "example", "export", "comment", "verse", "center"] {
            let arguments = name == "src" ? " text" : name == "export" ? " html" : ""
            let source = "#+begin_\(name)\(arguments)\n#+begin_note\nLiteral body\n#+end_note\n#+end_\(name)\n"
            let nodes = try parsedNodes(source)
            XCTAssertEqual(OrgPreviewCustomBlocks.group(nodes), nodes, name)
            XCTAssertTrue(flatten(nodes).allSatisfy { $0.type != "custom_block" }, name)
        }

        let source = "#+begin_note\n#+begin_src text\n#+end_note\n#+end_src\nTail\n#+end_note\n"
        let nodes = try parsedNodes(source)
        let block = try XCTUnwrap(OrgPreviewCustomBlocks.group(nodes).first)
        XCTAssertEqual(block.type, "custom_block")
        XCTAssertEqual(block.text, source)
        XCTAssertEqual(block.children.first { $0.type == "source_block" }, nodes.first { $0.type == "source_block" })
        XCTAssertEqual(block.children.last?.text, "Tail\n")
    }

    func testPairingCannotCrossAHeadingAndValidBlocksKeepTheirHeadingParent() throws {
        let acrossHeading = "#+begin_note\nBefore\n* New section\nAfter\n#+end_note\n"
        let ungrouped = try parsedNodes(acrossHeading)
        XCTAssertEqual(OrgPreviewCustomBlocks.group(ungrouped), ungrouped)

        let source = "* Parent\n** Child\n#+begin_note\nBody\n#+end_note\n* Sibling\n"
        let nodes = try parsedNodes(source)
        let headings = nodes.filter { $0.type == "heading" }
        let rows = OrgPreviewOutline.rows(from: nodes)
        let blockRow = try XCTUnwrap(rows.first { $0.node.type == "custom_block" })
        XCTAssertEqual(blockRow.parentHeadingIDs, Array(headings.prefix(2)).map(\.id))
        XCTAssertEqual(blockRow.parentHeadingLevel, 2)
        XCTAssertNil(blockRow.headingLevel)
        XCTAssertEqual(rows.filter { $0.headingLevel != nil }.map(\.node), headings)
        XCTAssertTrue(rows.filter { $0.headingLevel != nil }.prefix(2).allSatisfy(\.hasDescendants))
        XCTAssertEqual(rows.last?.parentHeadingIDs, [])
    }

    func testIndentedAndReservedPrefixDelimiterFragmentsFormCompleteBlocks() throws {
        let sources = [
            "  #+begin_note :title 提示\n  Body\n  #+end_note\n",
            "#+begin_src_extra\nBody\n#+end_src_extra\n",
        ]
        for source in sources {
            let nodes = try parsedNodes(source)
            let grouped = OrgPreviewCustomBlocks.group(nodes)
            let block = try XCTUnwrap(grouped.first, source)
            XCTAssertEqual(grouped.count, 1, source)
            XCTAssertEqual(block.type, "custom_block", source)
            XCTAssertEqual(block.startByte, 0, source)
            XCTAssertEqual(block.endByte, source.utf8.count, source)
            XCTAssertEqual(block.text, source)
            XCTAssertEqual(block.children.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines), "Body")
        }
    }

    func testInteractiveContentRetainsOriginalNodeIDsAndByteRanges() throws {
        let source = "前言🙂\n#+begin_note\n- [ ] 完成 [[https://example.com][链接]]\nSCHEDULED: <2026-09-22 Tue +1d>\n#+end_note\n"
        let nodes = try parsedNodes(source)
        let original = flatten(nodes).filter { ["checkbox", "link", "planning"].contains($0.type) }
        let block = try XCTUnwrap(OrgPreviewCustomBlocks.group(nodes).first { $0.type == "custom_block" })
        let presented = flatten(block.children)

        XCTAssertFalse(original.filter { $0.type == "checkbox" }.isEmpty)
        XCTAssertFalse(original.filter { $0.type == "link" }.isEmpty)
        XCTAssertFalse(original.filter { $0.type == "planning" }.isEmpty)
        for node in original {
            XCTAssertEqual(presented.first { $0.id == node.id }, node)
            XCTAssertEqual(sourceSlice(source, range: node.startByte..<node.endByte), node.text)
        }
        XCTAssertEqual(try parsedNodes(source), nodes)
    }

    func testAdjacentEmptyAndNonemptyBlocksAtEndOfFileStaySeparate() throws {
        let firstSource = "#+begin_note\n#+end_note\n"
        let lastSource = "#+begin_tip\nBody without a trailing newline after the end marker\n#+end_tip"
        let source = firstSource + lastSource
        let grouped = OrgPreviewCustomBlocks.group(try parsedNodes(source))

        XCTAssertEqual(grouped.map(\.type), ["custom_block", "custom_block"])
        XCTAssertEqual(grouped.map(\.text), [firstSource, lastSource])
        XCTAssertTrue(try XCTUnwrap(grouped.first).children.isEmpty)
        XCTAssertEqual(grouped.last?.endByte, source.utf8.count)
        XCTAssertEqual(grouped.last?.startByte, firstSource.utf8.count)
    }

    private func parsedNodes(_ source: String) throws -> [ParsedOrgNode] {
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "custom-blocks.org", title: "Custom Blocks", contents: source, kind: .org)
        ]).first)
        return document.root.children
    }

    private func flatten(_ nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    private func sourceSlice(_ source: String, range: Range<Int>) -> String {
        String(decoding: Array(source.utf8)[range], as: UTF8.self)
    }
}
