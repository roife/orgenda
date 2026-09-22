import SwiftUI
import SwiftMath
import UIKit
import XCTest
@testable import Orgenda

@MainActor
final class OrgSyntaxTextEditorTests: XCTestCase {
    func testSearchSelectionUsesUnicodeRangeWithoutEditingSource() {
        let session = OrgEditorSession()
        let view = OrgEditorTextView.make()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        let source = "中文🙂\n* Café workflow\nBody"
        view.text = source
        session.attach(view)
        session.selectSearchMatch("cafe")
        XCTAssertEqual(view.selectedRange, (source as NSString).range(of: "Café"))
        XCTAssertEqual(view.text, source)
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        session.selectSearchMatch("not present")
        XCTAssertEqual(view.selectedRange, (source as NSString).range(of: "Café"))
    }

    func testEditorFontIsCompactAndScalesWithDynamicType() {
        let standardFont = OrgSyntaxPresentation.bodyFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let accessibilityFont = OrgSyntaxPresentation.bodyFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )

        XCTAssertEqual(standardFont.pointSize, 16, accuracy: 0.01)
        XCTAssertGreaterThan(accessibilityFont.pointSize, standardFont.pointSize)
    }

    func testWorkflowSymbolsExistAndCurrentStatesHaveDistinctColors() {
        for state in OrgWorkflowState.allCases {
            XCTAssertNotNil(UIImage(systemName: state.symbol), state.rawValue)
        }
        let states = OrgWorkspaceConfiguration.taskStates
        XCTAssertEqual(Set(states.map(\.symbol)).count, states.count)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let colors = states.map {
                UIColor(OrgendaTheme.workflowColor($0)).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            }
            for index in colors.indices {
                for other in colors.indices where other > index {
                    XCTAssertNotEqual(colors[index], colors[other], "\(states[index]) and \(states[other])")
                }
            }
        }
    }

    func testWorkflowColorsCoverRichHeadingTitlesWithoutChangingSource() async throws {
        let source = "中文🙂\n* WAIT 标题 *加粗* [[https://example.com][链接]] :tag:\nBody.\n* Plain heading\n"
        let highlights = await OrgSyntaxHighlighter().highlights(in: source)
        let storage = NSTextStorage(string: source, attributes: [.foregroundColor: UIColor.label])
        for span in highlights {
            OrgSyntaxPresentation.apply(span.kind, to: storage, range: span.range, colorSchemeContrast: .standard)
        }
        OrgSyntaxPresentation.applyWorkflowHeadingColors(highlights, to: storage)
        for fragment in ["WAIT", "标题", "加粗", "链接"] {
            let location = (source as NSString).range(of: fragment).location
            let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                XCTAssertEqual(color.resolvedColor(with: traits),
                               UIColor(OrgendaTheme.workflowColor(.wait)).resolvedColor(with: traits))
            }
        }
        let body = (source as NSString).range(of: "Body.").location
        XCTAssertEqual(storage.attribute(.foregroundColor, at: body, effectiveRange: nil) as? UIColor, .label)
        XCTAssertEqual(storage.string, source)
    }

    func testWorkflowLogIconsPreserveTransitionAndNoteDetails() throws {
        let entry = try XCTUnwrap(OrgWorkflowLogEntry("State \"CANCELED\" from \"WAIT\" [2026-09-20 Sun] \\\\\n  保留备注🙂"))
        XCTAssertEqual(entry.current, "CANCELED")
        XCTAssertEqual(entry.previous, "WAIT")
        XCTAssertTrue(entry.details.contains("保留备注🙂"))
        XCTAssertNil(try XCTUnwrap(OrgWorkflowLogEntry("State \"DONE\" [2026-09-20 Sun]")).previous)
        XCTAssertNil(OrgWorkflowLogEntry("A note about State \"DONE\""))
    }

    func testFloatingToolbarKeepsFinalCaretVisibleAndMarginsInteractive() {
        let textView = OrgEditorTextView.make()
        textView.font = OrgSyntaxPresentation.bodyFont(compatibleWith: textView.traitCollection)
        textView.text = (1...40).map { "Line \($0)" }.joined(separator: "\n")
        let container = OrgEditorContainer(textView: textView, session: OrgEditorSession())
        container.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        container.setKeyboardFocused(true)
        container.layoutIfNeeded()
        textView.selectedRange = NSRange(location: textView.text.utf16.count, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        textView.layoutIfNeeded()

        let caret = textView.convert(textView.caretRect(for: textView.endOfDocument), to: container)
        // UIKit rounds the caret one point beyond the text layout fragment.
        XCTAssertLessThanOrEqual(caret.maxY, container.bounds.height - OrgKeyboardAccessory.height + 2)
        let marginHit = container.hitTest(CGPoint(x: 4, y: 496), with: nil)
        XCTAssertTrue(marginHit === textView || marginHit?.isDescendant(of: textView) == true)
        container.setKeyboardFocused(false)
        XCTAssertEqual(textView.contentInset.bottom, 0)
    }

    func testOrgInputCommandsKeepUnicodeSelectionsAndListSyntax() throws {
        let source = "中文🙂\nsecond\nuntouched"
        let selection = NSRange(location: 0, length: "中文🙂\nsecond\n".utf16.count)
        let edit = try XCTUnwrap(OrgInputCommands.edit(.indent, source: source, selection: selection))
        XCTAssertEqual((source as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
                       "  中文🙂\n  second\nuntouched")
        XCTAssertEqual(edit.selection, NSRange(location: 2, length: selection.length + 2))
        let item = try XCTUnwrap(OrgInputCommands.edit(.checkbox, source: "  - 中文🙂", selection: NSRange(location: 8, length: 0)))
        XCTAssertEqual(item.replacement, "  - [ ] 中文🙂")
        XCTAssertEqual(item.selection.location, 12)
        XCTAssertNil(OrgInputCommands.edit(.checkbox, source: "- [X] done", selection: NSRange(location: 8, length: 0)))
        let heading = try XCTUnwrap(OrgInputCommands.edit(.outdent, source: "** 中文", selection: NSRange(location: 5, length: 0)))
        XCTAssertEqual(heading.replacement, "* 中文")
    }

    func testReturnContinuesAndExitsListsButLeavesLiteralBlocksAlone() throws {
        for (source, expected) in [("- [X] 中文🙂", "\n- [ ] "), ("  9. item", "\n  10. "), ("+ note", "\n+ ")] {
            let edit = try XCTUnwrap(OrgInputCommands.newline(source: source, selection: NSRange(location: source.utf16.count, length: 0)))
            XCTAssertEqual(edit.replacement, expected)
            XCTAssertEqual(edit.selection.location, source.utf16.count + expected.utf16.count)
        }
        let empty = try XCTUnwrap(OrgInputCommands.newline(source: "- [ ] ", selection: NSRange(location: 6, length: 0)))
        XCTAssertEqual(empty.replacement, "")
        XCTAssertEqual(empty.range, NSRange(location: 0, length: 6))
        let literal = "#+BEGIN_SRC text\n- literal"
        XCTAssertNil(OrgInputCommands.newline(source: literal, selection: NSRange(location: literal.utf16.count, length: 0)))
        let drawer = ":LOGBOOK:\n- State DONE"
        XCTAssertNil(OrgInputCommands.newline(source: drawer, selection: NSRange(location: drawer.utf16.count, length: 0)))
        XCTAssertNil(OrgInputCommands.newline(source: "* Heading", selection: NSRange(location: 9, length: 0)))
    }

    func testPreviewEditsAndNativeTypingShareUndoAcrossModes() throws {
        var source = "* TODO 中文🙂\n"
        let original = source
        let session = OrgEditorSession()
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }),
                                         highlights: [], session: session)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.connect(textView)
        func render() {
            coordinator.apply(text: source, highlights: [], to: textView, colorScheme: .light,
                              dynamicTypeSize: .large, colorSchemeContrast: .standard)
        }
        render()
        let manager = try XCTUnwrap(textView.undoManager)
        manager.groupsByEvent = false
        textView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        manager.beginUndoGrouping()
        textView.insertText("A note")
        manager.endUndoGrouping()
        let typed = source
        XCTAssertEqual(typed, original + "A note")
        session.suspendEditing()
        source = source.replacingOccurrences(of: "TODO", with: "DONE")
        manager.beginUndoGrouping()
        render()
        manager.endUndoGrouping()
        session.refreshHistory()
        XCTAssertTrue(session.canUndo)
        session.undo()
        XCTAssertEqual(source, typed)
        session.undo()
        XCTAssertEqual(source, original)
        session.redo()
        XCTAssertEqual(source, typed)
        session.redo()
        XCTAssertEqual(source, typed.replacingOccurrences(of: "TODO", with: "DONE"))
    }

    func testCommandUndoRestoresSelectionAndExternalReloadClearsHistory() throws {
        var source = "中文🙂"
        let session = OrgEditorSession()
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: [], session: session)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.apply(text: source, highlights: [], to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        let manager = try XCTUnwrap(textView.undoManager)
        manager.groupsByEvent = false
        let selected = NSRange(location: 2, length: 2)
        textView.selectedRange = selected
        manager.beginUndoGrouping()
        session.perform(.heading)
        manager.endUndoGrouping()
        XCTAssertEqual(source, "* 中文🙂")
        session.undo()
        XCTAssertEqual(source, "中文🙂")
        XCTAssertEqual(textView.selectedRange, selected)
        session.redo()
        source = "* External version\n"
        coordinator.acceptRevision(1, in: textView)
        coordinator.apply(text: source, highlights: [], to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        session.refreshHistory()
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)
        XCTAssertEqual(textView.text, source)
    }

    func testMarkedCompositionIsNotInterruptedByHighlightingAndCanBeUndone() throws {
        var source = "* Note\n"
        let original = source
        let session = OrgEditorSession()
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: [], session: session)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.apply(text: source, highlights: [], to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        textView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        textView.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
        XCTAssertNotNil(textView.markedTextRange)
        coordinator.apply(text: source, highlights: [], to: textView, colorScheme: .dark,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        XCTAssertNotNil(textView.markedTextRange)
        textView.setMarkedText("中文🙂", selectedRange: NSRange(location: 4, length: 0))
        textView.unmarkText()
        XCTAssertEqual(source, original + "中文🙂")
        session.undo()
        XCTAssertEqual(source, original)
        session.redo()
        XCTAssertEqual(source, original + "中文🙂")
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testCollapsedHeadingFollowsEarlierUnicodeEditsAndWorkflowChanges() throws {
        func document(_ source: String) throws -> ParsedOrgDocument {
            try XCTUnwrap(OrgIndexService.parseSynchronously([WorkspaceDocument(path: "test.org", title: "test", contents: source, kind: .org)]).first)
        }
        let old = try document("* First\nbody\n* TODO 第二节🙂\n** Child\ntext\n")
        let new = try document("* First\nlonger 中文🙂 body\n* DONE 第二节🙂\n** Child\ntext\n")
        let oldHeading = try XCTUnwrap(old.root.children.first { $0.text.contains("TODO") })
        let newHeading = try XCTUnwrap(new.root.children.first { $0.text.contains("DONE") })
        XCTAssertEqual(OrgHeadingContinuity.remap([oldHeading.id], from: old, to: new), [newHeading.id])
    }

    func testPreviewRendersInlineMarkupAndLinksFromUTF8Nodes() throws {
        let node = try parsedNodes("中文🙂 *粗体* /斜体/ _下划线_ +旧文+ ~code~ =raw= [[https://orgmode.org][Org manual]] [2/3]\n")[0]
        let value = OrgPreviewMarkup.attributed(node)
        XCTAssertEqual(String(value.characters), "中文🙂 粗体 斜体 下划线 旧文 code raw Org manual 2/3")
        XCTAssertTrue(value.runs.contains { String(value[$0.range].characters) == "粗体" && $0.inlinePresentationIntent == .stronglyEmphasized })
        XCTAssertTrue(value.runs.contains { String(value[$0.range].characters) == "斜体" && $0.inlinePresentationIntent == .emphasized })
        XCTAssertTrue(value.runs.contains { $0.underlineStyle == .single })
        XCTAssertTrue(value.runs.contains { $0.strikethroughStyle == .single })
        XCTAssertTrue(value.runs.contains { $0.link == URL(string: "https://orgmode.org") })
        XCTAssertNil(OrgPreviewMarkup.externalURL("id:local-note"))
        XCTAssertNil(OrgPreviewMarkup.externalURL("elisp:(message)"))
    }

    func testPreviewTimestampReplacementCoexistsWithMarkupAndWebLinks() throws {
        let node = try parsedNodes("🙂 *Meet* <2026-09-19 Sat> at [[https://orgmode.org][Org]].\n")[0]
        let value = OrgPreviewMarkup.attributed(node) { child in
            guard child.type == "timestamp" else { return nil }
            var timestamp = AttributedString("<2026-09-20 Sun>")
            timestamp.link = URL(string: "orgenda-timestamp://edit/\(child.startByte)")
            return timestamp
        }
        XCTAssertEqual(String(value.characters), "🙂 Meet <2026-09-20 Sun> at Org.")
        XCTAssertEqual(value.runs.compactMap(\.link).count, 2)
        XCTAssertTrue(value.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    func testPreviewLiteralBlocksStripOnlyStructuralDelimiters() throws {
        let source = "#+BEGIN_SRC swift\nlet x = \"*literal*\"\n#+END_SRC\n: *fixed*\n:\n: tail\n#+BEGIN_QUOTE\nA *bold* quote.\n#+END_QUOTE\n"
        let nodes = try parsedNodes(source)
        XCTAssertEqual(OrgPreviewMarkup.literalText(nodes[0]), "let x = \"*literal*\"")
        XCTAssertEqual(OrgPreviewMarkup.literalText(nodes[1]), "*fixed*\n\ntail")
        XCTAssertEqual(String(OrgPreviewMarkup.blockText(nodes[2]).characters), "A bold quote.")
    }

    func testMathParserRecognizesInlineDisplayAndEnvironmentSyntax() {
        let source = #"中文 $e^{i\pi}+1=0$，\(a^2+b^2=c^2\)，\[\int_0^1 x\,dx\] \begin{align}x&=1\\y&=2\end{align}"#
        let matches = OrgMathParser.matches(in: source)

        XCTAssertEqual(matches.map(\.expression.mode), [.inline, .inline, .display, .display])
        XCTAssertEqual(matches.map(\.expression.latex), [
            #"e^{i\pi}+1=0"#,
            #"a^2+b^2=c^2"#,
            #"\int_0^1 x\,dx"#,
            #"\begin{align}x&=1\\y&=2\end{align}"#,
        ])
        XCTAssertEqual(matches.map { substring(source, utf8Range: $0.startByte..<$0.endByte) },
                       matches.map(\.expression.original))
    }

    func testMathParserLeavesEscapedCurrencyAndUnmatchedDelimitersAlone() {
        XCTAssertTrue(OrgMathParser.matches(in: #"Costs US$5 or \$6, with $unfinished math."#).isEmpty)
        XCTAssertNil(OrgMathParser.soleDisplayExpression(in: #"\[x^2"#))
    }

    func testPreviewFragmentsPreserveMarkupAroundInlineMath() throws {
        let node = try parsedNodes(#"*Euler:* prefix:$e^{i\pi}+x_1=0$ and [[https://example.com][details]]."# + "\n")[0]
        let fragments = OrgPreviewMarkup.fragments(node)
        let equations = fragments.compactMap { fragment -> OrgMathExpression? in
            guard case .math(let expression) = fragment else { return nil }
            return expression
        }
        let text = fragments.compactMap { fragment -> AttributedString? in
            guard case .text(let value) = fragment else { return nil }
            return value
        }.reduce(into: AttributedString()) { $0.append($1) }

        XCTAssertEqual(equations.map(\.latex), [#"e^{i\pi}+x_1=0"#])
        XCTAssertEqual(String(text.characters), "Euler: prefix: and details.")
        XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
        XCTAssertTrue(text.runs.contains { $0.link == URL(string: "https://example.com") })
    }

    func testPreviewRendersEveryInlineFormulaInMixedChineseParagraph() throws {
        let source = #"将全称量词看作是“函数”后，类型 \( T = \forall X \mathrel{\raisebox{0.1ex}{\scriptsize$<$}}\!\colon T_1. T_2\) 可以看作是一个“将 \( T_1 \) 的 subtypes 映射到类型为 \( T_2 \) 的 terms 上”的函数。令 \( S = \forall X <: S1. S2\)，其中 \( T_1 <: S_1 \)，也就是说 \( \operatorname{dom}(T) \subseteq \operatorname{dom}(S) \)。"#
        let node = try parsedNodes(source + "\n")[0]
        let fragments = OrgPreviewMarkup.fragments(node)
        let expressions = fragments.compactMap { fragment -> OrgMathExpression? in
            guard case .math(let expression) = fragment else { return nil }
            return expression
        }
        let expected = OrgMathParser.matches(in: source).map(\.expression)
        XCTAssertEqual(expected.count, 6)
        XCTAssertEqual(expressions, expected)
        let reconstructed = fragments.map { fragment -> String in
            switch fragment {
            case .text(let value): return String(value.characters)
            case .math(let expression): return expression.original
            case .image(let reference): return reference.target
            }
        }.joined()
        XCTAssertEqual(reconstructed.trimmingCharacters(in: .newlines), source)
        for expression in expressions {
            XCTAssertNotNil(OrgMathRendering.render(
                expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
            ), expression.original)
        }
        let renderer = ImageRenderer(content:
            OrgPreviewRichText(fragments: fragments)
                .font(.body)
                .lineSpacing(2)
                .frame(width: 370, alignment: .leading)
                .padding(16)
                .background(.white)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large)
        )
        renderer.scale = 3
        let screenshot = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Chinese inline formulas rendered"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPreviewRendersAdjacentFormulasInsideOneTextNode() {
        let source = #"中文🙂 \(T_1\) 的 subtypes 对应 \(T_2\)；随后 \(S\)。"#
        let child = ParsedOrgNode(id: "text", type: "text", text: source,
                                  startByte: 19, endByte: 19 + source.utf8.count, children: [])
        let paragraph = ParsedOrgNode(id: "paragraph", type: "paragraph", text: source,
                                      startByte: child.startByte, endByte: child.endByte, children: [child])
        let expressions = OrgPreviewMarkup.fragments(paragraph).compactMap { fragment -> String? in
            guard case .math(let expression) = fragment else { return nil }
            return expression.latex
        }
        XCTAssertEqual(expressions, ["T_1", "T_2", "S"])
    }

    func testPreviewGroupsMultilineDisplayMathIntoOneRow() throws {
        let source = #"""
        Before
        \[
        \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
        \]
        After
        """# + "\n"
        let nodes = try parsedNodes(source)
        let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: nodes))

        XCTAssertEqual(rows.filter { $0.node.type != "blank_line" }.map(\.node.type), ["paragraph", "math_block", "paragraph"])
        XCTAssertNotNil(OrgMathParser.soleDisplayExpression(in: rows[1].node.text))
    }

    func testUserAlphaExamplesRenderWithDelimiterBoundaryNewlines() throws {
        let examples = [
            "\\[\n\\alpha\n\\]\n",
            "\\begin{aligned}\n\\alpha\n\\end{aligned}\n",
            "\\[\n\n\\alpha\n\n\\]\n",
            "\\[\r\n\\alpha\r\n\\]\r\n"
        ]
        for source in examples {
            let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: try parsedNodes(source)))
            let visible = rows.filter { $0.node.type != "blank_line" }
            XCTAssertEqual(visible.map(\.node.type), ["math_block"], source)
            XCTAssertEqual(rows.map(\.node.text).joined(), source)
            let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: try XCTUnwrap(visible.first).node.text))
            let rendered = try XCTUnwrap(OrgMathRendering.render(
                expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
            ), source)
            XCTAssertGreaterThan(rendered.image.size.width, 0)
            XCTAssertGreaterThan(rendered.image.size.height, 0)
        }
    }

    func testLiteralDisplaySyntaxStaysLiteral() throws {
        let source = #"Literal ~\[x\]~ and =\begin{aligned}x\end{aligned}= remain code."# + "\n"
        let rows = OrgPreviewOutline.rows(from: try parsedNodes(source))
        let grouped = OrgPreviewMathRows.group(rows)
        XCTAssertEqual(grouped.map(\.id), rows.map(\.id))
        XCTAssertFalse(grouped.contains { $0.node.type == "math_block" })
    }

    func testNestedMathEnvironmentKeepsOuterBoundsAndUTF8Offsets() throws {
        let prefix = "中文🙂 before "
        let expression = #"\begin{matrix}1 & \begin{matrix}2\\3\end{matrix}\\4 & 5\end{matrix}"#
        let source = prefix + expression + " after"
        let matches = OrgMathParser.matches(in: source)
        let match = try XCTUnwrap(matches.first)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(match.startByte, prefix.utf8.count)
        XCTAssertEqual(match.endByte, (prefix + expression).utf8.count)
        XCTAssertEqual(match.expression.original, expression)
        XCTAssertEqual(match.expression.latex, expression)
        XCTAssertEqual(match.expression.mode, .display)
    }

    func testEnvironmentParserIgnoresEscapedBeginAndEndTokens() throws {
        let expression = #"\begin{aligned}x &= 1 \\begin{aligned} \\end{aligned} + 2 \end{aligned}"#
        let parsed = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: expression))

        XCTAssertEqual(parsed.original, expression)
        XCTAssertEqual(parsed.latex, expression)
    }

    func testEnvironmentCloserAfterRowBreakRemainsUnescaped() throws {
        let expression = #"\begin{matrix}1 \\\end{matrix}"#

        XCTAssertEqual(OrgMathParser.soleDisplayExpression(in: expression)?.original, expression)
    }

    func testNestedEnvironmentNeedsOuterClosingToken() {
        let incomplete = #"\begin{matrix}1 & \begin{matrix}2\end{matrix}"#

        XCTAssertNil(OrgMathParser.soleDisplayExpression(in: incomplete))
        XCTAssertTrue(OrgMathParser.matches(in: #"\begin{unsupported}x\end{unsupported}"#).isEmpty)
    }

    func testLiteralUnclosedOpenersDoNotHideLaterDisplayMath() throws {
        for source in [
            #"Literal ~\[~ then \[x\]."#,
            #"Literal =\begin{aligned}= then \begin{aligned}x\end{aligned}."#
        ] {
            let source = source + "\n"
            let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: try parsedNodes(source)))
            XCTAssertEqual(rows.filter { $0.node.type == "math_block" }.count, 1)
            XCTAssertEqual(rows.map(\.node.text).joined(), source)
        }
    }

    func testMacroAndExportSnippetsRetainLiteralMathDelimiters() throws {
        let source = #"{{{tex(\[x\])}}} and @@latex:\[x\]@@."# + "\n"
        let rows = OrgPreviewOutline.rows(from: try parsedNodes(source))
        let grouped = OrgPreviewMathRows.group(rows)
        XCTAssertEqual(grouped.map(\.id), rows.map(\.id))
    }

    func testAlignedEnvironmentAcrossBlankLinesPreservesSurroundingChinese() throws {
        let formula = #"""
        \begin{aligned}

        \mathtt{fix} &= \lambda f. (\lambda x. f\ (\lambda y. x\ x\ y))\ (\lambda x. f\ (\lambda y. x\ x\ y))\\

        &= \lambda.(\lambda. 1\ (\lambda. (1\ 1)\ 0))(\lambda. 1\ (\lambda. (1\ 1)\ 0)); \\

        \mathtt{f} &= (\lambda x. x\ y\ (\lambda y. y\ x\ z)) \\

        &= (\lambda. 0\ 1\ (\lambda. 0\ 1\ 2));
        \end{aligned}
        """#
        let source = "* Terms and Contexts\n这是 *De Bruijn terms*，例如：\n" + formula
            + "\n下面定义了 De Bruijn terms，abstraction 写作 \\(\\lambda.t\\)。\n"
        let nodes = try parsedNodes(source)
        let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: nodes))
        let visible = rows.filter { $0.node.type != "blank_line" }
        XCTAssertEqual(visible.map(\.node.type), ["heading", "paragraph", "math_block", "paragraph"])
        let block = try XCTUnwrap(rows.first { $0.node.type == "math_block" })
        let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: block.node.text))
        XCTAssertEqual(expression.latex, formula)
        XCTAssertEqual(substring(source, utf8Range: block.node.startByte..<block.node.endByte), formula)
        XCTAssertEqual(rows.map(\.node.text).joined(), source)
        XCTAssertEqual(block.parentHeadingIDs, [nodes[0].id])
        XCTAssertTrue(visible[1].node.text.contains("这是 *De Bruijn terms*"))
        XCTAssertTrue(visible.last?.node.text.contains("下面定义了") == true)
        let render = try XCTUnwrap(OrgMathRendering.render(
            expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
        ))
        XCTAssertGreaterThan(render.image.size.height, 60)
        let image = UIGraphicsImageRenderer(size: render.image.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: render.image.size))
            render.image.draw(at: .zero)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Aligned De Bruijn formulas rendered"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBracketAndDollarDisplayMathSplitProseWithoutLosingMarkup() throws {
        for (open, close) in [(#"\["#, #"\]"#), ("$$", "$$")] {
            let formula = open + "\n\\begin{aligned}\nx &= 1 \\\\\n\ny &= 2\n\\end{aligned}\n" + close
            let source = "之前 *加粗* 与 [[https://example.com][链接]]。\n" + formula + "\n之后还有 \\(T_1\\) 和 *强调*。\n"
            let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: try parsedNodes(source)))
            let visible = rows.filter { $0.node.type != "blank_line" }
            XCTAssertEqual(visible.map(\.node.type), ["paragraph", "math_block", "paragraph"])
            XCTAssertEqual(rows.map(\.node.text).joined(), source)
            let block = try XCTUnwrap(visible.first { $0.node.type == "math_block" })
            let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: block.node.text))
            XCTAssertEqual(expression.original, formula)
            XCTAssertEqual(substring(source, utf8Range: block.node.startByte..<block.node.endByte), formula)
            XCTAssertNotNil(OrgMathRendering.render(expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light))
            let before = OrgPreviewMarkup.attributed(visible[0].node)
            XCTAssertEqual(before.runs.compactMap(\.link).count, 1)
            XCTAssertTrue(before.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
            let after = OrgPreviewMarkup.fragments(try XCTUnwrap(visible.last).node)
            XCTAssertTrue(after.contains { if case .math(let expression) = $0 { return expression.latex == "T_1" }; return false })
        }
    }

    func testDisplayDelimitersCanShareProseLinesAndContainBoundaryNewlines() throws {
        for (open, close, body) in [
            (#"\["#, #"\]"#, #"\frac{a}{b}"#),
            (#"\begin{aligned}"#, #"\end{aligned}"#, #"x &= 1 \\ y &= 2"#)
        ] {
            for leadingNewline in ["", "\n"] {
                for trailingNewline in ["", "\n"] {
                    let formula = open + leadingNewline + body + trailingNewline + close
                    let source = "前文 *强调* " + formula + " 后文 [[https://example.com][链接]]。\n"
                    let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: try parsedNodes(source)))
                    let visible = rows.filter { $0.node.type != "blank_line" }
                    XCTAssertEqual(visible.map(\.node.type), ["paragraph", "math_block", "paragraph"], source)
                    XCTAssertEqual(rows.map(\.node.text).joined(), source)
                    let block = try XCTUnwrap(visible.first { $0.node.type == "math_block" }, source)
                    XCTAssertEqual(block.node.text, formula)
                    let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: block.node.text))
                    XCTAssertNotNil(OrgMathRendering.render(expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light))
                }
            }
        }
    }

    func testUnclosedDisplayMathDoesNotConsumeHeadingsOrCodeBlocks() throws {
        let source = "* First\n\\[\nx=1\n\n* Second\n\\]\n#+BEGIN_SRC latex\n\\[ y=2 \\]\n#+END_SRC\n"
        let rows = OrgPreviewOutline.rows(from: try parsedNodes(source))
        let grouped = OrgPreviewMathRows.group(rows)
        XCTAssertEqual(grouped.map(\.id), rows.map(\.id))
        XCTAssertFalse(grouped.contains { $0.node.type == "math_block" })
    }

    func testAlignBlockUsesRawSourceInsteadOfOrgVerbatimNodes() async throws {
        let source = #"""
        \begin{align}
        \pi(30) &= 120\times30-4800 = -1200, \\
        \pi(40) &= 120\times40-4800 = 0, \\
        \pi(50) &= 120\times50-4800 = 1200.
        \end{align}
        """# + "\n"
        let nodes = try parsedNodes(source)
        XCTAssertTrue(nodes.contains { node in
            node.children.contains { $0.type == "verbatim" }
        })

        let rows = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: nodes))
        let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: rows[0].node.text))
        XCTAssertEqual(rows.filter { $0.node.type != "blank_line" }.map(\.node.type), ["math_block"])
        XCTAssertEqual(
            OrgMathRendering.compatibleLatex(expression.latex),
            source.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\begin{align}"#, with: #"\begin{aligned}"#)
                .replacingOccurrences(of: #"\end{align}"#, with: #"\end{aligned}"#)
        )
        let rendered = try XCTUnwrap(OrgMathRendering.render(
            expression,
            textStyle: .body,
            dynamicTypeSize: .large,
            colorScheme: .light
        ))
        let cached = try XCTUnwrap(OrgMathRendering.render(
            expression,
            textStyle: .body,
            dynamicTypeSize: .large,
            colorScheme: .light
        ))
        XCTAssertGreaterThan(rendered.image.size.width, 0)
        XCTAssertGreaterThan(rendered.image.size.height, 0)
        XCTAssertTrue(rendered === cached)

        let spans = await OrgSyntaxHighlighter().highlights(in: source)
        XCTAssertFalse(spans.contains { $0.kind == .verbatim })
    }

    func testCodeHighlightingPreservesSourceAndProducesStyledRuns() {
        let source = "let greeting = \"Hello\"\nprint(greeting)"
        let highlighted = OrgCodeHighlighting.attributed(
            source,
            language: "swift",
            colorScheme: .light,
            dynamicTypeSize: .large
        )
        let cached = OrgCodeHighlighting.attributed(
            source,
            language: "swift",
            colorScheme: .light,
            dynamicTypeSize: .large
        )

        XCTAssertEqual(String(highlighted.characters), source)
        XCTAssertEqual(highlighted, cached)
        XCTAssertGreaterThan(highlighted.runs.count, 1)
    }

    func testClockPresentationSupportsRunningAndCompletedEntries() throws {
        let nodes = try parsedNodes("CLOCK: [2026-09-19 Sat 09:00]--[2026-09-19 Sat 10:25] => 1:25\nCLOCK: [2026-09-19 Sat 11:00]\nCLOCK: => 0:05\n")
        let completed = OrgPreviewClockValue(nodes[0])
        XCTAssertEqual(completed.duration, "1h 25m")
        let interval = try XCTUnwrap(completed.interval(
            locale: Locale(identifier: "en_US"),
            now: try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        ))
        XCTAssertFalse(interval.contains("2026"))
        XCTAssertEqual(interval.components(separatedBy: "Sep 19").count - 1, 1)
        XCTAssertTrue(interval.contains("9:00"))
        XCTAssertTrue(interval.contains("10:25"))
        XCTAssertEqual(OrgPreviewClockValue(nodes[1]).duration, "Running")
        XCTAssertEqual(OrgPreviewClockValue(nodes[2]).duration, "5m")
    }

    func testDrawerTimestampPresentationOmitsCurrentYearAndKeepsOtherYears() throws {
        let source = "- Current [2026-09-19 Sat 10:00], old [2025-12-31 Wed]\n"
        let root = try XCTUnwrap(parsedNodes(source).first)
        let node = try XCTUnwrap(root.descendantsByID.values.first { $0.type == "list_item_content" })
        let fragments = OrgPreviewMarkup.readableDrawerFragments(
            node,
            trimSpaces: true,
            locale: Locale(identifier: "en_US"),
            now: try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        )
        let rendered = fragments.compactMap { fragment -> String? in
            guard case .text(let value) = fragment else { return nil }
            return String(value.characters)
        }.joined()

        XCTAssertFalse(rendered.contains("2026"))
        XCTAssertTrue(rendered.contains("2025"))
        XCTAssertTrue(rendered.contains("10:00"))
    }

    func testDrawerAndProgressEditorStylesPreserveSourceAndCaret() async throws {
        var source = "* TODO 进度 [2/3]\n:LOGBOOK:\nCLOCK: => 1:25\n:END:\n"
        let highlights = await OrgSyntaxHighlighter().highlights(in: source)
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: highlights)
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(usingTextLayoutManager: true)
        textView.text = source
        textView.selectedRange = NSRange(location: 8, length: 2)
        for scheme in [ColorScheme.light, .dark] {
            coordinator.apply(text: source, highlights: highlights, to: textView, colorScheme: scheme,
                              dynamicTypeSize: .accessibility1, colorSchemeContrast: .increased)
            for kind in [OrgHighlightKind.drawerDelimiter, .clock, .progress] {
                let span = try XCTUnwrap(highlights.first { $0.kind == kind })
                let font = try XCTUnwrap(textView.textStorage.attribute(.font, at: span.range.location, effectiveRange: nil) as? UIFont)
                XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
                XCTAssertNotNil(textView.textStorage.attribute(.backgroundColor, at: span.range.location, effectiveRange: nil))
            }
            XCTAssertEqual(textView.text, source)
            XCTAssertEqual(textView.selectedRange, NSRange(location: 8, length: 2))
        }
    }

    func testDefinitionContainerRendersErasureMathWithoutOrgUnderlineParsing() throws {
        let formula = #"""
        \begin{aligned}

        & \operatorname{erase}(x) &&= x \\

        & \operatorname{erase}(\lambda x : T_1 . t_2) &&= \lambda x. \operatorname{erase}(t_2) \\

        & \operatorname{erase}(t_1\ t_2) &&= \operatorname{erase}(t_1)\ \operatorname{erase}(t_2) \\

        & \operatorname{erase}(\lambda X. t_2) &&= \operatorname{erase}(t_2) \\

        & \operatorname{erase}(t_1\ [T_2]) &&= \operatorname{erase}(t_1) \\
        \end{aligned}
        """#
        let source = "#+begin_definition\n*(erasure)*\nThe erasure of a term \\(t\\) in System F is defined as follows:\n"
            + formula + "\n#+end_definition\nAfter the definition.\n"
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "erasure.org", title: "Erasure", contents: source, kind: .org)
        ]).first)
        let rows = OrgPreviewOutline.rows(from: document.root.children)
        let definition = try XCTUnwrap(rows.first { $0.node.type == "custom_block" })
        let children = OrgPreviewMathRows.group(OrgPreviewOutline.rows(from: definition.node.children))
        let formulas = children.filter { $0.node.type == "math_block" }
        XCTAssertEqual(formulas.count, 1)
        let math = try XCTUnwrap(formulas.first)
        XCTAssertEqual(math.node.text, formula)
        XCTAssertEqual(substring(source, utf8Range: math.node.startByte..<math.node.endByte), formula)
        let expression = try XCTUnwrap(OrgMathParser.soleDisplayExpression(in: math.node.text))
        XCTAssertNotNil(OrgMathRendering.render(expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light))
        XCTAssertTrue(children.contains { $0.node.text.contains("The erasure of a term") })
        XCTAssertTrue(rows.last?.node.text.contains("After the definition.") == true)
    }

    private func parsedNodes(_ source: String) throws -> [ParsedOrgNode] {
        let document = try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "ui.org", title: "UI", contents: source, kind: .org)
        ]).first)
        XCTAssertFalse(document.hasError)
        return document.root.children
    }

    private func substring(_ source: String, utf8Range: Range<Int>) -> String {
        String(decoding: Array(source.utf8)[utf8Range], as: UTF8.self)
    }

    func testPresentationAttributesPreserveSelectionAndSemanticTraits() async throws {
        var source = "* NEXT [#B] 编写 [[id:文档][说明]] :dev:\n#+BEGIN_SRC swift\nlet value = 1\n#+END_SRC\n"
        let highlighter = try XCTUnwrap(OrgSyntaxHighlighter())
        let highlights = await highlighter.highlights(in: source)
        let binding = Binding(get: { source }, set: { source = $0 })
        let editor = OrgSyntaxTextEditor(text: binding, highlights: highlights)
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(usingTextLayoutManager: true)

        coordinator.apply(
            text: source,
            highlights: highlights,
            to: textView,
            colorScheme: .light,
            dynamicTypeSize: .large,
            colorSchemeContrast: .standard
        )
        textView.selectedRange = NSRange(location: 12, length: 2)
        coordinator.apply(
            text: source,
            highlights: highlights,
            to: textView,
            colorScheme: .dark,
            dynamicTypeSize: .large,
            colorSchemeContrast: .standard
        )

        XCTAssertEqual(textView.text, source)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 12, length: 2))

        let nextRange = try XCTUnwrap(highlights.first(where: { $0.kind == .todo })?.range)
        let nextFont = try XCTUnwrap(textView.textStorage.attribute(.font, at: nextRange.location, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(nextFont.fontDescriptor.symbolicTraits.contains(.traitBold))

        let linkRange = try XCTUnwrap(highlights.first(where: { $0.kind == .link })?.range)
        let underline = textView.textStorage.attribute(.underlineStyle, at: linkRange.location, effectiveRange: nil) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue)

        let sourceBlockRange = try XCTUnwrap(highlights.first(where: { $0.kind == .sourceBlock })?.range)
        XCTAssertNotNil(textView.textStorage.attribute(.backgroundColor, at: sourceBlockRange.location, effectiveRange: nil))
    }

    func testStaleHighlightRangesAreClampedWithoutMovingCaret() {
        var source = "* TODO 短文本\n"
        let stale = [OrgHighlightSpan(range: NSRange(location: 2, length: 10_000), kind: .todo)]
        let binding = Binding(get: { source }, set: { source = $0 })
        let editor = OrgSyntaxTextEditor(text: binding, highlights: stale)
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(usingTextLayoutManager: true)

        coordinator.apply(
            text: source,
            highlights: stale,
            to: textView,
            colorScheme: .dark,
            dynamicTypeSize: .accessibility2,
            colorSchemeContrast: .increased
        )
        textView.selectedRange = NSRange(location: 4, length: 0)
        coordinator.apply(
            text: source,
            highlights: stale,
            to: textView,
            colorScheme: .dark,
            dynamicTypeSize: .accessibility2,
            colorSchemeContrast: .standard
        )

        XCTAssertEqual(textView.selectedRange, NSRange(location: 4, length: 0))
        XCTAssertEqual(textView.textStorage.length, (source as NSString).length)
    }
}

@MainActor
final class OrgMathCompatibilityTests: XCTestCase {
    func testRaisedSubtypeRelationProducesAnActualInlineMathImage() throws {
        let source = #"T = \forall X \mathrel{\raisebox{0.1ex}{\scriptsize$<$}}\!\colon T_1. T_2"#
        let projected = OrgMathRendering.compatibleLatex(source)
        XCTAssertEqual(projected, #"T = \forall X <\!\colon T_1. T_2"#)

        var renderer = MathImage(latex: projected, fontSize: 17, textColor: .black, labelMode: .text)
        let (error, image, layout) = renderer.asImage()
        XCTAssertNil(error)
        let renderedImage = try XCTUnwrap(image)
        let renderedLayout = try XCTUnwrap(layout)
        XCTAssertGreaterThan(renderedImage.size.width, 0)
        XCTAssertGreaterThan(renderedImage.size.height, 0)
        XCTAssertGreaterThan(renderedLayout.ascent, 0)
        XCTAssertTrue(renderedLayout.descent.isFinite)

        // The projection must also work through the preview's rendering path
        // without modifying the expression used by source editing/fallback.
        let original = #"\("# + source + #"\)"#
        let expression = OrgMathExpression(latex: source, original: original, mode: .inline)
        let preview = try XCTUnwrap(OrgMathRendering.render(
            expression, textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
        ))
        XCTAssertGreaterThan(preview.image.size.width, 0)
        XCTAssertEqual(expression.latex, source)
        XCTAssertEqual(expression.original, original)
    }

    func testRaisedRelationProjectionRetainsSupportedRelationAndSurroundingMath() throws {
        let source = #"x \mathrel { \raisebox{+.1ex}{ \scriptsize $>$ } } y \mathrel{\raisebox{-0.2pt}{\scriptsize$=$}} z"#
        let projected = OrgMathRendering.compatibleLatex(source)
        var error: NSError?
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: projected, error: &error))
        XCTAssertNil(error)
        XCTAssertEqual(list.atoms.filter { $0.type == .relation }.map(\.nucleus), [">", "="])
        XCTAssertEqual(list.atoms.filter { $0.type == .variable }.map(\.nucleus), ["x", "y", "z"])
        var renderer = MathImage(latex: projected, fontSize: 17, textColor: .black)
        let (renderError, image, _) = renderer.asImage()
        XCTAssertNil(renderError)
        XCTAssertNotNil(image)
    }

    func testUnsupportedRaisedPayloadIsPreservedForLiteralFallback() {
        let examples = [
            #"\mathrel{\raisebox{0.1ex}{\scriptsize$\not<$}}"#,
            #"\mathrel{\raisebox{0.1ex}{\scriptsize$a<b$}}"#,
            #"\raisebox{0.1ex}{\scriptsize$<$}"#,
            #"\mathrel{\raisebox{\height}{\scriptsize$<$}}"#,
            #"\\mathrel{\raisebox{0.1ex}{\scriptsize$<$}}"#,
        ]
        for source in examples {
            XCTAssertEqual(OrgMathRendering.compatibleLatex(source), source)
        }
        let unsupported = examples[0]
        XCTAssertNil(OrgMathRendering.render(
            OrgMathExpression(latex: unsupported, original: unsupported, mode: .inline),
            textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
        ))
    }
    func testErasureEquationsRenderWithLeadingAndEmptyAlignmentColumns() throws {
        let source = #"""
        \begin{aligned}

        & \operatorname{erase}(x) &&= x \\

        & \operatorname{erase}(\lambda x : T_1 . t_2) &&= \lambda x. \operatorname{erase}(t_2) \\

        & \operatorname{erase}(t_1\ t_2) &&= \operatorname{erase}(t_1)\ \operatorname{erase}(t_2) \\

        & \operatorname{erase}(\lambda X. t_2) &&= \operatorname{erase}(t_2) \\

        & \operatorname{erase}(t_1\ [T_2]) &&= \operatorname{erase}(t_1) \\
        \end{aligned}
        """#
        let projected = OrgMathRendering.compatibleLatex(source)
        XCTAssertEqual(projected, source)

        var parseError: NSError?
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: projected, error: &parseError))
        XCTAssertNil(parseError)
        let table = try XCTUnwrap(list.atoms.first as? MTMathTable)
        XCTAssertEqual(table.numColumns, 4)
        XCTAssertGreaterThanOrEqual(table.numRows, 5)
        XCTAssertEqual(table.get(alignmentForColumn: 1), .left)
        XCTAssertEqual(table.get(alignmentForColumn: 3), .left)
        XCTAssertTrue(table.cells[0][0].atoms.isEmpty)
        XCTAssertTrue(table.cells[0][2].atoms.isEmpty)

        let rendered = try XCTUnwrap(OrgMathRendering.render(
            OrgMathExpression(latex: source, original: source, mode: .display),
            textStyle: .body, dynamicTypeSize: .large, colorScheme: .light
        ))
        XCTAssertGreaterThan(rendered.image.size.width, 0)
        XCTAssertGreaterThan(rendered.image.size.height, 80)
    }

    func testCompatibilityProjectionPreservesAllAlignmentSyntax() {
        for source in [
            #"\begin{aligned}a &= b & c &= d \\ e &= f & g &= h\end{aligned}"#,
            #"\begin{aligned}&x&&=\begin{matrix}a&b\\c&d\end{matrix}\end{aligned}"#,
            #"\begin{cases}x & x > 0 \\ 0 & x \le 0\end{cases}"#,
        ] {
            XCTAssertEqual(OrgMathRendering.compatibleLatex(source), source)
        }
        XCTAssertEqual(
            OrgMathRendering.compatibleLatex(#"\begin{aligned}\text{A\&B} &= x\end{aligned}"#),
            #"\begin{aligned}\text{A\orgendaAmpersand{}B} &= x\end{aligned}"#
        )
    }

}
