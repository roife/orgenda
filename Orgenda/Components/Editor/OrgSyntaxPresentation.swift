import SwiftUI
import UIKit

@MainActor
enum OrgSyntaxPresentation {
    static func bodyFont(compatibleWith traits: UITraitCollection) -> UIFont {
        let bodyDescriptor = UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: .callout,
            compatibleWith: traits
        )
        let monospacedDescriptor = bodyDescriptor.withDesign(.monospaced) ?? bodyDescriptor
        return UIFont(descriptor: monospacedDescriptor, size: 0)
    }

    static func clampedSelection(_ range: NSRange, to textLength: Int) -> NSRange {
        guard range.location != NSNotFound else {
            return NSRange(location: 0, length: 0)
        }

        let location = min(max(0, range.location), textLength)
        return NSRange(location: location, length: min(range.length, textLength - location))
    }

    static func apply(
        _ kind: OrgHighlightKind,
        to textStorage: NSTextStorage,
        range: NSRange,
        colorSchemeContrast: ColorSchemeContrast,
        workflow: WorkspaceConfiguration.Workflow
    ) {
        switch kind {
        case .heading:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.Syntax.heading, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .todo:
            textStorage.addAttribute(
                .foregroundColor,
                value: workflow.state(textStorage.attributedSubstring(from: range).string
                    .trimmingCharacters(in: .whitespacesAndNewlines)).map { UIColor(OrgendaTheme.workflowColor($0)) }
                    ?? OrgendaTheme.secondaryInkColor,
                range: range
            )
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .priority:
            textStorage.addAttribute(
                .foregroundColor,
                value: priorityColor(for: textStorage.attributedSubstring(from: range).string),
                range: range
            )
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .tag:
            textStorage.addAttributes(
                [
                    .foregroundColor: OrgendaTheme.Syntax.tag,
                    .backgroundColor: OrgendaTheme.Syntax.tagBackground(contrast: colorSchemeContrast),
                ],
                range: range
            )

        case .planning:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.secondaryInkColor, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .timestamp:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.Syntax.timestamp, range: range)

        case .property, .table:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.Syntax.property, range: range)

        case .drawer:
            textStorage.addAttribute(.backgroundColor, value: OrgendaTheme.Syntax.drawerBackground(contrast: colorSchemeContrast), range: range)

        case .drawerDelimiter:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.Syntax.property, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .clock, .listMarker:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.Syntax.timestamp, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .progress:
            textStorage.addAttributes([
                .foregroundColor: OrgendaTheme.Syntax.progress,
                .backgroundColor: OrgendaTheme.Syntax.progressBackground(contrast: colorSchemeContrast),
            ], range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .target, .keyword:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.Syntax.keyword, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .math, .macro, .verbatim:
            textStorage.addAttributes([
                .foregroundColor: OrgendaTheme.Syntax.literal,
                .backgroundColor: OrgendaTheme.tertiaryFillColor,
            ], range: range)

        case .comment, .quoteBlock:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.secondaryInkColor, range: range)
            addFontTraits(.traitItalic, to: textStorage, range: range)

        case .link:
            textStorage.addAttributes(
                [
                    .foregroundColor: OrgendaTheme.Syntax.link,
                    .underlineColor: OrgendaTheme.Syntax.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )

        case .bold:
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .italic:
            addFontTraits(.traitItalic, to: textStorage, range: range)

        case .underline:
            textStorage.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )

        case .strikethrough:
            textStorage.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )

        case .code:
            textStorage.addAttributes(
                [
                    .foregroundColor: OrgendaTheme.Syntax.code,
                    .backgroundColor: OrgendaTheme.tertiaryFillColor,
                ],
                range: range
            )

        case .sourceBlock:
            textStorage.addAttributes(
                [
                    .foregroundColor: OrgendaTheme.inkColor,
                    .backgroundColor: OrgendaTheme.secondaryFillColor,
                ],
                range: range
            )

        case .checkbox:
            textStorage.addAttribute(
                .foregroundColor,
                value: checkboxColor(for: textStorage.attributedSubstring(from: range).string),
                range: range
            )
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .footnote:
            textStorage.addAttributes(
                [
                    .foregroundColor: OrgendaTheme.Syntax.footnote,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )
        }
    }

    static func applyWorkflowHeadingColors(_ highlights: [OrgHighlightSpan], to storage: NSTextStorage,
                                          workflow: WorkspaceConfiguration.Workflow) {
        let source = storage.string as NSString
        for span in highlights where span.kind == .heading {
            let line = source.substring(with: source.lineRange(for: span.range))
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count > 1, tokens[0].allSatisfy({ $0 == "*" }),
                  let state = workflow.state(String(tokens[1])) else { continue }
            storage.addAttribute(.foregroundColor, value: UIColor(OrgendaTheme.workflowColor(state)), range: span.range)
        }
    }

    private static func priorityColor(for token: String) -> UIColor {
        if token.contains("#A") { return UIColor(OrgendaTheme.priorityColor(.high)) }
        if token.contains("#B") { return UIColor(OrgendaTheme.priorityColor(.medium)) }
        if token.contains("#C") { return UIColor(OrgendaTheme.priorityColor(.low)) }
        return OrgendaTheme.secondaryInkColor
    }

    private static func checkboxColor(for token: String) -> UIColor {
        if token.localizedCaseInsensitiveContains("x") { return UIColor(OrgendaTheme.success) }
        if token.contains("-") { return UIColor(OrgendaTheme.warning) }
        return OrgendaTheme.secondaryInkColor
    }

    private static func addFontTraits(
        _ traits: UIFontDescriptor.SymbolicTraits,
        to textStorage: NSTextStorage,
        range: NSRange
    ) {
        var updates: [(NSRange, UIFont)] = []
        textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? UIFont else { return }
            let combinedTraits = font.fontDescriptor.symbolicTraits.union(traits)
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(combinedTraits) else {
                return
            }
            updates.append((subrange, UIFont(descriptor: descriptor, size: 0)))
        }
        for (subrange, font) in updates {
            textStorage.addAttribute(.font, value: font, range: subrange)
        }
    }
}
