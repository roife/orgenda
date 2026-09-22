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

    static func clamped(_ range: NSRange, to textLength: Int) -> NSRange? {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              range.location < textLength else {
            return nil
        }

        return NSRange(
            location: range.location,
            length: min(range.length, textLength - range.location)
        )
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
        colorSchemeContrast: ColorSchemeContrast
    ) {
        switch kind {
        case .heading:
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .todo:
            textStorage.addAttribute(
                .foregroundColor,
                value: workflowColor(for: textStorage.attributedSubstring(from: range).string),
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
                    .foregroundColor: UIColor.systemPurple,
                    .backgroundColor: UIColor.systemPurple.withAlphaComponent(
                        colorSchemeContrast == .increased ? 0.22 : 0.12
                    ),
                ],
                range: range
            )

        case .planning:
            textStorage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .timestamp:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.syntaxTeal, range: range)

        case .property:
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: range)

        case .drawer:
            textStorage.addAttribute(.backgroundColor, value: UIColor.systemIndigo.withAlphaComponent(
                colorSchemeContrast == .increased ? 0.16 : 0.06
            ), range: range)

        case .drawerDelimiter:
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .clock:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.syntaxTeal, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .progress:
            textStorage.addAttributes([
                .foregroundColor: UIColor.systemBlue,
                .backgroundColor: UIColor.systemBlue.withAlphaComponent(
                    colorSchemeContrast == .increased ? 0.22 : 0.12
                ),
            ], range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .target:
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .macro:
            textStorage.addAttributes([
                .foregroundColor: UIColor.systemBrown,
                .backgroundColor: UIColor.tertiarySystemFill,
            ], range: range)

        case .keyword:
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .comment:
            textStorage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
            addFontTraits(.traitItalic, to: textStorage, range: range)

        case .link:
            textStorage.addAttributes(
                [
                    .foregroundColor: UIColor.link,
                    .underlineColor: UIColor.link,
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
                    .foregroundColor: UIColor.systemPink,
                    .backgroundColor: UIColor.tertiarySystemFill,
                ],
                range: range
            )

        case .verbatim:
            textStorage.addAttributes(
                [
                    .foregroundColor: UIColor.systemBrown,
                    .backgroundColor: UIColor.tertiarySystemFill,
                ],
                range: range
            )

        case .sourceBlock:
            textStorage.addAttributes(
                [
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.secondarySystemFill,
                ],
                range: range
            )

        case .quoteBlock:
            textStorage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
            addFontTraits(.traitItalic, to: textStorage, range: range)

        case .listMarker:
            textStorage.addAttribute(.foregroundColor, value: OrgendaTheme.syntaxTeal, range: range)
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .checkbox:
            textStorage.addAttribute(
                .foregroundColor,
                value: checkboxColor(for: textStorage.attributedSubstring(from: range).string),
                range: range
            )
            addFontTraits(.traitBold, to: textStorage, range: range)

        case .table:
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: range)

        case .footnote:
            textStorage.addAttributes(
                [
                    .foregroundColor: UIColor.systemPurple,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )
        }
    }

    static func applyWorkflowHeadingColors(_ highlights: [OrgHighlightSpan], to storage: NSTextStorage) {
        let source = storage.string as NSString
        for span in highlights where span.kind == .heading {
            guard let range = clamped(span.range, to: storage.length) else { continue }
            let line = source.substring(with: source.lineRange(for: range))
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count > 1, tokens[0].allSatisfy({ $0 == "*" }),
                  let state = OrgWorkflowState(rawValue: String(tokens[1])) else { continue }
            storage.addAttribute(.foregroundColor, value: UIColor(OrgendaTheme.workflowColor(state)), range: range)
        }
    }

    private static func workflowColor(for token: String) -> UIColor {
        let keyword = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let state = OrgWorkflowState(rawValue: keyword) else { return .secondaryLabel }
        return UIColor(OrgendaTheme.workflowColor(state))
    }

    private static func priorityColor(for token: String) -> UIColor {
        if token.contains("#A") { return .systemRed }
        if token.contains("#B") { return .systemOrange }
        if token.contains("#C") { return .systemBlue }
        return .secondaryLabel
    }

    private static func checkboxColor(for token: String) -> UIColor {
        if token.localizedCaseInsensitiveContains("x") { return .systemGreen }
        if token.contains("-") { return .systemOrange }
        return .secondaryLabel
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
