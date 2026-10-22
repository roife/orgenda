import Observation
import UIKit

/// The document owns this session; the text view survives Edit/Preview switches.
@MainActor
@Observable
final class OrgEditorSession {
    private(set) var canUndo = false
    private(set) var canRedo = false
    var isDatePresented = false
    var isKeyboardFocused = false
    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored var synchronizeSource: (() -> Void)?
    @ObservationIgnored var performEdit: ((OrgTextEdit, String) -> Void)?
    @ObservationIgnored var finishTyping: (() -> Void)?
    @ObservationIgnored var updateAccessory: ((Bool, Bool) -> Void)?
    @ObservationIgnored var onReadingPositionChange: ((Int) -> Void)?
    @ObservationIgnored private var pendingReadingByte: Int?
    @ObservationIgnored private(set) var isRestoringReadingPosition = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var resumesKeyboard = false
    @ObservationIgnored private var dateSelection: NSRange?
    @ObservationIgnored private var pendingSearchQuery: String?

    func attach(_ textView: UITextView) {
        self.textView = textView
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers = [Notification.Name.NSUndoManagerDidCloseUndoGroup,
                     .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: textView.undoManager, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshHistory() }
            }
        }
    }

    deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }

    func refreshHistory() {
        let manager = textView?.undoManager
        canUndo = manager?.canUndo == true
        canRedo = manager?.canRedo == true
        updateAccessory?(canUndo, canRedo)
    }

    func undo() {
        synchronizeSource?()
        textView?.unmarkText()
        finishTyping?()
        textView?.undoManager?.undo()
        refreshHistory()
    }

    func redo() {
        synchronizeSource?()
        finishTyping?()
        textView?.undoManager?.redo()
        refreshHistory()
    }

    func suspendEditing() {
        guard let textView else { return }
        resumesKeyboard = textView.isFirstResponder
        textView.unmarkText()
        finishTyping?()
        textView.resignFirstResponder()
    }

    func captureReadingPosition() {
        guard !isRestoringReadingPosition, let textView, !textView.isHidden,
              textView.bounds.width > 0, textView.bounds.height > 0 else { return }
        let point = CGPoint(x: textView.textContainerInset.left,
                            y: max(textView.textContainerInset.top,
                                   textView.contentOffset.y + textView.adjustedContentInset.top))
        guard let position = textView.closestPosition(to: point) else { return }
        let offset = textView.offset(from: textView.beginningOfDocument, to: position)
        let source = textView.text as NSString? ?? ""
        onReadingPositionChange?(source.substring(to: min(max(0, offset), source.length)).utf8.count)
    }

    func restoreReadingPosition(sourceByte: Int) {
        pendingReadingByte = max(0, sourceByte)
        isRestoringReadingPosition = true
        textView?.superview?.setNeedsLayout()
    }

    /// Called after the previously hidden editor has its full viewport again.
    func applyPendingReadingPosition() {
        guard let byte = pendingReadingByte, let textView, !textView.isHidden,
              textView.bounds.width > 0, textView.bounds.height > 0 else { return }
        pendingReadingByte = nil
        let source = textView.text ?? ""
        var index = source.utf8.index(source.utf8.startIndex, offsetBy: min(byte, source.utf8.count))
        while String.Index(index, within: source) == nil, index > source.utf8.startIndex {
            source.utf8.formIndex(before: &index)
        }
        let location = source[..<String.Index(index, within: source)!].utf16.count
        guard let position = textView.position(from: textView.beginningOfDocument, offset: location) else {
            isRestoringReadingPosition = false
            return
        }
        // An old offscreen caret must not pull the viewport back when typing
        // resumes. Updating the selection leaves text and undo history intact.
        textView.selectedRange = NSRange(location: location, length: 0)
        if resumesKeyboard { textView.becomeFirstResponder() }
        let caret = textView.caretRect(for: position)
        let minimum = -textView.adjustedContentInset.top
        let maximum = max(minimum, textView.contentSize.height - textView.bounds.height
                          + textView.adjustedContentInset.bottom)
        let y = byte == 0 ? minimum : caret.minY - textView.adjustedContentInset.top
        textView.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, y))), animated: false)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.pendingReadingByte == nil else { return }
            self?.isRestoringReadingPosition = false
        }
    }

    func selectHeading(startByte: Int) {
        pendingReadingByte = nil
        isRestoringReadingPosition = false
        synchronizeSource?()
        guard let textView else { return }
        let source = textView.text ?? ""
        let prefix = String(decoding: source.utf8.prefix(max(0, startByte)), as: UTF8.self)
        let location = min(prefix.utf16.count, source.utf16.count)
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: location, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        onReadingPositionChange?(startByte)
    }

    func selectSearchMatch(_ query: String) {
        pendingSearchQuery = query
        applyPendingSearchSelection()
    }

    func applyPendingSearchSelection() {
        guard let query = pendingSearchQuery, let textView,
              !textView.isHidden, textView.bounds.width > 0 else { return }
        let source = textView.text ?? ""
        guard let match = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            pendingSearchQuery = nil
            return
        }
        pendingSearchQuery = nil
        pendingReadingByte = nil
        isRestoringReadingPosition = false
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(match, in: source)
        textView.layoutIfNeeded()
        textView.scrollRangeToVisible(textView.selectedRange)
        captureReadingPosition()
    }

    func perform(_ command: OrgInputCommand) {
        synchronizeSource?()
        guard let textView else { return }
        textView.unmarkText()
        if let edit = OrgInputCommands.edit(command, source: textView.text ?? "", selection: textView.selectedRange) {
            performEdit?(edit, command.title)
        }
        refreshHistory()
    }

    func presentDate() {
        textView?.unmarkText()
        finishTyping?()
        dateSelection = textView?.selectedRange
        isDatePresented = true
    }

    func insertDate(_ date: Date) {
        guard let textView else { return }
        let value = date.orgTimestamp(includesTime: false)
        let range = dateSelection ?? textView.selectedRange
        performEdit?(OrgTextEdit(range: range, replacement: value,
                                selection: NSRange(location: range.location + value.utf16.count, length: 0)), String(localized: "Insert date"))
    }
}

/// An owned manager is also available while this editor is not first responder.
final class OrgEditorTextView: UITextView {
    let documentUndoManager = OrgDocumentUndoManager()
    override var undoManager: UndoManager? { documentUndoManager }

    static func make() -> OrgEditorTextView {
        // A nil container lets UIKit create TextKit 2 while the designated
        // initializer preserves our document-level undo manager subclass.
        let view = OrgEditorTextView(frame: .zero, textContainer: nil)
        view.textContainer.size = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer.widthTracksTextView = true
        view.documentUndoManager.groupsByEvent = false
        view.documentUndoManager.levelsOfUndo = 100
        return view
    }
}

final class OrgDocumentUndoManager: UndoManager {
    var finishTyping: (() -> Void)?
    override func undo() { finishTyping?(); super.undo() }
    override func redo() { finishTyping?(); super.redo() }
}
