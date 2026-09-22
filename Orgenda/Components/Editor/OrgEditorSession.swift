import Observation
import UIKit

/// The document owns this session; the text view survives Edit/Preview switches.
@MainActor
@Observable
final class OrgEditorSession {
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoName = String(localized: "Undo")
    private(set) var redoName = String(localized: "Redo")
    var isDatePresented = false
    var isKeyboardFocused = false
    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored var synchronizeSource: (() -> Void)?
    @ObservationIgnored var performEdit: ((OrgTextEdit, String) -> Void)?
    @ObservationIgnored var finishTyping: (() -> Void)?
    @ObservationIgnored var updateAccessory: ((Bool, Bool) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var savedOffset: CGPoint?
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
        undoName = manager?.undoMenuItemTitle ?? String(localized: "Undo")
        redoName = manager?.redoMenuItemTitle ?? String(localized: "Redo")
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
        savedOffset = textView.contentOffset
        resumesKeyboard = textView.isFirstResponder
        textView.unmarkText()
        finishTyping?()
        textView.resignFirstResponder()
    }

    func restorePosition() {
        guard let textView, let savedOffset else { return }
        if resumesKeyboard { textView.becomeFirstResponder() }
        textView.layoutIfNeeded()
        textView.setContentOffset(savedOffset, animated: false)
        self.savedOffset = nil
    }

    func selectHeading(startByte: Int) {
        synchronizeSource?()
        guard let textView else { return }
        let source = textView.text ?? ""
        let prefix = String(decoding: source.utf8.prefix(max(0, startByte)), as: UTF8.self)
        let location = min(prefix.utf16.count, source.utf16.count)
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: location, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        savedOffset = nil
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
        savedOffset = nil
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(match, in: source)
        textView.layoutIfNeeded()
        textView.scrollRangeToVisible(textView.selectedRange)
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd EEE"
        let value = "<\(formatter.string(from: date))>"
        let range = dateSelection ?? textView.selectedRange
        performEdit?(OrgTextEdit(range: range, replacement: value,
                                selection: NSRange(location: range.location + value.utf16.count, length: 0)), String(localized: "Insert date"))
    }
}

/// An owned manager is also available while this editor is not first responder.
final class OrgEditorTextView: UITextView {
    let documentUndoManager = OrgDocumentUndoManager()
    private var ownedContentStorage: NSTextContentStorage?
    override var undoManager: UndoManager? { documentUndoManager }

    static func make() -> OrgEditorTextView {
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.textContainer = container
        // UITextView's usingTextLayoutManager convenience initializer can return
        // a base UITextView. The designated initializer preserves this subclass.
        let view = OrgEditorTextView(frame: .zero, textContainer: container)
        view.documentUndoManager.groupsByEvent = false
        view.documentUndoManager.levelsOfUndo = 100
        view.ownedContentStorage = storage
        return view
    }
}

final class OrgDocumentUndoManager: UndoManager {
    var finishTyping: (() -> Void)?
    override func undo() { finishTyping?(); super.undo() }
    override func redo() { finishTyping?(); super.redo() }
}
