import SwiftUI
import XCTest
@testable import Orgenda

@MainActor
final class OrgPreviewImagePresentationTests: XCTestCase {
    func testImageInChineseParagraphPreservesMathLinksAndUTF8SourceOffsets() throws {
        let source = #"前言🙂 \(x + y\) [[file:images/示意.png]] 后文 [[https://example.com][资料]] \(z\)。"# + "\n"
        let document = try parse(source)
        let paragraph = try XCTUnwrap(document.root.children.first { $0.type == "paragraph" })
        let fragments = OrgPreviewMarkup.fragments(paragraph)
        let reference = try XCTUnwrap(images(fragments).first)

        XCTAssertEqual(images(fragments).count, 1)
        XCTAssertEqual(math(fragments).map(\.latex), ["x + y", "z"])
        XCTAssertEqual(text(fragments), "前言🙂   后文 资料 。")
        XCTAssertEqual(reference.startByte, #"前言🙂 \(x + y\) "#.utf8.count)
        XCTAssertEqual(reference.target, "file:images/示意.png")
        XCTAssertTrue(fragments.contains { fragment in
            guard case .text(let value) = fragment else { return false }
            return value.runs.contains { $0.link?.absoluteString == "https://example.com" }
        })

        let segments = OrgPreviewImageFlow.segments(fragments)
        XCTAssertEqual(segmentKinds(segments), ["text", "image", "text"])
        guard case .text(let before) = segments[0], case .text(let after) = segments[2] else {
            return XCTFail("Expected rich text on both sides of the image")
        }
        XCTAssertEqual(math(before).map(\.latex), ["x + y"])
        XCTAssertEqual(math(after).map(\.latex), ["z"])
        XCTAssertEqual(paragraph.text, source)
        XCTAssertEqual(document.root.children, try parse(source).root.children)
    }

    func testDescribedImageUsesDescriptionAsAlternativeText() throws {
        let source = "[[file:images/state%20diagram.png][状态迁移图：打开 → 完成]]\n"
        let paragraph = try XCTUnwrap(try parse(source).root.children.first { $0.type == "paragraph" })
        let fragments = OrgPreviewMarkup.fragments(paragraph)
        let reference = try XCTUnwrap(images(fragments).first)

        XCTAssertEqual(reference.label, "状态迁移图：打开 → 完成")
        XCTAssertEqual(reference.target, "file:images/state%20diagram.png")
        XCTAssertEqual(reference.startByte, 0)
        XCTAssertTrue(text(fragments).isEmpty)
        XCTAssertEqual(segmentKinds(OrgPreviewImageFlow.segments(fragments)), ["image"])
        XCTAssertEqual(paragraph.text, source)
    }

    func testAdjacentImagesKeepSourceOrderWithoutEmptyTextRows() throws {
        let source = "[[file:first.png]]\n[[attachment:second.jpg]]\n[[https://example.com/third.png]]\n"
        let document = try parse(source)
        let fragments = document.root.children.flatMap { OrgPreviewMarkup.fragments($0) }
        let segments = OrgPreviewImageFlow.segments(fragments)

        XCTAssertEqual(segmentKinds(segments), ["image", "image", "image"])
        XCTAssertEqual(images(fragments).map(\.target), [
            "file:first.png", "attachment:second.jpg", "https://example.com/third.png"
        ])
        XCTAssertEqual(images(fragments).map(\.startByte), [
            0, "[[file:first.png]]\n".utf8.count,
            "[[file:first.png]]\n[[attachment:second.jpg]]\n".utf8.count
        ])
        XCTAssertEqual(document.root.children.map(\.text).joined(), source)
    }

    func testInlineCodeAndVerbatimKeepImageSyntaxLiteral() throws {
        let source = "=[[file:code.png]]= ~[[file:verbatim.png]]~ [[file:real.png]]\n"
        let document = try parse(source)
        let fragments = document.root.children.flatMap { OrgPreviewMarkup.fragments($0) }

        XCTAssertEqual(images(fragments).map(\.target), ["file:real.png"])
        XCTAssertTrue(text(fragments).contains("[[file:code.png]]"))
        XCTAssertTrue(text(fragments).contains("[[file:verbatim.png]]"))
        XCTAssertEqual(document.root.children.map(\.text).joined(), source)
    }

    func testSourceAndExampleBlocksKeepImageLinksAsLiteralSource() throws {
        for name in ["src", "example"] {
            let source = "#+begin_\(name)\(name == "src" ? " org" : "")\n[[file:literal.png]]\n#+end_\(name)\n"
            let expectedType = name == "src" ? "source_block" : "example_block"
            let block = try XCTUnwrap(try parse(source).root.children.first { $0.type == expectedType })

            XCTAssertTrue(images(OrgPreviewMarkup.fragments(block)).isEmpty, name)
            XCTAssertEqual(OrgPreviewMarkup.literalText(block), "[[file:literal.png]]", name)
            XCTAssertEqual(block.text, source, name)
        }
    }

    func testQuoteImageKeepsHeadingAttachmentContextAndOriginalByteOffset() throws {
        let prefix = "* 中文标题🙂\n:PROPERTIES:\n:DIR: attachments\n:END:\n#+begin_quote\n引用 "
        let imageSource = "[[attachment:photo.png][引用图片]]"
        let source = prefix + imageSource + " 后文\n#+end_quote\n"
        let document = try parse(source)
        let block = try XCTUnwrap(document.root.children.first { $0.type == "quote_block" })
        let fragments = OrgPreviewContainerMath.blockFragments(block)
        let reference = try XCTUnwrap(images(fragments).first)

        XCTAssertEqual(reference.startByte, prefix.utf8.count)
        XCTAssertEqual(reference.label, "引用图片")
        XCTAssertEqual(try reference.candidates(documentPath: "notes/images.org", document: document), [
            "notes/attachments/photo.png"
        ])
        XCTAssertEqual(text(fragments), "引用  后文")
        XCTAssertFalse(text(fragments).contains("#+begin_quote"))
        XCTAssertEqual(sourceSlice(source, startByte: reference.startByte, count: imageSource.utf8.count), imageSource)
    }

    func testCustomBlockImageKeepsSourceOffsetAfterGrouping() throws {
        let prefix = "前言🙂\n#+begin_note :title 图示\n说明 "
        let imageSource = "[[file:images/custom.png]]"
        let source = prefix + imageSource + " 尾文\n#+end_note\n"
        let document = try parse(source)
        let originalLink = try XCTUnwrap(flatten(document.root.children).first { $0.type == "link" })
        let block = try XCTUnwrap(OrgPreviewCustomBlocks.group(document.root.children).first { $0.type == "custom_block" })
        let fragments = block.children.flatMap { OrgPreviewMarkup.fragments($0) }
        let reference = try XCTUnwrap(images(fragments).first)

        XCTAssertEqual(reference.startByte, prefix.utf8.count)
        XCTAssertEqual(reference.startByte, originalLink.startByte)
        XCTAssertEqual(flatten(block.children).first { $0.id == originalLink.id }, originalLink)
        XCTAssertEqual(text(fragments), "说明  尾文")
        XCTAssertEqual(segmentKinds(OrgPreviewImageFlow.segments(fragments)), ["text", "image", "text"])
        XCTAssertEqual(sourceSlice(source, startByte: reference.startByte, count: imageSource.utf8.count), imageSource)
    }

    private func parse(_ source: String) throws -> ParsedOrgDocument {
        try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "notes/images.org", title: "Images", contents: source, kind: .org)
        ]).first)
    }

    private func images(_ fragments: [OrgPreviewInlineFragment]) -> [OrgPreviewImageReference] {
        fragments.compactMap {
            guard case .image(let reference) = $0 else { return nil }
            return reference
        }
    }

    private func math(_ fragments: [OrgPreviewInlineFragment]) -> [OrgMathExpression] {
        fragments.compactMap {
            guard case .math(let expression) = $0 else { return nil }
            return expression
        }
    }

    private func text(_ fragments: [OrgPreviewInlineFragment]) -> String {
        fragments.compactMap {
            guard case .text(let value) = $0 else { return nil }
            return String(value.characters)
        }.joined()
    }

    private func segmentKinds(_ segments: [OrgPreviewImageFlow.Segment]) -> [String] {
        segments.map {
            switch $0 {
            case .text: "text"
            case .image: "image"
            }
        }
    }

    private func flatten(_ nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    private func sourceSlice(_ source: String, startByte: Int, count: Int) -> String {
        String(decoding: Array(source.utf8)[startByte..<(startByte + count)], as: UTF8.self)
    }
}
