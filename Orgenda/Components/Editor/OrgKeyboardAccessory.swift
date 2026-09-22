import UIKit

@MainActor
enum OrgKeyboardAccessory {
    static let height: CGFloat = 68

    static func make(for session: OrgEditorSession) -> UIView {
        func button(_ title: String, _ symbol: String, _ id: String, _ action: @escaping () -> Void) -> UIButton {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: symbol)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20)
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
            button.accessibilityLabel = title
            button.accessibilityIdentifier = "org.editor.\(id)"
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return button
        }
        let indent = button(String(localized: "Indentation"), "increase.indent", "indent") {}
        indent.menu = UIMenu(children: [
            UIAction(title: String(localized: "Indent"), image: UIImage(systemName: "increase.indent")) { [weak session] _ in session?.perform(.indent) },
            UIAction(title: String(localized: "Outdent"), image: UIImage(systemName: "decrease.indent")) { [weak session] _ in session?.perform(.outdent) }
        ])
        indent.showsMenuAsPrimaryAction = true
        let undo = button(String(localized: "Undo"), "arrow.uturn.backward", "undo") { [weak session] in session?.undo() }
        let redo = button(String(localized: "Redo"), "arrow.uturn.forward", "redo") { [weak session] in session?.redo() }
        undo.isEnabled = session.canUndo
        redo.isEnabled = session.canRedo
        session.updateAccessory = { [weak undo, weak redo] canUndo, canRedo in
            undo?.isEnabled = canUndo
            redo?.isEnabled = canRedo
        }
        let actions = UIStackView(arrangedSubviews: [
            button(String(localized: "Insert heading"), "textformat", "heading") { [weak session] in session?.perform(.heading) },
            button(String(localized: "Insert checkbox"), "checklist", "checkbox") { [weak session] in session?.perform(.checkbox) },
            indent,
            button(String(localized: "Insert date"), "calendar.badge.plus", "date") { [weak session] in session?.presentDate() },
            undo,
            redo,
            button(String(localized: "Dismiss keyboard"), "keyboard.chevron.compact.down", "dismissKeyboard") { [weak session] in
                session?.suspendEditing()
            }
        ])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.alignment = .center
        actions.translatesAutoresizingMaskIntoConstraints = false
        // A single native glass surface keeps every action visible on a phone;
        // UIToolbar moves the final actions into overflow at this width.
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glass = UIVisualEffectView(effect: effect)
        glass.layer.cornerRadius = 24
        glass.clipsToBounds = true
        glass.contentView.addSubview(actions)
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -8),
            actions.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            actions.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor)
        ])
        return OrgKeyboardAccessoryContainer(toolbar: glass)
    }
}

/// The editor scrolls behind the glass. Only the keyboard itself reduces the
/// viewport; a scroll inset keeps the caret and final line above the controls.
final class OrgEditorContainer: UIView {
    let textView: UITextView
    private let toolbar: UIView?

    init(textView: UITextView, session: OrgEditorSession?) {
        self.textView = textView
        toolbar = session.map { OrgKeyboardAccessory.make(for: $0) }
        super.init(frame: .zero)
        backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        if let toolbar {
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            toolbar.isHidden = true
            addSubview(toolbar)
            keyboardLayoutGuide.usesBottomSafeArea = false
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
                toolbar.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                toolbar.heightAnchor.constraint(equalToConstant: OrgKeyboardAccessory.height)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setKeyboardFocused(_ focused: Bool) {
        guard let toolbar, toolbar.isHidden == focused else { return }
        toolbar.isHidden = !focused
        let inset = focused ? OrgKeyboardAccessory.height : 0
        textView.contentInset.bottom = inset
        textView.verticalScrollIndicatorInsets.bottom = inset
    }
}

/// Keep the native glass and actions above the keyboard with clear margins.
private final class OrgKeyboardAccessoryContainer: UIView {
    private let toolbar: UIView

    init(toolbar: UIView) {
        self.toolbar = toolbar
        super.init(frame: CGRect(x: 0, y: 0, width: toolbar.frame.width, height: OrgKeyboardAccessory.height))
        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = .flexibleWidth
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        let preferredWidth = toolbar.widthAnchor.constraint(equalToConstant: 420)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            toolbar.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            preferredWidth,
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            toolbar.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: OrgKeyboardAccessory.height)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), hit !== self else { return nil }
        // Empty margins and space between button groups belong to the editor.
        var candidate: UIView? = hit
        while let view = candidate, view !== self {
            if view is UIControl { return hit }
            candidate = view.superview
        }
        return nil
    }
}
