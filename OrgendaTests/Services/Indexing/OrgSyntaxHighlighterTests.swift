import Foundation
import XCTest
@testable import Orgenda

final class OrgSyntaxHighlighterTests: XCTestCase {
    func testPlainLinksDoNotProduceEmphasisSpans() async {
        let target = "https://example.com/a_b/c_d?q=one+two&next=/docs/#section"
        let source = "中文🙂 cafe\u{301} (\(target)). /斜体/ _下划线_\r\n"
        let spans = await OrgSyntaxHighlighter().highlights(in: source)
        let nsSource = source as NSString
        let links = spans.filter { $0.kind == .link }

        XCTAssertEqual(links.map { nsSource.substring(with: $0.range) }, [target])
        XCTAssertEqual(text(of: .italic, in: spans, source: source), "/斜体/")
        XCTAssertEqual(text(of: .underline, in: spans, source: source), "_下划线_")
        for span in spans {
            XCTAssertNotNil(Range(span.range, in: source))
            if [.bold, .italic, .underline, .strikethrough, .code, .verbatim].contains(span.kind) {
                for link in links {
                    XCTAssertEqual(NSIntersectionRange(span.range, link.range).length, 0)
                }
            }
        }
    }

    func testHighlightsRepresentativeSyntaxWithoutStylingLiteralBlockContents() async {
        let source = """
        #+TITLE: 示例文档
        # 一条中文注释
        * TODO [#A] 你好🙂 cafe\u{301} *重点* /斜体/ _下划线_ +删除+ ~代码~ =原样= :work:ios:
        SCHEDULED: <2026-09-01 Tue 09:30> DEADLINE: [2026-09-02 Wed]
        :PROPERTIES:
        :ID: 中文-001
        :END:
        :LOGBOOK:
        CLOCK: [2026-09-19 Sat 09:00]--[2026-09-19 Sat 10:00] => 1:00
        :END:
        Progress [2/3] <<target>> {{{title}}} [fn::注释]
        - [ ] 阅读 [[https://example.com][说明]] [fn:note]
        | 名称 | 值 |
        |------+----|
        [fn:note] 脚注内容
        #+BEGIN_SRC swift
        let greeting = "你好"
        #+END_SRC
        #+BEGIN_QUOTE
        引用内容
        #+END_QUOTE
        #+BEGIN_EXAMPLE
        *literal* [50%]
        #+END_EXAMPLE
        #+BEGIN_COMMENT
        * TODO hidden
        #+END_COMMENT
        """
        let highlighter = OrgSyntaxHighlighter()

        let spans = await highlighter.highlights(in: source)
        let kinds = Set(spans.map(\.kind))

        XCTAssertEqual(kinds, Set(OrgHighlightKind.allCases))
        for span in spans {
            XCTAssertGreaterThan(span.range.length, 0)
            XCTAssertNotNil(Range(span.range, in: source), "Invalid UTF-16 range for \(span.kind)")
        }
        XCTAssertEqual(text(of: .todo, in: spans, source: source)?.trimmingCharacters(in: .whitespaces), "TODO")
        XCTAssertEqual(text(of: .priority, in: spans, source: source)?.trimmingCharacters(in: .whitespaces), "[#A]")
        XCTAssertEqual(text(of: .link, in: spans, source: source), "[[https://example.com][说明]]")
        XCTAssertEqual(text(of: .checkbox, in: spans, source: source)?.trimmingCharacters(in: .whitespaces), "[ ]")
        let nsSource = source as NSString
        for (kind, literal) in [(OrgHighlightKind.bold, "literal"), (.progress, "[50%]"), (.heading, "hidden")] {
            XCTAssertFalse(spans.contains { $0.kind == kind && nsSource.substring(with: $0.range).contains(literal) }, literal)
        }
        for (kind, token) in [(OrgHighlightKind.drawerDelimiter, ":LOGBOOK:"), (.clock, "CLOCK:"),
                              (.footnote, "[fn::注释]"), (.sourceBlock, "*literal*"), (.comment, "* TODO hidden")] {
            XCTAssertTrue(spans.contains { $0.kind == kind && nsSource.substring(with: $0.range).contains(token) }, token)
        }
        let empty = await highlighter.highlights(in: "")
        XCTAssertTrue(empty.isEmpty)
    }

    func testByteRangeConversionRejectsInvalidBoundariesAndBounds() {
        let source = "A你🙂B"

        let cases: [(Int, Int, NSRange?)] = [
            (0, 9, NSRange(location: 0, length: 5)),
            (1, 4, NSRange(location: 1, length: 1)),
            (4, 8, NSRange(location: 2, length: 2)),
            (2, 4, nil), (-1, 1, nil), (4, 10, nil), (4, 4, nil), (8, 4, nil)
        ]
        for (start, end, expected) in cases {
            XCTAssertEqual(OrgSyntaxHighlighter.utf16Range(startByte: start, endByte: end, in: source),
                           expected, "UTF-8 range \(start)..<\(end)")
        }
    }

    private func text(
        of kind: OrgHighlightKind,
        in spans: [OrgHighlightSpan],
        source: String
    ) -> String? {
        guard let span = spans.first(where: { $0.kind == kind }) else { return nil }
        return (source as NSString).substring(with: span.range)
    }
}
