import SwiftUI
import SwiftMath
import UIKit
import XCTest
@testable import Orgenda

/// Opt-in integration audit. Stage input.json under the simulator app's
/// Documents/MathCorpusAudit and set ORGENDA_MATH_CORPUS_AUDIT=1 on the runner.
/// Original documents are read from a staged copy and are never edited.
@MainActor
final class OrgMathCorpusAuditTests: XCTestCase {
    struct Document: Decodable { let path: String; let source: String }
    struct Formula: Decodable {
        let file: String; let line: Int; let kind: String; let source: String; let body: String
    }
    struct Input: Decodable { let documents: [Document]; let formulas: [Formula] }
    struct RenderResult: Codable {
        let success: Bool; let error: String?; let width: Double; let height: Double; let image: String?
    }
    struct Finding: Codable {
        let file: String; let line: Int; let kind: String; let source: String; let latex: String
        let projected: Bool; let rendered: RenderResult
    }
    struct FileResult: Codable {
        let path: String; let parseError: Bool; let candidates: Int
        let projected: Int; let renderFailures: Int; let missing: Int; let extraProjected: [String]
    }
    struct Report: Codable {
        let files: [FileResult]; let formulas: [Finding]; let uniqueRendered: Int
    }

    func testRenderStagedOrgCorpus() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORGENDA_MATH_CORPUS_AUDIT"] == "1"
            || environment["TEST_RUNNER_ORGENDA_MATH_CORPUS_AUDIT"] == "1" else {
            throw XCTSkip("Opt-in corpus audit requires staged documents")
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MathCorpusAudit")
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: directory.appendingPathComponent("input.json")))
        let imageDirectory = directory.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        let candidates = Dictionary(grouping: input.formulas, by: \.file)
        var renderCache: [String: RenderResult] = [:]
        var findings: [Finding] = []
        var files: [FileResult] = []

        for document in input.documents {
            try autoreleasepool {
                let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([
                    WorkspaceDocument(path: document.path, title: document.path, contents: document.source, kind: .org)
                ]).first)
                var projected = projectedExpressions(in: parsed.root.children)
                    .reduce(into: [String: Int]()) { $0[$1.original, default: 0] += 1 }
                var missing = 0
                var failures = 0
                for formula in candidates[document.path, default: []] {
                    let mode: OrgMathExpression.Mode = ["\\[", "$$", "environment"].contains(formula.kind) ? .display : .inline
                    let expression = OrgMathExpression(latex: formula.body, original: formula.source, mode: mode)
                    let wasProjected = projected[formula.source, default: 0] > 0
                    if wasProjected { projected[formula.source, default: 0] -= 1 } else { missing += 1 }
                    let key = mode.rawValue + "\u{0}" + expression.latex
                    let rendered: RenderResult
                    if let cached = renderCache[key] {
                        rendered = cached
                    } else {
                        if let image = OrgMathRendering.render(expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light) {
                            let filename = String(format: "%05d.png", renderCache.count)
                            try image.image.pngData()?.write(to: imageDirectory.appendingPathComponent(filename))
                            rendered = RenderResult(success: true, error: nil,
                                                    width: image.image.size.width, height: image.image.size.height, image: filename)
                        } else {
                            var renderer = MathImage(latex: OrgMathRendering.compatibleLatex(expression.latex),
                                                     fontSize: 17, textColor: .black,
                                                     labelMode: mode == .display ? .display : .text)
                            let (error, _, _) = renderer.asImage()
                            rendered = RenderResult(success: false, error: error.map(String.init(describing:)) ?? "No image returned",
                                                    width: 0, height: 0, image: nil)
                        }
                        renderCache[key] = rendered
                    }
                    if !rendered.success { failures += 1 }
                    findings.append(Finding(file: document.path, line: formula.line, kind: formula.kind,
                                            source: formula.source, latex: formula.body,
                                            projected: wasProjected, rendered: rendered))
                }
                files.append(FileResult(path: document.path, parseError: parsed.hasError,
                                        candidates: candidates[document.path, default: []].count,
                                        projected: candidates[document.path, default: []].count - missing,
                                        renderFailures: failures, missing: missing,
                                        extraProjected: projected.filter { $0.value > 0 }.map(\.key).sorted()))
                print("CORPUS \(files.count)/\(input.documents.count): \(document.path), missing=\(missing), failed=\(failures)")
            }
        }
        let report = Report(files: files, formulas: findings, uniqueRendered: renderCache.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try data.write(to: directory.appendingPathComponent("report.json"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Org formula corpus report"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(files.count, input.documents.count)
        XCTAssertEqual(findings.count, input.formulas.count)
        print("CORPUS TOTAL files=\(files.count), formulas=\(findings.count), missing=\(findings.filter { !$0.projected }.count), failed=\(findings.filter { !$0.rendered.success }.count), unique=\(renderCache.count)")
    }

    private func expressions(_ fragments: [OrgPreviewInlineFragment]) -> [OrgMathExpression] {
        fragments.compactMap { if case .math(let expression) = $0 { return expression }; return nil }
    }

    private func descendants(_ node: ParsedOrgNode) -> [ParsedOrgNode] {
        [node] + node.children.flatMap(descendants)
    }

    private func projectedExpressions(in nodes: [ParsedOrgNode]) -> [OrgMathExpression] {
        OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: nodes)).flatMap { row -> [OrgMathExpression] in
            let node = row.node
            switch node.type {
            case "custom_block": return projectedExpressions(in: node.children)
            case "math_block": return OrgMathParser.soleDisplayExpression(in: node.text).map { [$0] } ?? []
            case "paragraph": return expressions(OrgPreviewMarkup.fragments(node))
            case "heading": return node.child(ofType: "heading_title").map { expressions(OrgPreviewMarkup.fragments($0, trimSpaces: true)) } ?? []
            case "list_item": return node.child(ofType: "list_item_content").map { expressions(OrgPreviewMarkup.fragments($0, trimSpaces: true)) } ?? []
            case "table": return descendants(node).filter { $0.type == "table_cell" }.flatMap { expressions(OrgPreviewMarkup.fragments($0, trimSpaces: true)) }
            case "quote_block", "verse_block", "center_block": return expressions(OrgPreviewContainerMath.blockFragments(node))
            case "footnote_definition", "property": return expressions(OrgPreviewMarkup.fragments(node))
            case "keyword":
                let name = node.child(ofType: "keyword_key")?.text.uppercased() ?? ""
                if name == "CAPTION", let value = node.child(ofType: "keyword_value") { return expressions(OrgPreviewMarkup.fragments(value)) }
                return []
            case "drawer", "property_drawer", "dynamic_block":
                return projectedExpressions(in: OrgPreviewMarkup.contents(of: node))
            default: return []
            }
        }
    }
}
