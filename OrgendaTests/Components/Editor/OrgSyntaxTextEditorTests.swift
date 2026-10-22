import SwiftUI
import UIKit
import XCTest
@testable import Orgenda

@MainActor
final class OrgSyntaxTextEditorTests: XCTestCase {
    func testListContinuationRequiresTheMatchingBlockEnd() throws {
        let blocks = [
            ("  #+begin_src org", "#+END_EXAMPLE", "  #+end_src"),
            ("#+BEGIN_SRC org", "#+END_SRC_extra", "#+END_SRC"),
            ("#+BEGIN_SRC org", "#+END_SRC not-a-delimiter", "#+END_SRC"),
            ("#+BEGIN: generated", "#+END_SRC", "#+END:"),
            ("#+BEGIN_EXAMPLE", ":LOGBOOK:", "#+END_EXAMPLE"),
            ("  #+BEGIN_QUOTE", "#+END_QUOTE_extra", "  #+END_QUOTE"),
            ("#+BEGIN_note", "#+END_other", "#+END_note"),
            ("#+BEGIN_note", "#+BEGIN_nested\n#+END_nested", "#+END_note"),
            (":狀態-LOG:", "Previous log", ":END:"),
        ]
        for newline in ["\n", "\r\n"] {
            for (begin, body, end) in blocks {
                let literal = [begin, body, "- literal item"].joined(separator: newline)
                XCTAssertNil(OrgInputCommands.newline(
                    source: literal, selection: NSRange(location: literal.utf16.count, length: 0)
                ), begin + newline + body)
                let source = [literal, end, "- real item"].joined(separator: newline)
                let edit = try XCTUnwrap(OrgInputCommands.newline(
                    source: source, selection: NSRange(location: source.utf16.count, length: 0)
                ))
                XCTAssertEqual(edit.replacement, newline + "- ")
                XCTAssertEqual((source as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
                               source + newline + "- ")
            }
        }
    }

    func testUnicodeSourceChangesCanBeUndoneAndRedone() {
        let changes = [
            ("* Caf\u{00E9}\n", "* Cafe\u{301}\n"),
            ("e\u{301} old", "\u{00E9} new"),
            ("old \u{00E9}", "new e\u{301}"),
            ("* 👩🏽‍💻 Task\n", "* 👩🏽‍🔬 Task\n"),
        ]
        for (original, updated) in changes {
            var source = original
            let session = OrgEditorSession()
            let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: nil, session: session)
            let coordinator = editor.makeCoordinator()
            let textView = OrgEditorTextView.make()
            textView.delegate = coordinator
            coordinator.connect(textView)
            coordinator.apply(text: source, highlights: nil, to: textView, colorScheme: .light,
                              dynamicTypeSize: .large, colorSchemeContrast: .standard)

            source = updated
            coordinator.apply(text: source, highlights: nil, to: textView, colorScheme: .light,
                              dynamicTypeSize: .large, colorSchemeContrast: .standard)
            XCTAssertEqual(Array(textView.text.utf8), Array(updated.utf8))
            session.undo()
            XCTAssertEqual(Array(source.utf8), Array(original.utf8))
            session.redo()
            XCTAssertEqual(Array(source.utf8), Array(updated.utf8))
        }
    }

    func testNativeCanonicalUnicodeEditPublishesExactSourceAndCanBeUndone() {
        var source = "* Caf\u{00E9}\n"
        let original = source
        let updated = "* Cafe\u{301}\n"
        let session = OrgEditorSession()
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: nil, session: session)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.apply(text: source, highlights: nil, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        textView.selectedRange = NSRange(location: 5, length: 1)
        textView.insertText("e\u{301}")

        XCTAssertEqual(Array(source.utf8), Array(updated.utf8))
        session.undo()
        XCTAssertEqual(Array(source.utf8), Array(original.utf8))
        session.redo()
        XCTAssertEqual(Array(source.utf8), Array(updated.utf8))
    }

    func testCanonicalUnicodeDiskRefreshReplacesSourceWithoutUndoHistory() {
        var source = "* Caf\u{00E9}\n"
        let session = OrgEditorSession()
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: nil, session: session)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.apply(text: source, highlights: nil, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        session.perform(.heading)
        XCTAssertTrue(textView.undoManager?.canUndo == true)

        source = "** Cafe\u{301}\n"
        coordinator.acceptRevision(1, in: textView)
        coordinator.apply(text: source, highlights: nil, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        XCTAssertEqual(Array(textView.text.utf8), Array(source.utf8))
        XCTAssertFalse(textView.undoManager?.canUndo == true)
        session.undo()
        XCTAssertEqual(Array(source.utf8), Array("** Cafe\u{301}\n".utf8))
    }

    func testMarkedCompositionIsNotInterruptedByHighlightingAndCanBeUndone() async throws {
        var source = "* Note\n"
        let original = source
        let highlighter = OrgSyntaxHighlighter()
        let initialHighlights = await highlighter.highlights(in: source)
        let session = OrgEditorSession()
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: nil, session: session)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.apply(text: source, highlights: initialHighlights, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        textView.selectedRange = NSRange(location: source.utf16.count, length: 0)
        textView.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
        XCTAssertNotNil(textView.markedTextRange)
        coordinator.apply(text: source, highlights: initialHighlights, to: textView, colorScheme: .dark,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        XCTAssertNotNil(textView.markedTextRange)
        textView.setMarkedText("中文🙂", selectedRange: NSRange(location: 4, length: 0))
        textView.unmarkText()
        XCTAssertEqual(source, original + "中文🙂")
        let selection = textView.selectedRange
        let finalHighlights = await highlighter.highlights(in: source)
        // A superseded parse must not restore its old text or enter undo history.
        coordinator.apply(text: source, highlights: initialHighlights, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        coordinator.apply(text: source, highlights: finalHighlights, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        XCTAssertEqual(textView.selectedRange, selection)
        XCTAssertEqual(textView.text, original + "中文🙂")
        session.undo()
        XCTAssertEqual(source, original)
        session.redo()
        XCTAssertEqual(source, original + "中文🙂")
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testLocalHighlightingMatchesFullPresentationAfterAccumulatedEdits() async {
        var source = "#+TODO: OPEN | DONE\n* OPEN First\nBody *bold* 中文🙂\n* OPEN Last\nUnchanged\n"
        let highlighter = OrgSyntaxHighlighter()
        let initial = await highlighter.highlights(in: source)
        let editor = OrgSyntaxTextEditor(text: Binding(get: { source }, set: { source = $0 }), highlights: nil)
        let coordinator = editor.makeCoordinator()
        let textView = OrgEditorTextView.make()
        textView.delegate = coordinator
        coordinator.apply(text: source, highlights: initial, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        let sentinel = NSAttributedString.Key("UnchangedBlock")
        textView.textStorage.addAttribute(sentinel, value: true, range: (source as NSString).range(of: "Last"))
        textView.selectedRange = (source as NSString).range(of: "First")
        textView.insertText("Edited")
        let updated = await highlighter.highlights(in: source)
        coordinator.apply(text: source, highlights: updated, to: textView, colorScheme: .light,
                          dynamicTypeSize: .large, colorSchemeContrast: .standard)
        let initialRevisions = Set(initial.blocks.map(\.revision))
        XCTAssertEqual(updated.blocks.filter { !initialRevisions.contains($0.revision) }.count, 1)
        XCTAssertEqual(textView.textStorage.attribute(sentinel, at: (source as NSString).range(of: "Last").location,
                                                       effectiveRange: nil) as? Bool, true)
        textView.textStorage.removeAttribute(sentinel, range: NSRange(location: 0, length: textView.textStorage.length))

        let batches = [
            [("*bold*", "/italic/"), ("Last", "最后"), ("Body /italic/ 中文🙂", "中文")],
            [("中文", ""), ("Edited", "*nested*")],
            [("#+TODO: OPEN | DONE", "#+TODO: NEXT | DONE")],
            [("Unchanged\n", "")],
        ]
        for edits in batches {
            for (before, after) in edits {
                textView.selectedRange = (source as NSString).range(of: before)
                textView.insertText(after)
            }
            // The editor may receive several source changes before the next parse finishes.
            coordinator.apply(text: source, highlights: updated, to: textView, colorScheme: .light,
                              dynamicTypeSize: .large, colorSchemeContrast: .standard)
            let highlights = await highlighter.highlights(in: source)
            coordinator.apply(text: source, highlights: highlights, to: textView, colorScheme: .light,
                              dynamicTypeSize: .large, colorSchemeContrast: .standard)

            let fresh = await OrgSyntaxHighlighter().highlights(in: source)
            let fullEditor = OrgSyntaxTextEditor(text: .constant(source), highlights: fresh)
            let fullView = OrgEditorTextView.make()
            fullEditor.makeCoordinator().apply(text: source, highlights: fresh, to: fullView, colorScheme: .light,
                                               dynamicTypeSize: .large, colorSchemeContrast: .standard)
            XCTAssertTrue(textView.textStorage.isEqual(to: fullView.textStorage), source)
        }
    }

}
