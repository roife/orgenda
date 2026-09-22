import SwiftUI

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

    static func blockText(_ node: ParsedOrgNode) -> AttributedString {
        var result = AttributedString()
        for child in contents(of: node) { result.append(render(child, replacement: nil)) }
        return trimmed(result, spaces: false)
    }

    static func fragments(
        _ node: ParsedOrgNode,
        trimSpaces: Bool = false,
        replacement: ((ParsedOrgNode) -> AttributedString?)? = nil
    ) -> [OrgPreviewInlineFragment] {
        trimmed(renderFragments(node, replacement: replacement), spaces: trimSpaces)
    }

    static func mathLiteralRanges(in node: ParsedOrgNode) -> [Range<Int>] {
        if ["code", "verbatim", "link", "angle_link", "plain_link", "macro", "export_snippet",
            "target", "radio_target", "footnote_reference", "inline_footnote"].contains(node.type) {
            return [node.startByte..<node.endByte]
        }
        return node.children.flatMap { mathLiteralRanges(in: $0) }
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
        case "bold", "italic", "underline", "strikethrough":
            let source = String(node.text.dropFirst().dropLast())
            return styledFragments(in: source) { value in
                switch node.type {
                case "bold": value.inlinePresentationIntent = .stronglyEmphasized
                case "italic": value.inlinePresentationIntent = .emphasized
                case "underline": value.underlineStyle = .single
                case "strikethrough": value.strikethroughStyle = .single
                default: break
                }
            }
        case "code", "verbatim", "statistics_cookie", "target", "radio_target", "macro",
             "export_snippet", "footnote_reference", "inline_footnote", "footnote_definition_marker",
             "description_tag", "timestamp", "timestamp_range", "active_timestamp", "inactive_timestamp":
            return [.text(render(node, replacement: nil))]
        case "link", "angle_link", "plain_link":
            if let image = OrgPreviewImageReference.from(node) { return [.image(image)] }
            let target = node.type == "angle_link"
                ? String(node.text.dropFirst().dropLast())
                : node.children.first { $0.type == "link_target" }?.text ?? node.text
            let label = node.children.first { $0.type == "link_description" }?.text ?? target
            return styledFragments(in: label) { value in
                if let url = externalURL(target) {
                    value.link = url
                    value.foregroundColor = OrgendaTheme.accentText
                    value.underlineStyle = .single
                }
            }
        default:
            guard !node.children.isEmpty else { return fragments(in: node.text) }

            let bytes = Array(node.text.utf8)
            let math = OrgMathParser.matches(
                in: node.text,
                literalRanges: mathLiteralRanges(in: node).map {
                    ($0.lowerBound - node.startByte)..<($0.upperBound - node.startByte)
                }
            )
            var result: [OrgPreviewInlineFragment] = []
            var cursor = 0
            var childIndex = 0
            var mathIndex = 0

            while cursor < bytes.count {
                while childIndex < node.children.count,
                      node.children[childIndex].endByte - node.startByte <= cursor {
                    childIndex += 1
                }
                while mathIndex < math.count, math[mathIndex].endByte <= cursor {
                    mathIndex += 1
                }

                let child = childIndex < node.children.count ? node.children[childIndex] : nil
                let childStart = child.map { $0.startByte - node.startByte }
                let childEnd = child.map { $0.endByte - node.startByte }
                let match = mathIndex < math.count ? math[mathIndex] : nil

                if let match, match.startByte == cursor {
                    result.append(.math(match.expression))
                    cursor = match.endByte
                    mathIndex += 1
                    continue
                }

                if let child, let childStart, let childEnd, childStart == cursor {
                    if let match, match.startByte > cursor, match.startByte < childEnd {
                        result.append(.text(AttributedString(String(decoding: bytes[cursor..<match.startByte], as: UTF8.self))))
                        cursor = match.startByte
                        continue
                    }
                    result.append(contentsOf: renderFragments(child, replacement: replacement))
                    cursor = childEnd
                    childIndex += 1
                    continue
                }

                if let childStart, let childEnd,
                   childStart < cursor, cursor < childEnd {
                    // A formula can finish inside a larger Org text node. Stop
                    // at the next formula instead of consuming the whole tail.
                    let end = min(childEnd, match?.startByte ?? bytes.count)
                    result.append(.text(AttributedString(String(decoding: bytes[cursor..<end], as: UTF8.self))))
                    cursor = end
                    if cursor == childEnd { childIndex += 1 }
                    continue
                }

                let nextChild = childStart ?? bytes.count
                let nextMath = match?.startByte ?? bytes.count
                let end = min(nextChild, nextMath)
                result.append(.text(AttributedString(String(decoding: bytes[cursor..<end], as: UTF8.self))))
                cursor = end
            }
            return result
        }
    }

    private static func styledFragments(
        in source: String,
        style: (inout AttributedString) -> Void
    ) -> [OrgPreviewInlineFragment] {
        fragments(in: source).map { fragment in
            guard case .text(var value) = fragment else { return fragment }
            style(&value)
            return .text(value)
        }
    }

    private static func fragments(in source: String) -> [OrgPreviewInlineFragment] {
        let bytes = Array(source.utf8)
        let matches = OrgMathParser.matches(in: source)
        guard !matches.isEmpty else { return [.text(AttributedString(source))] }

        var result: [OrgPreviewInlineFragment] = []
        var cursor = 0
        for match in matches {
            if cursor < match.startByte {
                result.append(.text(AttributedString(String(decoding: bytes[cursor..<match.startByte], as: UTF8.self))))
            }
            result.append(.math(match.expression))
            cursor = match.endByte
        }
        if cursor < bytes.count {
            result.append(.text(AttributedString(String(decoding: bytes[cursor...], as: UTF8.self))))
        }
        return result
    }

    private static func trimmed(_ value: AttributedString, spaces: Bool) -> AttributedString {
        var result = value
        func trim(_ character: Character) -> Bool { spaces ? character.isWhitespace : character.isNewline }
        while let first = result.characters.first, trim(first) {
            result.removeSubrange(result.startIndex..<result.characters.index(after: result.startIndex))
        }
        while let last = result.characters.last, trim(last) {
            result.removeSubrange(result.characters.index(before: result.endIndex)..<result.endIndex)
        }
        return result
    }

    static func trimmed(
        _ fragments: [OrgPreviewInlineFragment],
        spaces: Bool
    ) -> [OrgPreviewInlineFragment] {
        var result = fragments
        func shouldTrim(_ character: Character) -> Bool {
            spaces ? character.isWhitespace : character.isNewline
        }

        while let first = result.first {
            guard case .text(var value) = first else { break }
            while let character = value.characters.first, shouldTrim(character) {
                value.removeSubrange(value.startIndex..<value.characters.index(after: value.startIndex))
            }
            if value.characters.isEmpty {
                result.removeFirst()
            } else {
                result[0] = .text(value)
                break
            }
        }

        while let last = result.last {
            guard case .text(var value) = last else { break }
            while let character = value.characters.last, shouldTrim(character) {
                value.removeSubrange(value.characters.index(before: value.endIndex)..<value.endIndex)
            }
            if value.characters.isEmpty {
                result.removeLast()
            } else {
                result[result.count - 1] = .text(value)
                break
            }
        }
        return result
    }

}
