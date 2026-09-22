import SwiftUI
import Synchronization

/// A display-only projection. The draft retains the exact Org source for edits.
struct OrgPreviewDateText {
    /// Formatters are expensive to build and re-template; they are cached per
    /// (locale, template) since rendering touches one formatter per timestamp.
    private static let formatters = Mutex<[String: DateFormatter]>([:])

    private static func formatter(locale: Locale, template: String) -> DateFormatter {
        let key = "\(locale.identifier)\u{0}\(template)"
        return formatters.withLock { cache in
            if let cached = cache[key] { return cached }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate(template)
            cache[key] = formatter
            return formatter
        }
    }

    let draft: OrgPlanningEntryDraft
    var locale: Locale = .autoupdatingCurrent
    var now: Date = .now

    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private var traditional: Bool {
        locale.language.script?.identifier == "Hant" || ["TW", "HK", "MO"].contains(locale.region?.identifier ?? "")
    }

    func localized(_ english: String, _ simplified: String, _ traditional: String) -> String {
        chinese ? (self.traditional ? traditional : simplified) : english
    }

    var keyword: String? {
        switch draft.keyword {
        case .scheduled: localized("Scheduled", "计划", "計畫")
        case .deadline: localized("Deadline", "截止", "截止")
        case .closed: localized("Closed", "完成", "完成")
        case nil: nil
        }
    }

    var date: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return draft.timestamps.map { timestamp in
            let sameYear = calendar.component(.year, from: timestamp.date)
                == calendar.component(.year, from: now)
            let dateFormatter = Self.formatter(
                locale: locale, template: sameYear ? "MMM d EEE" : "y MMM d EEE")
            var result = dateFormatter.string(from: timestamp.date)
            if timestamp.includesTime {
                let timeFormatter = Self.formatter(locale: locale, template: "jmm")
                result += " " + timeFormatter.string(from: timestamp.date)
                if let range = OrgPlanningTimestampDraft.sameDayTimeRange(in: timestamp.trailingText) {
                    let parts = timestamp.trailingText[range].dropFirst().split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2, let end = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: timestamp.date) {
                        result += "–" + timeFormatter.string(from: end)
                    }
                }
            }
            return result
        }.joined(separator: " → ")
    }

    var details: [String] {
        draft.timestamps.flatMap { timestamp -> [String] in
            var result: [String] = []
            var remainder = timestamp.trailingText
            if let range = OrgPlanningTimestampDraft.sameDayTimeRange(in: remainder) {
                remainder.removeSubrange(range)
            }
            if let token = timestamp.recurrence, let repeater = OrgRepeater(token) {
                result.append(recurrence(repeater))
                if let range = remainder.range(of: token) { remainder.removeSubrange(range) }
            }
            // Keep warnings, delays and unfamiliar extensions visible instead of
            // silently dropping source semantics while formatting the date.
            let annotation = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !annotation.isEmpty { result.append(annotation) }
            return result
        }
    }

    var accessibilityValue: String { ([date] + details).joined(separator: ", ") }

    private func recurrence(_ repeater: OrgRepeater) -> String {
        let unit: String
        let english: String
        switch repeater.unit {
        case .hour: unit = localized("", "小时", "小時"); english = "hour"
        case .day: unit = "天"; english = "day"
        case .week: unit = localized("", "周", "週"); english = "week"
        case .month: unit = "月"; english = "month"
        case .year: unit = "年"; english = "year"
        }
        var value = chinese
            ? "每\(repeater.interval == 1 ? "" : "\(repeater.interval) ")\(unit)\(localized("", "重复", "重複"))"
            : "Every \(repeater.interval == 1 ? english : "\(repeater.interval) \(english)s")"
        switch repeater.mode {
        case .cumulative: break
        case .catchUp: value += localized(" · skip missed dates", " · 跳过已错过的日期", " · 跳過已錯過的日期")
        case .restart: value += localized(" after completion", "（从完成时算起）", "（從完成時算起）")
        }
        if let maximum = repeater.maximumInterval, let maximumUnit = repeater.maximumUnit {
            let names: [OrgRepeater.Unit: String] = chinese
                ? [.hour: localized("", "小时", "小時"), .day: "天", .week: localized("", "周", "週"), .month: "月", .year: "年"]
                : [.hour: "hour", .day: "day", .week: "week", .month: "month", .year: "year"]
            let name = names[maximumUnit] ?? maximumUnit.rawValue
            value += localized(" · maximum ", " · 最长间隔 ", " · 最長間隔 ")
                + "\(maximum) \(name)" + (!chinese && maximum != 1 ? "s" : "")
        }
        return value
    }
}

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
                guard start >= cursor, end >= start, end <= bytes.count else { continue }
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
                        result.append(.text(rawSlice(
                            child,
                            range: (node.startByte + cursor)..<(node.startByte + match.startByte)
                        )))
                        cursor = match.startByte
                        continue
                    }
                    result.append(contentsOf: renderFragments(child, replacement: replacement))
                    cursor = childEnd
                    childIndex += 1
                    continue
                }

                if let child, let childStart, let childEnd,
                   childStart < cursor, cursor < childEnd {
                    // A formula can finish inside a larger Org text node. Stop
                    // at the next formula instead of consuming the whole tail.
                    let end = min(childEnd, match?.startByte ?? bytes.count)
                    result.append(.text(rawSlice(
                        child,
                        range: (node.startByte + cursor)..<(node.startByte + end)
                    )))
                    cursor = end
                    if cursor == childEnd { childIndex += 1 }
                    continue
                }

                let nextChild = childStart ?? bytes.count
                let nextMath = match?.startByte ?? bytes.count
                let end = min(nextChild, nextMath, bytes.count)
                guard end > cursor else {
                    cursor += 1
                    continue
                }
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

    private static func rawSlice(_ node: ParsedOrgNode, range: Range<Int>) -> AttributedString {
        let lower = max(range.lowerBound, node.startByte) - node.startByte
        let upper = min(range.upperBound, node.endByte) - node.startByte
        guard lower < upper else { return AttributedString() }
        let bytes = Array(node.text.utf8)
        return AttributedString(String(decoding: bytes[lower..<upper], as: UTF8.self))
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

    private static func trimmed(
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

enum OrgPreviewInlineFragment {
    case text(AttributedString)
    case math(OrgMathExpression)
    case image(OrgPreviewImageReference)
}

struct OrgMathExpression: Hashable, Sendable {
    enum Mode: String, Hashable, Sendable {
        case inline
        case display
    }

    let latex: String
    let original: String
    let mode: Mode
}

enum OrgMathParser {
    struct Match: Hashable, Sendable {
        let startByte: Int
        let endByte: Int
        let expression: OrgMathExpression
    }

    private static let environments = [
        "equation", "equation*", "displaymath", "align", "align*", "aligned", "alignat", "alignat*", "alignedat",
        "gather", "gather*", "multline", "multline*", "eqnarray", "eqnarray*",
        "cases", "array", "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix",
    ]

    static func matches(
        in source: String,
        literalRanges: [Range<Int>] = [],
        canStartAt: ((Int) -> Bool)? = nil
    ) -> [Match] {
        var result: [Match] = []
        var protectedRanges = literalRanges
        var index = source.startIndex

        func append(_ match: Match) {
            result.append(match)
            // A formula has precedence over markup that starts inside it.
            // In particular '=' inside math can create a spurious Org verbatim
            // node extending into later prose and otherwise hide its formulas.
            protectedRanges.removeAll { match.startByte <= $0.lowerBound && $0.lowerBound < match.endByte }
        }

        while index < source.endIndex {
            if source[index] == "\\" || source[index] == "$" {
                let offset = source.utf8.distance(from: source.startIndex, to: index)
                if protectedRanges.contains(where: { $0.contains(offset) }) || canStartAt?(offset) == false {
                    index = source.index(after: index)
                    continue
                }
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix("$$"),
               let match = delimited(in: source, from: index, opening: "$$", closing: "$$", mode: .display) {
                append(match)
                index = stringIndex(atUTF8Offset: match.endByte, in: source)
                continue
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix(#"\["#),
               let match = delimited(in: source, from: index, opening: #"\["#, closing: #"\]"#, mode: .display) {
                append(match)
                index = stringIndex(atUTF8Offset: match.endByte, in: source)
                continue
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix(#"\("#),
               let match = delimited(in: source, from: index, opening: #"\("#, closing: #"\)"#, mode: .inline) {
                append(match)
                index = stringIndex(atUTF8Offset: match.endByte, in: source)
                continue
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix(#"\begin{"#),
               let match = environment(in: source, from: index) {
                append(match)
                index = stringIndex(atUTF8Offset: match.endByte, in: source)
                continue
            }
            if source[index] == "$", isUnescaped(index, in: source),
               validInlineDollarStart(at: index, in: source),
               let match = delimited(in: source, from: index, opening: "$", closing: "$", mode: .inline,
                                     validateEnd: { validInlineDollarEnd(at: $0, in: source) }) {
                append(match)
                index = stringIndex(atUTF8Offset: match.endByte, in: source)
                continue
            }
            index = source.index(after: index)
        }
        return result
    }

    static func soleDisplayExpression(in source: String) -> OrgMathExpression? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = matches(in: trimmed)
        guard matches.count == 1, let match = matches.first,
              match.startByte == 0, match.endByte == trimmed.utf8.count,
              match.expression.mode == .display else { return nil }
        return match.expression
    }

    static func startsDisplayExpression(in source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("$$") || trimmed.hasPrefix(#"\["#) { return true }
        guard trimmed.hasPrefix(#"\begin{"#),
              let brace = trimmed.dropFirst(#"\begin{"#.count).firstIndex(of: "}") else { return false }
        let nameStart = trimmed.index(trimmed.startIndex, offsetBy: #"\begin{"#.count)
        return environments.contains(String(trimmed[nameStart..<brace]))
    }

    private static func delimited(
        in source: String,
        from start: String.Index,
        opening: String,
        closing: String,
        mode: OrgMathExpression.Mode,
        validateEnd: ((String.Index) -> Bool)? = nil
    ) -> Match? {
        let contentStart = source.index(start, offsetBy: opening.count)
        var search = contentStart
        while search < source.endIndex,
              let range = source.range(of: closing, range: search..<source.endIndex) {
            // A dollar always closes the current pair before it can open the
            // next one; skipping it would swallow prose and a later formula.
            if closing == "$", isUnescaped(range.lowerBound, in: source),
               validateEnd?(range.lowerBound) == false { return nil }
            if isUnescaped(range.lowerBound, in: source), validateEnd?(range.lowerBound) != false {
                let latex = String(source[contentStart..<range.lowerBound])
                guard !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                // An unclosed inline formula must not consume a later formula
                // in a different paragraph. Keep the damaged source literal
                // and let the scanner recover at the next valid opener.
                if mode == .inline,
                   latex.range(of: #"\r?\n[ \t]*\r?\n"#, options: .regularExpression) != nil {
                    return nil
                }
                let end = range.upperBound
                return Match(
                    startByte: source.utf8.distance(from: source.startIndex, to: start),
                    endByte: source.utf8.distance(from: source.startIndex, to: end),
                    expression: OrgMathExpression(
                        latex: latex,
                        original: String(source[start..<end]),
                        mode: mode
                    )
                )
            }
            search = source.index(after: range.lowerBound)
        }
        return nil
    }

    private static func environment(in source: String, from start: String.Index) -> Match? {
        let nameStart = source.index(start, offsetBy: #"\begin{"#.count)
        guard let brace = source[nameStart...].firstIndex(of: "}") else { return nil }
        let name = String(source[nameStart..<brace])
        guard environments.contains(name) else { return nil }
        let opening = "\\begin{\(name)}"
        let closing = "\\end{\(name)}"
        var depth = 1
        var cursor = source.index(after: brace)
        while cursor < source.endIndex {
            if source[cursor] == "\\", isUnescaped(cursor, in: source) {
                if source[cursor...].hasPrefix(opening) {
                    depth += 1
                    cursor = source.index(cursor, offsetBy: opening.count)
                    continue
                }
                if source[cursor...].hasPrefix(closing) {
                    depth -= 1
                    let end = source.index(cursor, offsetBy: closing.count)
                    if depth == 0 {
                        return Match(
                            startByte: source.utf8.distance(from: source.startIndex, to: start),
                            endByte: source.utf8.distance(from: source.startIndex, to: end),
                            expression: OrgMathExpression(
                                latex: String(source[start..<end]),
                                original: String(source[start..<end]),
                                mode: .display
                            )
                        )
                    }
                    cursor = end
                    continue
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func isUnescaped(_ index: String.Index, in source: String) -> Bool {
        var cursor = index
        var slashes = 0
        while cursor > source.startIndex {
            let previous = source.index(before: cursor)
            guard source[previous] == "\\" else { break }
            slashes += 1
            cursor = previous
        }
        return slashes.isMultiple(of: 2)
    }

    private static func stringIndex(atUTF8Offset offset: Int, in source: String) -> String.Index {
        let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
        return String.Index(utf8Index, within: source) ?? source.endIndex
    }

    private static func validInlineDollarStart(at index: String.Index, in source: String) -> Bool {
        let next = source.index(after: index)
        guard next < source.endIndex, !source[next].isWhitespace, source[next] != "$" else { return false }
        guard index > source.startIndex else { return true }
        let previous = source[source.index(before: index)]
        return !previous.isLetter && !previous.isNumber && previous != "$"
    }

    private static func validInlineDollarEnd(at index: String.Index, in source: String) -> Bool {
        guard index > source.startIndex else { return false }
        let next = source.index(after: index)
        guard next < source.endIndex else { return true }
        // TeX in algorithm blocks commonly uses '$bb$s' and '$x \\gets $'.
        // Keep adjacent amounts such as '$5 and $6' from forming a pair.
        return !source[next].isNumber && source[next] != "$"
    }
}

struct OrgPreviewClockValue {
    private let startDraft: OrgPlanningEntryDraft?
    private let endDraft: OrgPlanningEntryDraft?
    let minutes: Int?

    init(_ node: ParsedOrgNode) {
        let timestamps = node.children.filter { $0.type == "inactive_timestamp" }
        startDraft = timestamps.first.flatMap { OrgPlanningEntryDraft(timestampSource: $0.text) }
        endDraft = timestamps.dropFirst().first.flatMap { OrgPlanningEntryDraft(timestampSource: $0.text) }
        let duration = node.children.first { $0.type == "clock_duration" }?.text
            .replacingOccurrences(of: "=>", with: "").trimmingCharacters(in: .whitespaces)
        let parts = duration?.split(separator: ":").compactMap { Int($0) } ?? []
        if parts.count == 2, parts[0] <= (Int.max - parts[1]) / 60 {
            minutes = parts[0] * 60 + parts[1]
        } else {
            minutes = nil
        }
    }

    var duration: String { minutes.map(Self.duration) ?? "Running" }

    func interval(
        locale: Locale = .autoupdatingCurrent,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard let startDraft else { return nil }
        guard let startTimestamp = startDraft.timestamps.first else { return nil }
        let startDate = startTimestamp.date
        let start = OrgPreviewDateText(draft: startDraft, locale: locale, now: now).date
        guard let endDraft, let endTimestamp = endDraft.timestamps.first else { return start }

        if calendar.isDate(startDate, inSameDayAs: endTimestamp.date) {
            var timeStyle = Date.FormatStyle.dateTime.locale(locale).hour().minute()
            timeStyle.timeZone = calendar.timeZone
            let day = OrgendaDatePresentation.date(
                startDate,
                relativeTo: now,
                locale: locale,
                calendar: calendar
            )
            return "\(day) · \(startDate.formatted(timeStyle))–\(endTimestamp.date.formatted(timeStyle))"
        }

        let end = OrgPreviewDateText(draft: endDraft, locale: locale, now: now).date
        return "\(start) → \(end)"
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours == 0 ? "\(remainder)m" : remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
