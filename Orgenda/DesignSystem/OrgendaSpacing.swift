import SwiftUI

/// Shared spacing for custom content, from tight text groups to page margins.
/// Native forms, sidebars and control hit areas keep their system geometry;
/// source indentation remains tied to the document.
enum OrgendaSpacing {
    static let textGap: CGFloat = 2
    static let compactInset: CGFloat = 4
    static let inlineGap: CGFloat = 6
    static let rowInset: CGFloat = 8
    static let contentInset: CGFloat = 12
    static let pageMargin: CGFloat = 16
    static let scrollBottomInset: CGFloat = 24

    static let documentInsets = EdgeInsets(
        top: rowInset, leading: pageMargin,
        bottom: scrollBottomInset, trailing: pageMargin
    )

    static let badgeInsets = EdgeInsets(
        top: textGap, leading: inlineGap,
        bottom: textGap, trailing: inlineGap
    )

    // Match TextEditor's native text-container inset and line-fragment padding.
    static let textEditorPlaceholderInsets = EdgeInsets(
        top: rowInset, leading: 5, bottom: 0, trailing: 0
    )
}
