import SwiftUI
import XCTest
@testable import Orgenda

@MainActor
final class OrgPreviewContainerMathTests: XCTestCase {
    func testIndentedAlignmentTokensDoNotBreakDisplayFormula() throws {
        let source = "\\begin{aligned}\n    a &= b \\\\\n    c &= d\n\\end{aligned}\n"
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "indent.org", title: "Indent", contents: source, kind: .org)
        ]).first)
        let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: document.root.children))
        let blocks = rows.filter { $0.node.type == "math_block" }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(rows.map(\.node.text).joined(), source)
        let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: try XCTUnwrap(blocks.first).node.text))
        XCTAssertNotNil(OrgMathRendering.render(expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light))
    }

    func testUnclosedInlineFormulaDoesNotSwallowNextParagraph() {
        let source = "损坏 \\(M(Q)\n\n\\[F = \\{q\\}\\]\n\n之后 \\(L(M)\\)"
        XCTAssertEqual(OrgMathParser.matches(in: source).map(\.expression.original), [#"\[F = \{q\}\]"#, #"\(L(M)\)"#])
    }

    func testTableCellsExtractFormulaImagesAlongsideLabelsAndLinks() throws {
        let source = #"""
        | proposition \(P \supset Q\) | type \(P \rightarrow Q\) |
        | [[https://example.com][Reference]] | \(\alpha\) |
        """# + "\n"
        let table = try XCTUnwrap(try nodes(source).first { $0.type == "table" })
        let cells = table.children.flatMap(\.children).filter { $0.type == "table_cell" }
        XCTAssertEqual(cells.count, 4)
        let fragments = cells.flatMap { OrgPreviewMarkup.fragments($0, trimSpaces: true) }
        XCTAssertEqual(math(fragments).map(\.latex), [#"P \supset Q"#, #"P \rightarrow Q"#, #"\alpha"#])
        XCTAssertTrue(text(fragments).contains("proposition"))
        XCTAssertTrue(text(fragments).contains("Reference"))
        XCTAssertTrue(fragments.contains { fragment in
            guard case .text(let value) = fragment else { return false }
            return value.runs.contains { $0.link?.absoluteString == "https://example.com" }
        })
        try assertRendered(math(fragments))
    }

    func testQuoteBodyKeepsInlineMathAndGroupsMultilineDisplayMath() throws {
        let source = #"""
        前言🙂
        #+begin_quote
        If \(t\) is an \(n\)-term.

        \[
        \alpha

        + \beta
        \]

        *After* the formula.
        #+end_quote
        """# + "\n"
        let block = try XCTUnwrap(try nodes(source).first { $0.type == "quote_block" })
        let fragments = OrgPreviewContainerMath.blockFragments(block)
        XCTAssertEqual(math(fragments).map(\.mode), [.inline, .inline, .display])
        XCTAssertTrue(math(fragments).last?.latex.contains("\n\n") == true)
        XCTAssertFalse(text(fragments).contains("#+begin_quote"))
        XCTAssertFalse(text(fragments).contains("#+end_quote"))
        XCTAssertEqual(segmentKinds(fragments), ["inline", "display", "inline"])
        XCTAssertTrue(fragments.contains { fragment in
            guard case .text(let value) = fragment else { return false }
            return value.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        })
        try assertRendered(math(fragments))
    }

    func testVerseAndCenterPreserveIndentationAndSeparateDisplayExpressions() throws {
        for name in ["verse", "center"] {
            let source = "#+begin_\(name)\n  First \\(x\\)\n\\[\n\\alpha\n\\]\n\\[\\beta\\]\n  Last\n#+end_\(name)\n"
            let block = try XCTUnwrap(try nodes(source).first { $0.type == "\(name)_block" })
            let fragments = OrgPreviewContainerMath.blockFragments(block)
            XCTAssertEqual(math(fragments).map(\.mode), [.inline, .display, .display], name)
            XCTAssertEqual(segmentKinds(fragments), ["inline", "display", "display", "inline"], name)
            let segments = OrgPreviewContainerMath.segments(fragments)
            guard let firstSegment = segments.first, let lastSegment = segments.last,
                  case .inline(let first) = firstSegment,
                  case .inline(let last) = lastSegment else {
                return XCTFail("Expected surrounding prose for \(name)")
            }
            XCTAssertTrue(text(first).hasPrefix("  First"), name)
            XCTAssertEqual(text(last), "  Last", name)
            try assertRendered(math(fragments))
        }
    }

    func testFootnoteFormulaIsExtractedWithoutTreatingMarkerAsMath() throws {
        let node = try XCTUnwrap(try nodes(#"[fn:proof] Therefore \(\alpha = \beta\)."# + "\n")
            .first { $0.type == "footnote_definition" })
        let fragments = OrgPreviewMarkup.fragments(node)
        XCTAssertEqual(math(fragments).map(\.latex), [#"\alpha = \beta"#])
        XCTAssertTrue(text(fragments).hasPrefix("[proof] "))
        try assertRendered(math(fragments))
    }

    func testEmptyBodyDoesNotExposeBlockDelimiters() throws {
        for name in ["quote", "verse", "center"] {
            let block = try XCTUnwrap(try nodes("#+begin_\(name)\n#+end_\(name)\n").first)
            XCTAssertTrue(OrgPreviewContainerMath.blockFragments(block).isEmpty)
        }
    }

    func testDisplayMathCanCrossListAndTableShapedSyntax() throws {
        let source = #"""
        - Application: \[
          t = t_1 t_2
          \]

        \begin{alignat*}{2}
        T = {}& l_1 \\
        |\ & l_2
        \end{alignat*}

            \[[q, A, p] \Rightarrow a[q_1, A_1, q_2]\]
        """# + "\n"
        let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: try nodes(source)))
        let formulas = rows.filter { $0.node.type == "math_block" }
        XCTAssertEqual(formulas.count, 3)
        XCTAssertEqual(rows.map(\.node.text).joined(), source)
        let list = try XCTUnwrap(rows.first { $0.node.type == "list_item" })
        let content = try XCTUnwrap(list.node.child(ofType: "list_item_content"))
        XCTAssertEqual(text(OrgPreviewMarkup.fragments(content, trimSpaces: true)), "Application:")
        XCTAssertTrue(formulas[1].node.text.contains("|\\ & l_2"))
        XCTAssertTrue(formulas[2].node.text.hasPrefix(#"\[[q"#))
    }

    func testMultilineInlineFormulaStaysWithSurroundingParagraphText() throws {
        let source = #"""
        中文 \(x\), then \( P: \sigma \rightarrow \sigma
        \) after.

          For \(\alpha = \begin{cases}
          x & x > 0 \\
          0 & x \le 0
          \end{cases}\), continue.
        """# + "\n"
        let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: try nodes(source)))
        let paragraphs = rows.filter { $0.node.type == "paragraph" }
        let fragments = paragraphs.flatMap { OrgPreviewMarkup.fragments($0.node) }
        XCTAssertEqual(math(fragments).count, 3)
        XCTAssertTrue(math(fragments).allSatisfy { $0.mode == .inline })
        XCTAssertTrue(math(fragments)[1].latex.contains("\n"))
        XCTAssertTrue(math(fragments)[2].latex.contains(#"\begin{cases}"#))
        XCTAssertEqual(rows.map(\.node.text).joined(), source)
        XCTAssertTrue(text(OrgPreviewMarkup.fragments(paragraphs[0].node)).hasSuffix(" after."))
    }

    func testLiteralFormulaOpenersCannotStealLaterFormulas() throws {
        let source = #"""
        =\(literal\)= ~\[unclosed~ {{{macro(\(literal\))}}} [[https://example.com/\(literal\)][Link]] \(real\)
        \(a = b\), then \(c = d\).
        """# + "\n"
        let paragraphs = try nodes(source).filter { $0.type == "paragraph" }
        let fragments = paragraphs.flatMap { OrgPreviewMarkup.fragments($0) }
        XCTAssertEqual(math(fragments).map(\.latex), ["real", "a = b", "c = d"])
        XCTAssertTrue(text(fragments).contains(#"\(literal\)"#))
        XCTAssertTrue(text(fragments).contains(#"\[unclosed"#))
    }

    func testPseudocodeDollarPairsAllowSuffixesAndTrailingPadding() {
        let source = #"\state set $bb$s in $func$; $worklist \gets [($entry $bb$; $same \gets $ next $phi$"#
        XCTAssertEqual(OrgMathParser.matches(in: source).map(\.expression.original), [
            "$bb$", "$func$", #"$worklist \gets [($"#, "$bb$", #"$same \gets $"#, "$phi$"
        ])
        XCTAssertTrue(OrgMathParser.matches(in: #"Costs US$5 or \$6, with $unfinished math."#).isEmpty)
        XCTAssertTrue(OrgMathParser.matches(in: "$5 and $6").isEmpty)
    }

    func testIncompleteInlineMathDoesNotConsumeAnotherParagraph() {
        let source = "\\( unfinished\n\nNext \\(valid\\)"
        XCTAssertEqual(OrgMathParser.matches(in: source).map(\.expression.latex), ["valid"])
    }

    func testOrdinaryContainersRemainIntactAndCaptionMathIsAvailable() throws {
        let source = "| Label | \\(x\\) |\n- Inline \\(y\\)\n#+caption: Full \\( F_{<:} \\)\n"
        let parsed = try nodes(source)
        let rows = OrgPreviewOutline.rows(from: parsed)
        XCTAssertEqual(OrgPreviewMathRows.group(rows).map(\.node), rows.map(\.node))
        let caption = try XCTUnwrap(parsed.first { $0.type == "keyword" }?.child(ofType: "keyword_value"))
        XCTAssertEqual(math(OrgPreviewMarkup.fragments(caption, trimSpaces: true)).map(\.latex), [" F_{<:} "])
    }

    private func nodes(_ source: String) throws -> [ParsedOrgNode] {
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "container-math.org", title: "Container Math", contents: source, kind: .org)
        ]).first)
        return document.root.children
    }

    private func math(_ fragments: [OrgPreviewInlineFragment]) -> [OrgMathExpression] {
        fragments.compactMap { fragment in
            guard case .math(let expression) = fragment else { return nil }
            return expression
        }
    }

    private func text(_ fragments: [OrgPreviewInlineFragment]) -> String {
        fragments.compactMap { fragment in
            guard case .text(let value) = fragment else { return nil }
            return String(value.characters)
        }.joined()
    }

    private func segmentKinds(_ fragments: [OrgPreviewInlineFragment]) -> [String] {
        OrgPreviewContainerMath.segments(fragments).map { segment in
            switch segment {
            case .inline: "inline"
            case .display: "display"
            }
        }
    }

    private func assertRendered(_ expressions: [OrgMathExpression]) throws {
        for expression in expressions {
            let rendered = try XCTUnwrap(OrgMathRendering.render(
                expression, textStyle: .subheadline, dynamicTypeSize: .large, colorScheme: .light
            ), expression.original)
            XCTAssertGreaterThan(rendered.image.size.width, 0)
            XCTAssertGreaterThan(rendered.image.size.height, 0)
        }
    }
}
