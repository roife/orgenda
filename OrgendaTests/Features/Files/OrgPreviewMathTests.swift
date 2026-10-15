import XCTest
@testable import Orgenda

@MainActor
final class OrgPreviewMathTests: XCTestCase {
    func testMathInsideEmphasisBecomesRenderableFragments() throws {
        for marker in ["*", "/", "_", "+"] {
            let fragments = try fragments(in: marker + #"before \(\omega\) and \(\mathtt{sub}(N, N, 9)\) after"# + marker)
            let expressions = math(in: fragments)
            XCTAssertEqual(expressions.map(\.latex), [#"\omega"#, #"\mathtt{sub}(N, N, 9)"#])
            for expression in expressions {
                XCTAssertNotNil(OrgMathRendering.render(
                    expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
                ))
            }
            let text = fragments.compactMap { fragment -> String? in
                guard case .text(let value) = fragment else { return nil }
                for run in value.runs {
                    switch marker {
                    case "*": XCTAssertTrue(run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
                    case "/": XCTAssertTrue(run.inlinePresentationIntent?.contains(.emphasized) == true)
                    case "_": XCTAssertNotNil(run.underlineStyle)
                    default: XCTAssertNotNil(run.strikethroughStyle)
                    }
                }
                return String(value.characters)
            }.joined()
            XCTAssertEqual(text, "before  and  after")
        }
    }

    func testMathRendersInBothColorSchemes() throws {
        let fragments = try fragments(in: #"\(0\) \(\forall a : \neg Sa = 0\) $x² + y₁$"#)
        let expressions = math(in: fragments)
        XCTAssertEqual(expressions.count, 3)
        for expression in expressions {
            let light = try XCTUnwrap(OrgMathRendering.render(
                expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
            ))
            let dark = try XCTUnwrap(OrgMathRendering.render(
                expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .dark
            ))
            XCTAssertEqual(light.image.size, dark.image.size)
            XCTAssertEqual(light.descent, dark.descent)
            XCTAssertTrue(OrgMathRendering.render(
                expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .dark
            ) === dark)
        }
    }

    func testLiteralMathInsideEmphasisRemainsLiteral() throws {
        let fragments = try fragments(in: #"*before =\(literal\)= and \(x\) after*"#)
        XCTAssertEqual(math(in: fragments).map(\.latex), ["x"])
        let text = fragments.compactMap { fragment -> String? in
            guard case .text(let value) = fragment else { return nil }
            return String(value.characters)
        }.joined()
        XCTAssertTrue(text.contains(#"\(literal\)"#))
    }

    func testEmphasisWithoutMathKeepsItsExistingText() throws {
        let fragments = try fragments(in: #"*literal \command and =code=*"#)
        XCTAssertTrue(math(in: fragments).isEmpty)
        XCTAssertEqual(fragments.count, 1)
        guard case .text(let value) = fragments.first else { return XCTFail("Expected styled text") }
        XCTAssertEqual(String(value.characters), #"literal \command and =code="#)
    }

    private func fragments(in source: String) throws -> [OrgPreviewInlineFragment] {
        let document = WorkspaceDocument(path: "math.org", title: "Math", contents: source + "\n", kind: .org)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([document]).first)
        XCTAssertFalse(parsed.hasError)
        let paragraph = try XCTUnwrap(parsed.root.children.first { $0.type == "paragraph" })
        return OrgPreviewMarkup.fragments(paragraph)
    }

    private func math(in fragments: [OrgPreviewInlineFragment]) -> [OrgMathExpression] {
        fragments.compactMap { fragment in
            guard case .math(let expression) = fragment else { return nil }
            return expression
        }
    }
}
