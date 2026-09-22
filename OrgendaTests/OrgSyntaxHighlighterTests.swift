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

    func testHighlightsDrawersClocksAndExtendedSyntaxWithoutParsingLiteralContents() async {
        let source = """
        * TODO 中文🙂 [2/3]
          :LOGBOOK:
          CLOCK: [2026-09-19 Sat 09:00]--[2026-09-19 Sat 10:00] => 1:00
          :END:
        See <<目标>> {{{title}}} [fn::注释] <https://orgmode.org>.
        #+BEGIN_EXAMPLE
        *literal* [50%]
        #+END_EXAMPLE
        #+BEGIN_COMMENT
        * TODO hidden
        #+END_COMMENT
        """
        let spans = await OrgSyntaxHighlighter().highlights(in: source)
        let nsSource = source as NSString
        func contains(_ kind: OrgHighlightKind, _ text: String) -> Bool {
            spans.contains { $0.kind == kind && nsSource.substring(with: $0.range).contains(text) }
        }
        XCTAssertTrue(contains(.drawer, ":LOGBOOK:"))
        XCTAssertTrue(contains(.drawerDelimiter, ":LOGBOOK:"))
        XCTAssertTrue(contains(.clock, "CLOCK:"))
        XCTAssertTrue(contains(.clock, "=> 1:00"))
        XCTAssertTrue(contains(.progress, "[2/3]"))
        XCTAssertTrue(contains(.target, "<<目标>>"))
        XCTAssertTrue(contains(.macro, "{{{title}}}"))
        XCTAssertTrue(contains(.footnote, "[fn::注释]"))
        XCTAssertTrue(contains(.sourceBlock, "*literal*"))
        XCTAssertTrue(contains(.comment, "* TODO hidden"))
        XCTAssertFalse(contains(.bold, "literal"))
        XCTAssertFalse(contains(.progress, "[50%]"))
        XCTAssertFalse(contains(.heading, "hidden"))
        for span in spans { XCTAssertNotNil(Range(span.range, in: source)) }
    }

    func testHighlightsRepresentativeOrgSyntax() async throws {
        let source = """
        #+TITLE: 示例文档
        # 一条中文注释
        * TODO [#A] 完成 *重点* /斜体/ _下划线_ +删除+ ~代码~ =原样= :work:ios:
        SCHEDULED: <2026-09-01 Tue 09:30> DEADLINE: [2026-09-02 Wed]
        :PROPERTIES:
        :ID: 中文-001
        :END:
        CLOCK: => 1:00
        Progress [2/3] <<target>> {{{title}}}
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
        """
        let highlighter = try XCTUnwrap(OrgSyntaxHighlighter())

        let spans = await highlighter.highlights(in: source)
        let kinds = Set(spans.map(\.kind))

        XCTAssertEqual(kinds, Set(OrgHighlightKind.allCases))
        XCTAssertEqual(text(of: .todo, in: spans, source: source)?.trimmingCharacters(in: .whitespaces), "TODO")
        XCTAssertEqual(text(of: .priority, in: spans, source: source)?.trimmingCharacters(in: .whitespaces), "[#A]")
        XCTAssertEqual(text(of: .link, in: spans, source: source), "[[https://example.com][说明]]")
        XCTAssertEqual(text(of: .checkbox, in: spans, source: source)?.trimmingCharacters(in: .whitespaces), "[ ]")
    }

    func testUTF8TreeSitterOffsetsBecomeValidUTF16Ranges() async throws {
        // The link begins after CJK, a supplementary-plane emoji, and a
        // decomposed grapheme (`e` + combining acute). Its tree-sitter byte
        // offset therefore differs substantially from its UTF-16 location.
        let source = "* TODO 你好🙂 cafe\u{301} [[id:東京][链接]] :zh:\n"
        let highlighter = try XCTUnwrap(OrgSyntaxHighlighter())

        let spans = await highlighter.highlights(in: source)
        let utf16Length = (source as NSString).length

        XCTAssertFalse(spans.isEmpty)
        for span in spans {
            XCTAssertGreaterThan(span.range.length, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(span.range), utf16Length)
            XCTAssertNotNil(Range(span.range, in: source), "Invalid UTF-16 range for \(span.kind)")
        }

        XCTAssertEqual(text(of: .link, in: spans, source: source), "[[id:東京][链接]]")
        XCTAssertTrue(text(of: .heading, in: spans, source: source, longest: true)?.contains("你好🙂") == true)
    }

    func testByteRangeConversionRejectsInvalidBoundariesAndBounds() {
        let source = "A你🙂B"

        XCTAssertEqual(
            OrgSyntaxHighlighter.utf16Range(startByte: 0, endByte: 9, in: source),
            NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(
            OrgSyntaxHighlighter.utf16Range(startByte: 1, endByte: 4, in: source),
            NSRange(location: 1, length: 1)
        )
        XCTAssertEqual(
            OrgSyntaxHighlighter.utf16Range(startByte: 4, endByte: 8, in: source),
            NSRange(location: 2, length: 2)
        )
        XCTAssertNil(OrgSyntaxHighlighter.utf16Range(startByte: 2, endByte: 4, in: source))
        XCTAssertNil(OrgSyntaxHighlighter.utf16Range(startByte: -1, endByte: 1, in: source))
        XCTAssertNil(OrgSyntaxHighlighter.utf16Range(startByte: 4, endByte: 10, in: source))
        XCTAssertNil(OrgSyntaxHighlighter.utf16Range(startByte: 4, endByte: 4, in: source))
        XCTAssertNil(OrgSyntaxHighlighter.utf16Range(startByte: 8, endByte: 4, in: source))
    }

    func testEmptyDocumentProducesNoSpans() async throws {
        let highlighter = try XCTUnwrap(OrgSyntaxHighlighter())

        let spans = await highlighter.highlights(in: "")

        XCTAssertTrue(spans.isEmpty)
    }

    private func text(
        of kind: OrgHighlightKind,
        in spans: [OrgHighlightSpan],
        source: String,
        longest: Bool = false
    ) -> String? {
        let matches = spans.filter { $0.kind == kind }
        let span = longest ? matches.max(by: { $0.range.length < $1.range.length }) : matches.first
        guard let span else { return nil }
        return (source as NSString).substring(with: span.range)
    }
}
