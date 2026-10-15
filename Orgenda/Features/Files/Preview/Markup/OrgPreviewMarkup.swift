import SwiftUI
import OrgTreeSitter

/// Presentation derived from the existing syntax tree. Source slices stay in
/// UTF-8 coordinates; removing visible delimiters never changes edit offsets.
enum OrgPreviewMarkup {
    static func attributed(
        _ node: ParsedOrgNode,
        trimSpaces: Bool = false,
        replacement: ((ParsedOrgNode) -> AttributedString?)? = nil
    ) -> AttributedString {
        trimmed(render(node, replacement: replacement), spaces: trimSpaces)
    }

    static func contents(of node: ParsedOrgNode) -> [ParsedOrgNode] {
        node.children.filter {
            !$0.type.hasSuffix("_begin") && !$0.type.hasSuffix("_end")
        }
    }

    static func fragments(
        _ node: ParsedOrgNode,
        trimSpaces: Bool = false,
        replacement: ((ParsedOrgNode) -> AttributedString?)? = nil
    ) -> [OrgPreviewInlineFragment] {
        trimmed(renderFragments(node, replacement: replacement), spaces: trimSpaces)
    }

    /// Drawer history is display-only, so its timestamps can use the same
    /// readable current-year elision as the rest of Preview without changing
    /// the underlying Org source.
    static func readableDrawerFragments(
        _ node: ParsedOrgNode,
        trimSpaces: Bool = false,
        locale: Locale = .autoupdatingCurrent,
        now: Date = .now
    ) -> [OrgPreviewInlineFragment] {
        fragments(node, trimSpaces: trimSpaces) { timestamp in
            guard let draft = OrgPlanningEntryDraft(timestampSource: timestamp.text) else {
                return nil
            }
            let presentation = OrgPreviewDateText(draft: draft, locale: locale, now: now)
            var value = AttributedString(([presentation.date] + presentation.details).joined(separator: " · "))
            value.foregroundColor = OrgendaTheme.accentText
            return value
        }
    }

    static func literalText(_ node: ParsedOrgNode) -> String {
        if node.type == "fixed_width" {
            return node.children.map { line in
                line.children.first { $0.type == "fixed_width_content" }?.text ?? ""
            }.joined(separator: "\n")
        }
        return contents(of: node).map(\.text).joined().trimmingCharacters(in: .newlines)
    }

    static func externalURL(_ target: String) -> URL? {
        guard let url = URL(string: target),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme) else { return nil }
        return url
    }

    static func listContent(_ node: ParsedOrgNode) -> AttributedString {
        var result = AttributedString()
        if let tag = node.children.first(where: { $0.type == "description_tag" }) {
            result.append(attributed(tag))
            result.append(AttributedString("  "))
        }
        if let content = node.children.first(where: { $0.type == "list_item_content" }) {
            result.append(attributed(content, trimSpaces: true))
        }
        return result
    }

    static func listMarker(_ node: ParsedOrgNode) -> String {
        if let counter = node.children.first(where: { $0.type == "list_counter" }) {
            return "\(counter.text.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(2).dropLast())."
        }
        let marker = node.children.first { $0.type.hasSuffix("list_marker") }?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "•"
        return ["-", "+", "*"].contains(marker) ? "•" : marker
    }

    private static func render(
        _ node: ParsedOrgNode,
        replacement: ((ParsedOrgNode) -> AttributedString?)?
    ) -> AttributedString {
        if let replaced = replacement?(node) { return replaced }
        switch node.type {
        case "bold", "italic", "underline", "strikethrough", "code", "verbatim":
            var value = AttributedString(String(node.text.dropFirst().dropLast()))
            switch node.type {
            case "bold": value.inlinePresentationIntent = .stronglyEmphasized
            case "italic": value.inlinePresentationIntent = .emphasized
            case "underline": value.underlineStyle = .single
            case "strikethrough": value.strikethroughStyle = .single
            default:
                value.font = .subheadline.monospaced()
                value.foregroundColor = Color(uiColor: .systemPink)
                value.backgroundColor = Color(uiColor: .tertiarySystemFill)
            }
            return value
        case "link", "angle_link", "plain_link":
            let target = node.type == "angle_link"
                ? String(node.text.dropFirst().dropLast())
                : node.children.first { $0.type == "link_target" }?.text ?? node.text
            let label = node.children.first { $0.type == "link_description" }?.text ?? target
            var value = AttributedString(label)
            if let url = externalURL(target) {
                value.link = url
                value.foregroundColor = OrgendaTheme.accentText
                value.underlineStyle = .single
            }
            return value
        case "statistics_cookie":
            var value = AttributedString(String(node.text.dropFirst().dropLast()))
            value.inlinePresentationIntent = .stronglyEmphasized
            value.foregroundColor = Color(uiColor: .systemBlue)
            value.backgroundColor = Color(uiColor: .systemBlue).opacity(0.12)
            return value
        case "target", "radio_target":
            let count = node.type == "target" ? 2 : 3
            var value = AttributedString("⌖ " + node.text.dropFirst(count).dropLast(count))
            value.foregroundColor = .secondary
            return value
        case "macro", "export_snippet":
            var value = AttributedString(node.text)
            value.font = .body.monospaced()
            value.foregroundColor = Color(uiColor: .systemBrown)
            value.backgroundColor = Color(uiColor: .tertiarySystemFill)
            return value
        case "footnote_reference", "inline_footnote", "footnote_definition_marker":
            let raw = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = raw.hasPrefix("[fn:") ? String(raw.dropFirst(4).dropLast()) : raw
            var value = AttributedString("[" + label.trimmingCharacters(in: CharacterSet(charactersIn: ":")) + "]"
                + (node.type == "footnote_definition_marker" ? " " : ""))
            value.foregroundColor = Color(uiColor: .systemPurple)
            return value
        case "description_tag":
            var value = AttributedString(node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .dropLast(2).trimmingCharacters(in: .whitespaces))
            value.inlinePresentationIntent = .stronglyEmphasized
            return value
        case "timestamp", "timestamp_range", "active_timestamp", "inactive_timestamp":
            var value = AttributedString(node.text)
            value.foregroundColor = OrgendaTheme.accentText
            return value
        default:
            guard !node.children.isEmpty else { return AttributedString(node.text) }
            let bytes = Array(node.text.utf8)
            var result = AttributedString()
            var cursor = 0
            for child in node.children {
                let start = child.startByte - node.startByte
                let end = child.endByte - node.startByte
                result.append(AttributedString(String(decoding: bytes[cursor..<start], as: UTF8.self)))
                result.append(render(child, replacement: replacement))
                cursor = end
            }
            result.append(AttributedString(String(decoding: bytes[cursor...], as: UTF8.self)))
            return result
        }
    }

    private static func renderFragments(
        _ node: ParsedOrgNode,
        replacement: ((ParsedOrgNode) -> AttributedString?)?
    ) -> [OrgPreviewInlineFragment] {
        if let replaced = replacement?(node) { return [.text(replaced)] }

        switch node.type {
        case "latex_fragment", "latex_block":
            return [.math(OrgMathExpression(node))]
        case "bold", "italic", "underline", "strikethrough":
            let styled = render(node, replacement: nil)
            let source = String(node.text.dropFirst().dropLast())
            guard source.contains("\\") || source.contains("$") else { return [.text(styled)] }
            // Emphasis is a terminal grammar token. Parse its body with the
            // same Org grammar so formulas survive the surrounding style.
            let body = ParsedOrgNode(OrgParser().parse(source).rootNode, path: node.id)
            let fragments = renderFragments(body, replacement: nil)
            guard fragments.contains(where: { if case .math = $0 { return true }; return false }) else {
                return [.text(styled)]
            }
            let attributes = styled.runs.first?.attributes ?? AttributeContainer()
            return fragments.map { fragment in
                guard case .text(var value) = fragment else { return fragment }
                value.mergeAttributes(attributes)
                return .text(value)
            }
        case "code", "verbatim", "statistics_cookie", "target", "radio_target", "macro",
             "export_snippet", "footnote_reference", "inline_footnote", "footnote_definition_marker",
             "description_tag", "timestamp", "timestamp_range", "active_timestamp", "inactive_timestamp":
            return [.text(render(node, replacement: nil))]
        case "link", "angle_link", "plain_link":
            if let image = OrgPreviewImageReference.from(node) { return [.image(image)] }
            return [.text(render(node, replacement: nil))]
        default:
            guard !node.children.isEmpty else { return [.text(AttributedString(node.text))] }
            let bytes = Array(node.text.utf8)
            var result: [OrgPreviewInlineFragment] = []
            var cursor = 0
            for child in node.children {
                let start = child.startByte - node.startByte
                let end = child.endByte - node.startByte
                if cursor < start {
                    result.append(.text(AttributedString(String(decoding: bytes[cursor..<start], as: UTF8.self))))
                }
                result.append(contentsOf: renderFragments(child, replacement: replacement))
                cursor = end
            }
            if cursor < bytes.count {
                result.append(.text(AttributedString(String(decoding: bytes[cursor...], as: UTF8.self))))
            }
            return result
        }
    }

    private static func trimmed(
        _ value: AttributedString, spaces: Bool, leading: Bool = true, trailing: Bool = true
    ) -> AttributedString {
        let characters = value.characters
        func keep(_ character: Character) -> Bool { !(spaces ? character.isWhitespace : character.isNewline) }
        let start = leading ? characters.firstIndex(where: keep) ?? value.endIndex : value.startIndex
        let end = trailing ? characters.lastIndex(where: keep).map { characters.index(after: $0) } ?? start : value.endIndex
        return AttributedString(value[start..<end])
    }

    static func trimmed(
        _ fragments: [OrgPreviewInlineFragment],
        spaces: Bool
    ) -> [OrgPreviewInlineFragment] {
        var result = fragments[...]
        while let first = result.first, case .text(let value) = first {
            let trimmed = trimmed(value, spaces: spaces, trailing: false)
            if !trimmed.characters.isEmpty {
                result[result.startIndex] = .text(trimmed)
                break
            }
            result.removeFirst()
        }
        while let last = result.last, case .text(let value) = last {
            let trimmed = trimmed(value, spaces: spaces, leading: false)
            if !trimmed.characters.isEmpty {
                result[result.index(before: result.endIndex)] = .text(trimmed)
                break
            }
            result.removeLast()
        }
        return Array(result)
    }
}
