import SwiftUI
import UIKit
import XCTest
@testable import Orgenda

@MainActor
final class OrgSyntaxTextEditorTests: XCTestCase {
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

}
