import SwiftUI
import UIKit

/// A plain-text Org editor whose presentation attributes are supplied by the
/// tree-sitter highlighter. Text remains plain in the binding and text storage;
/// syntax attributes are reapplied in place so selection, scrolling, undo, and
/// TextKit 2's layout state stay intact.
struct OrgSyntaxTextEditor: UIViewRepresentable {
    @Binding private var text: String
    private let highlights: [OrgHighlightSpan]
    private let isEditable: Bool
    private let session: OrgEditorSession?
    private let isActive: Bool
    private let externalRevision: UInt64

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        text: Binding<String>,
        highlights: [OrgHighlightSpan],
        isEditable: Bool = true,
        session: OrgEditorSession? = nil,
        isActive: Bool = true,
        externalRevision: UInt64 = 0
    ) {
        _text = text
        self.highlights = highlights
        self.isEditable = isEditable
        self.session = session
        self.isActive = isActive
        self.externalRevision = externalRevision
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> OrgEditorContainer {
        // Opt in explicitly so future editor work cannot accidentally fall back
        // to NSLayoutManager/TextKit 1 APIs.
        let textView: UITextView = session == nil
            ? UITextView(usingTextLayoutManager: true)
            : OrgEditorTextView.make()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = .systemTeal
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        // The UIKit editor needs its own edge style; SwiftUI's modifier only
        // configures the native preview scroll view.
        textView.topEdgeEffect.style = .soft
        textView.bottomEdgeEffect.style = .soft
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 20, right: 14)
        textView.textContainer.lineFragmentPadding = 0

        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        let container = OrgEditorContainer(textView: textView, session: isEditable ? session : nil)
        configureInteraction(for: textView)
        context.coordinator.connect(textView)
        context.coordinator.apply(
            text: text,
            highlights: highlights,
            to: textView,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize,
            colorSchemeContrast: colorSchemeContrast
        )
        return container
    }

    func updateUIView(_ container: OrgEditorContainer, context: Context) {
        let textView = container.textView
        context.coordinator.parent = self
        context.coordinator.acceptRevision(externalRevision, in: textView)
        configureInteraction(for: textView)

        context.coordinator.apply(
            text: text,
            highlights: highlights,
            to: textView,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize,
            colorSchemeContrast: colorSchemeContrast
        )
        if !isActive, textView.isFirstResponder { textView.resignFirstResponder() }
        if isActive { session?.applyPendingSearchSelection() }
    }

    private func configureInteraction(for textView: UITextView) {
        textView.isUserInteractionEnabled = isActive
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isHidden = !isActive
        textView.isAccessibilityElement = isActive
        textView.accessibilityElementsHidden = !isActive
        textView.accessibilityLabel = isEditable ? String(localized: "Org source editor") : String(localized: "Org source")
        textView.accessibilityIdentifier = "Org source editor"
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: OrgSyntaxTextEditor

        private var isApplyingPresentation = false
        private weak var textView: UITextView?
        private var externalRevision: UInt64
        private var skipsSourceUndo = false
        private var isApplyingCommand = false
        private var selectionBeforeInput: NSRange?
        private var lastTypingSelection: NSRange?
        private var ownsTypingGroup = false
        private var typingTask: Task<Void, Never>?
        private var lastText: String?
        private var lastHighlights: [OrgHighlightSpan] = []
        private var lastColorScheme: ColorScheme?
        private var lastDynamicTypeSize: DynamicTypeSize?
        private var lastColorSchemeContrast: ColorSchemeContrast?

        init(parent: OrgSyntaxTextEditor) {
            self.parent = parent
            externalRevision = parent.externalRevision
        }

        func connect(_ textView: UITextView) {
            self.textView = textView
            guard let session = parent.session, parent.isEditable else { return }
            session.attach(textView)
            session.finishTyping = { [weak self] in self?.finishTyping() }
            (textView as? OrgEditorTextView)?.documentUndoManager.finishTyping = { [weak self] in self?.finishTyping() }
            session.synchronizeSource = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.apply(text: self.parent.text, highlights: self.parent.highlights, to: textView,
                           colorScheme: self.parent.colorScheme, dynamicTypeSize: self.parent.dynamicTypeSize,
                           colorSchemeContrast: self.parent.colorSchemeContrast)
            }
            session.performEdit = { [weak self, weak textView] edit, name in
                guard let self, let textView else { return }
                textView.unmarkText()
                self.replace(edit, name: name, in: textView)
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }

        func acceptRevision(_ revision: UInt64, in textView: UITextView) {
            guard revision != externalRevision else { return }
            externalRevision = revision
            // A refreshed disk version is not a user edit and must never be undone
            // over another writer's changes.
            finishTyping()
            textView.undoManager?.removeAllActions()
            skipsSourceUndo = true
            Task { @MainActor [weak self] in self?.parent.session?.refreshHistory() }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if let previous = lastTypingSelection, previous != textView.selectedRange,
               textView.markedTextRange == nil {
                finishTyping()
            }
            selectionBeforeInput = textView.selectedRange
            guard parent.session != nil, text == "\n", textView.markedTextRange == nil,
                  let edit = OrgInputCommands.newline(source: textView.text ?? "", selection: range) else { return true }
            replace(edit, name: String(localized: "Continue list"), in: textView)
            textView.scrollRangeToVisible(textView.selectedRange)
            return false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            (textView.superview as? OrgEditorContainer)?.setKeyboardFocused(true)
            Task { @MainActor [weak self] in self?.parent.session?.isKeyboardFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            (textView.superview as? OrgEditorContainer)?.setKeyboardFocused(false)
            finishTyping()
            Task { @MainActor [weak self] in self?.parent.session?.isKeyboardFocused = false }
        }

        /// Registers only text mutations; syntax presentation never enters history.
        func replace(_ edit: OrgTextEdit, name: String, in textView: UITextView) {
            let storage = textView.textStorage
            guard edit.range.location != NSNotFound, NSMaxRange(edit.range) <= storage.length else { return }
            let previous = (storage.string as NSString).substring(with: edit.range)
            let previousSelection = textView.selectedRange
            let inverse = OrgTextEdit(range: NSRange(location: edit.range.location, length: edit.replacement.utf16.count),
                                      replacement: previous, selection: previousSelection)
            finishTyping()
            registerUndo(inverse, name: name, in: textView)
            let undoManager = (textView as? OrgEditorTextView)?.undoManager
            undoManager?.disableUndoRegistration()
            isApplyingPresentation = true
            isApplyingCommand = true
            let offset = textView.contentOffset
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.selectedRange = OrgSyntaxPresentation.clampedSelection(edit.selection, to: storage.length)
            textView.setContentOffset(offset, animated: false)
            isApplyingPresentation = false
            undoManager?.enableUndoRegistration()
            textViewDidChange(textView)
            isApplyingCommand = false
            Task { @MainActor [weak self] in self?.parent.session?.refreshHistory() }
        }

        private func registerUndo(_ inverse: OrgTextEdit, name: String, in textView: UITextView) {
            let manager = textView.undoManager
            let needsGroup = manager?.groupingLevel == 0 && manager?.isUndoing == false && manager?.isRedoing == false
            if needsGroup { manager?.beginUndoGrouping() }
            textView.undoManager?.registerUndo(withTarget: self) { [weak textView] coordinator in
                guard let textView else { return }
                coordinator.replace(inverse, name: name, in: textView)
            }
            textView.undoManager?.setActionName(name)
            if needsGroup { manager?.endUndoGrouping() }
        }

        func finishTyping() {
            typingTask?.cancel()
            typingTask = nil
            if ownsTypingGroup {
                ownsTypingGroup = false
                textView?.undoManager?.endUndoGrouping()
            }
            lastTypingSelection = nil
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingPresentation else { return }

            let newText = textView.text ?? ""
            if parent.session != nil, !isApplyingCommand, parent.text != newText {
                let difference = OrgInputCommands.difference(from: parent.text, to: newText)
                let old = (parent.text as NSString).substring(with: difference.range)
                if textView.undoManager?.groupingLevel == 0 {
                    textView.undoManager?.beginUndoGrouping()
                    ownsTypingGroup = true
                }
                registerUndo(OrgTextEdit(range: NSRange(location: difference.range.location, length: difference.replacement.utf16.count),
                                         replacement: old, selection: selectionBeforeInput ?? NSRange(location: difference.range.location, length: 0)),
                             name: String(localized: "Typing"), in: textView)
                typingTask?.cancel()
                typingTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    self?.finishTyping()
                }
            }
            // The storage already contains this user edit. Mark the revision as
            // current before SwiftUI echoes the binding back, otherwise every
            // keystroke would restyle the whole document using stale spans.
            lastText = newText
            lastTypingSelection = textView.selectedRange
            if parent.text != newText {
                parent.text = newText
            }
            Task { @MainActor [weak self] in self?.parent.session?.refreshHistory() }
        }

        func apply(
            text: String,
            highlights: [OrgHighlightSpan],
            to textView: UITextView,
            colorScheme: ColorScheme,
            dynamicTypeSize: DynamicTypeSize,
            colorSchemeContrast: ColorSchemeContrast
        ) {
            // Attribute and backing-string mutations during an active marked range
            // can cancel or duplicate CJK composition. The binding still receives
            // delegate updates; SwiftUI will call us again once composition ends.
            guard textView.markedTextRange == nil else { return }

            let needsRefresh = lastText != text
                || lastHighlights != highlights
                || lastColorScheme != colorScheme
                || lastDynamicTypeSize != dynamicTypeSize
                || lastColorSchemeContrast != colorSchemeContrast
            guard needsRefresh else { return }

            if lastText != nil, textView.text != text, parent.session != nil, !skipsSourceUndo {
                let difference = OrgInputCommands.difference(from: textView.text ?? "", to: text)
                let selection = textView.selectedRange
                let delta = difference.replacement.utf16.count - difference.range.length
                func mapped(_ offset: Int) -> Int {
                    if offset <= difference.range.location { return offset }
                    if offset >= NSMaxRange(difference.range) { return offset + delta }
                    return difference.range.location + min(offset - difference.range.location, difference.replacement.utf16.count)
                }
                let start = mapped(selection.location)
                let adjusted = NSRange(location: start, length: max(0, mapped(NSMaxRange(selection)) - start))
                replace(OrgTextEdit(range: difference.range, replacement: difference.replacement, selection: adjusted),
                        name: String(localized: "Change document"), in: textView)
            }
            skipsSourceUndo = false

            let selectedRange = textView.selectedRange
            let contentOffset = textView.contentOffset
            let textStorage = textView.textStorage
            let font = OrgSyntaxPresentation.bodyFont(compatibleWith: textView.traitCollection)
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label,
            ]

            isApplyingPresentation = true
            let undoManager = (textView as? OrgEditorTextView)?.undoManager
            undoManager?.disableUndoRegistration()
            // These UIKit defaults feed the insertion point. They are set before
            // syntax attributes so they cannot flatten highlighted fonts/colors.
            textView.font = font
            textView.textColor = .label
            textStorage.beginEditing()

            if textStorage.string != text {
                textStorage.replaceCharacters(
                    in: NSRange(location: 0, length: textStorage.length),
                    with: text
                )
            }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            if fullRange.length > 0 {
                textStorage.setAttributes(baseAttributes, range: fullRange)

                for highlight in highlights {
                    guard let range = OrgSyntaxPresentation.clamped(highlight.range, to: fullRange.length) else {
                        continue
                    }
                    OrgSyntaxPresentation.apply(
                        highlight.kind,
                        to: textStorage,
                        range: range,
                        colorSchemeContrast: colorSchemeContrast
                    )
                }
                OrgSyntaxPresentation.applyWorkflowHeadingColors(highlights, to: textStorage)
            }

            textStorage.endEditing()
            textView.typingAttributes = baseAttributes
            textView.selectedRange = OrgSyntaxPresentation.clampedSelection(selectedRange, to: textStorage.length)
            textView.setContentOffset(contentOffset, animated: false)
            isApplyingPresentation = false
            undoManager?.enableUndoRegistration()

            lastText = text
            lastHighlights = highlights
            lastColorScheme = colorScheme
            lastDynamicTypeSize = dynamicTypeSize
            lastColorSchemeContrast = colorSchemeContrast
        }

    }
}
