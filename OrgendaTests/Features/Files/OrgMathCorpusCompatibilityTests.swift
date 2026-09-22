import SwiftUI
import SwiftMath
import XCTest
@testable import Orgenda

@MainActor
final class OrgMathCorpusCompatibilityTests: XCTestCase {
    func testUnicodeScriptsAndOperatorsAreNotSilentlyDiscarded() throws {
        let source = #"J₁₂ + a^{−1} + T₂ + \sigma ∖ \chi + T(•) = × + Γ + \rightarrow^∗"#
        let normalized = OrgMathRendering.compatibleLatex(source)
        XCTAssertTrue(normalized.contains("J_{12}"))
        XCTAssertTrue(normalized.contains("a^{-1}"))
        XCTAssertTrue(normalized.contains(#"\setminus{}"#))
        XCTAssertTrue(normalized.contains(#"\times{}"#))
        XCTAssertTrue(normalized.contains(#"\Gamma{}"#))
        XCTAssertTrue(normalized.contains(#"\rightarrow^\ast{}"#))
        let list = try parse(source)
        XCTAssertEqual(list.atoms.first?.subScript?.atoms.map(\.nucleus).joined(), "12")
        try assertRendered(source)
    }

    func testUnicodeInTextRetainsTextSemantics() throws {
        let source = #"\text{编号 T₁ 与 Γ} + J₁"#
        let normalized = OrgMathRendering.compatibleLatex(source)
        XCTAssertTrue(normalized.contains(#"\text{编号 T₁ 与 Γ}"#))
        XCTAssertTrue(normalized.hasSuffix("J_{1}"))
        let list = try parse(source)
        XCTAssertTrue(list.atoms.map(\.nucleus).joined().contains("编号 T₁ 与 Γ"), "Text-mode Unicode must remain in the actual atom list")
        try assertRendered(source)
    }

    func testExactSymbolsKeepTheirGlyphAndAtomClass() throws {
        let list = try parse(#"\llbracket T \rrbracket \Coloneqq S \rightharpoonup U \vDash V"#)
        XCTAssertEqual(list.atoms[0].nucleus, "⟦")
        XCTAssertEqual(list.atoms[0].type, .open)
        XCTAssertEqual(list.atoms[2].nucleus, "⟧")
        XCTAssertEqual(list.atoms[2].type, .close)
        XCTAssertEqual(list.atoms[3].nucleus, "∷=")
        XCTAssertEqual(list.atoms[3].type, .relation)
        XCTAssertTrue(list.atoms.contains { $0.nucleus == "⇀" && $0.type == .relation })
        XCTAssertTrue(list.atoms.contains { $0.nucleus == "⊨" && $0.type == .relation })
        try assertRendered(#"\llbracket T \rrbracket \Coloneqq S \rightharpoonup U \vDash V"#)
    }

    func testCommonAliasesAndNegationRetainMeaning() throws {
        let source = #"\exist i. a_1 + \dots + a_n \plusmn 1, \{1, 2, \dots, n\}, T \not\lt : U"#
        let normalized = OrgMathRendering.compatibleLatex(source)
        XCTAssertTrue(normalized.contains(#"\exists"#))
        XCTAssertTrue(normalized.contains(#"\cdots{}"#))
        XCTAssertTrue(normalized.contains(#"\ldots{}"#))
        XCTAssertTrue(normalized.contains(#"\pm"#))
        XCTAssertTrue(normalized.contains(#"\nless{}"#))
        try assertRendered(source)
        // Literal escaped control words and longer names must not be rewritten.
        XCTAssertEqual(OrgMathRendering.compatibleLatex(#"\\dots \dotsCustom"#), #"\\dots \dotsCustom"#)
        XCTAssertEqual(OrgMathRendering.compatibleLatex(#"\Sigma*"#), #"\Sigma{}*"#)
        XCTAssertEqual(OrgMathRendering.compatibleLatex(#"\$"#), #"\$"#)
    }

    func testEquationTagsRemainVisibleIncludingNestedLabels() throws {
        let source = #"t \rightarrow t' \tag{E-\text{If}-True}"#
        let normalized = OrgMathRendering.compatibleLatex(source)
        XCTAssertTrue(normalized.contains(#"\qquad\text{(E\orgendaHyphen{}\text{If}\orgendaHyphen{}True)}"#))
        let list = try parse(source)
        let glyphs = list.atoms.map(\.nucleus).joined()
        XCTAssertTrue(glyphs.contains("(E-If-True)"))
        XCTAssertEqual(OrgMathRendering.compatibleLatex(#"x \tag*{A}"#), #"x \qquad\text{A}"#)
        try assertRendered(source)
    }

    func testAlignedAtAndHomogeneousArrayKeepCellsAndAlignment() throws {
        let source = #"\begin{alignat*}{2}a&=b&c&=d\\x&=y&z&=w\end{alignat*}"#
        let table = try XCTUnwrap(try parse(source).atoms.first as? MTMathTable)
        XCTAssertEqual(table.cells.count, 2)
        XCTAssertEqual(table.cells[0].count, 4)
        XCTAssertEqual(table.alignments, [.right, .left, .right, .left])
        let array = #"\left\{\begin{array}{ll}0,&x<0\\1,&x\geq0\end{array}\right."#
        XCTAssertTrue(OrgMathRendering.compatibleLatex(array).contains(#"\begin{matrix*}[l]"#))
        try assertRendered(source)
        try assertRendered(array)
        XCTAssertEqual(OrgMathRendering.compatibleLatex(#"\begin{array}{r|l}a&b\end{array}"#), #"\begin{array}{r|l}a&b\end{array}"#)
    }

    func testAnnotatedRelationsKeepUpperAndLowerLabels() throws {
        let arrow = #"\xRightarrow[G_i]{\text{step}}"#
        let list = try parse(arrow)
        let atom = try XCTUnwrap(list.atoms.first as? MTLargeOperator)
        XCTAssertEqual(atom.nucleus, "⟹")
        XCTAssertTrue(atom.limits)
        XCTAssertEqual(atom.superScript?.atoms.map(\.nucleus).joined(), "step")
        XCTAssertEqual(atom.subScript?.atoms.first?.nucleus, "G")
        XCTAssertEqual(atom.subScript?.atoms.first?.subScript?.atoms.first?.nucleus, "i")
        let definition = try parse(#"\overset{\text{def}}{=}"#)
        let relation = try XCTUnwrap(definition.atoms.first as? MTLargeOperator)
        XCTAssertEqual(relation.nucleus, "=")
        XCTAssertEqual(relation.superScript?.atoms.map(\.nucleus).joined(), "def")
        try assertRendered(arrow)
        try assertRendered(#"t \overset{\text{def}}{=} u"#)
        try assertRendered(#"\overset{\text{gc}}{\rightarrow}^{*}"#)
    }

    func testMathInsideTextSwitchesModesWithoutLeakingDollarsOrDroppingScripts() throws {
        let source = #"\text{if $Y₁ \in \chi₁$; fee \$5}"#
        let list = try parse(source)
        XCTAssertEqual(list.atoms.filter { $0.nucleus == "$" }.count, 1, "Only the escaped price marker is literal")
        let variable = try XCTUnwrap(list.atoms.first { $0.nucleus == "Y" })
        XCTAssertEqual(variable.subScript?.atoms.first?.nucleus, "1")
        XCTAssertTrue(list.atoms.contains { $0.nucleus == "∈" && $0.type == .relation })
        try assertRendered(source)
        try assertRendered(#"\text{outer \text{inner $x_1$} text}"#)
        try assertRendered(#"x = y \tag{Rule-$T₁$}"#)
        XCTAssertNil(render(#"\text{unclosed $x}"#))
    }

    func testNegatedArrowAndEscapedAmpersandRetainTheirSymbols() throws {
        let list = try parse(#"\lambda_\& \nrightarrow"#)
        XCTAssertEqual(list.atoms.first?.subScript?.atoms.first?.nucleus, "&")
        XCTAssertEqual(list.atoms.last?.nucleus, "↛")
        XCTAssertEqual(list.atoms.last?.type, .relation)
        try assertRendered(#"\lambda_\& \nrightarrow"#)
        try assertRendered(#"\begin{aligned}\text{A\&B} &= x\end{aligned}"#)
        XCTAssertEqual(OrgMathRendering.compatibleLatex(#"\\&"#), #"\\&"#)
    }

    func testRaisedSubtypeRelationPreservesBothPunctuationMarks() throws {
        let source = #"T = \forall X \mathrel{{\raisebox{0.1ex}{\scriptsize$<$}}\!\colon} T_1. T_2"#
        let list = try parse(source)
        XCTAssertTrue(list.atoms.contains { $0.nucleus == "<:" && $0.type == .relation })
        try assertRendered(source)
    }

    func testUnsupportedStructuresAndOverescapedSourceAreNotSilentlySimplified() {
        for source in [#"\underbrace{S S}_{2}"#, #"\cancel{x}"#, #"\overset{n}{\frac{a}{b}}"#] {
            XCTAssertEqual(OrgMathRendering.compatibleLatex(source), source)
            XCTAssertNil(render(source), source)
        }
        let malformed = #"A = \\{1, 2\\}"#
        XCTAssertEqual(OrgMathRendering.compatibleLatex(malformed), malformed)
        XCTAssertNil(render("a ♜ b"), "Unknown math symbols must not disappear while reporting rendering success")
    }

    private func parse(_ source: String) throws -> MTMathList {
        var error: NSError?
        let list = MTMathListBuilder.build(fromString: OrgMathRendering.compatibleLatex(source), error: &error)
        XCTAssertNil(error, source)
        return try XCTUnwrap(list, source)
    }

    private func render(_ source: String) -> OrgMathCacheEntry? {
        OrgMathRendering.render(OrgMathExpression(latex: source, original: source, mode: .display),
                                textStyle: .body, dynamicTypeSize: .large, colorScheme: .light)
    }

    private func assertRendered(_ source: String) throws {
        let image = try XCTUnwrap(render(source), source)
        XCTAssertGreaterThan(image.image.size.width, 0)
        XCTAssertGreaterThan(image.image.size.height, 0)
    }
}
