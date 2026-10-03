import Foundation

enum ConfiguredCapture {
    struct Expansion: Identifiable, Equatable {
        var id: Int { start }
        let start: Int
        let end: Int
        let token: String
        let prompt: String?
        let choices: [String]
    }

    /// Byte offsets allow repeated prompts and multibyte titles without
    /// replacing literal text that happens to resemble an expanded value.
    static func expansions(in template: String) throws -> [Expansion] {
        var result: [Expansion] = []
        var cursor = template.startIndex
        while cursor < template.endIndex {
            guard template[cursor] == "%" else { cursor = template.index(after: cursor); continue }
            let start = cursor
            cursor = template.index(after: cursor)
            guard cursor < template.endIndex else { throw ConfigurationFailure(message: "capture: incomplete % placeholder.") }
            let character = template[cursor]
            cursor = template.index(after: cursor)
            var prompt: String?
            var choices: [String] = []
            if character == "^" {
                guard cursor < template.endIndex, template[cursor] == "{",
                      let end = template[cursor...].firstIndex(of: "}") else {
                    throw ConfigurationFailure(message: "capture: expected %^{Prompt|Default|Choices}.")
                }
                let components = template[template.index(after: cursor)..<end].components(separatedBy: "|")
                prompt = components[0]
                choices = Array(components.dropFirst())
                cursor = template.index(after: end)
                if cursor < template.endIndex, "tTuU".contains(template[cursor]) { cursor = template.index(after: cursor) }
            } else if character == "<" {
                guard let end = template[cursor...].firstIndex(of: ">") else {
                    throw ConfigurationFailure(message: "capture: unclosed date format.")
                }
                let format = String(template[cursor..<end])
                // Deliberately bounded strftime subset; no platform-dependent
                // silent interpretation of unsupported directives.
                let allowed = ["%Y", "%m", "%d", "%H", "%M", "%a", "%A", "%b", "%B", "%%"]
                var remainder = format
                for value in allowed { remainder = remainder.replacingOccurrences(of: value, with: "") }
                guard !remainder.contains("%") else { throw ConfigurationFailure(message: "capture: unsupported date format.") }
                cursor = template.index(after: end)
            } else if !"%?tTuUaix".contains(character) {
                throw ConfigurationFailure(message: "capture: unsupported placeholder %\(character). Lisp and external templates are not executed.")
            }
            result.append(Expansion(start: template[..<start].utf8.count, end: template[..<cursor].utf8.count,
                                    token: String(template[start..<cursor]), prompt: prompt, choices: choices))
        }
        return result
    }

    static func render(_ template: String, answers: [Int: String] = [:], cursorText: String = "",
                       date: Date = .now, link: String = "", selection: String = "", clipboard: String = "") throws -> String {
        var result = template
        for expansion in try expansions(in: template).reversed() {
            let replacement: String
            if let prompt = expansion.prompt {
                guard let answer = answers[expansion.id] ?? expansion.choices.first else {
                    throw ConfigurationFailure(message: "capture: answer required for \(prompt).")
                }
                replacement = answer
            } else {
                switch expansion.token {
                case "%%": replacement = "%"
                case "%?": replacement = cursorText
                case "%a": replacement = link
                case "%i": replacement = selection
                case "%x": replacement = clipboard
                case "%t", "%T", "%u", "%U":
                    let active = expansion.token == "%t" || expansion.token == "%T"
                    let time = expansion.token == "%T" || expansion.token == "%U"
                    replacement = timestamp(date, active: active, time: time)
                default:
                    let format = String(expansion.token.dropFirst(2).dropLast())
                    replacement = formatted(date, format: format)
                }
            }
            result = try OrgSourceMutation(startByte: expansion.start, endByte: expansion.end, replacement: replacement).applied(to: result)
        }
        return result
    }

    static func timestamp(_ date: Date, active: Bool, time: Bool) -> String {
        let value = formatted(date, format: time ? "%Y-%m-%d %a %H:%M" : "%Y-%m-%d %a")
        return (active ? "<" : "[") + value + (active ? ">" : "]")
    }

    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        let mapping = ["Y": "yyyy", "m": "MM", "d": "dd", "H": "HH", "M": "mm", "a": "EEE", "A": "EEEE", "b": "MMM", "B": "MMMM"]
        var result = ""
        var directive = false
        for character in format {
            if directive {
                if let pattern = mapping[String(character)] {
                    formatter.dateFormat = pattern
                    result += formatter.string(from: date)
                } else { result.append(character) }
                directive = false
            } else if character == "%" { directive = true }
            else { result.append(character) }
        }
        return result
    }

    /// Insertion operates only on indexed structural headings, not stars in
    /// source blocks. Missing targets are reported rather than guessed.
    static func inserting(_ rendered: String, template: WorkspaceConfiguration.Template,
                          into source: String, parsed: ParsedOrgDocument, date: Date = .now,
                          createMissing: Bool = false) throws -> String {
        var outline = template.target.outline
        if template.target.type == .datetree {
            let calendar = Calendar(identifier: .gregorian)
            outline += [String(calendar.component(.year, from: date)),
                        formatted(date, format: "%Y-%m"),
                        formatted(date, format: "%Y-%m-%d %A")]
        }
        let headings = parsed.root.children.filter { $0.type == "heading" }
        var parent: ParsedOrgNode?
        var lower = 0
        var upper = source.utf8.count
        var level = 0
        func headingLevel(_ node: ParsedOrgNode) -> Int { node.text.prefix(while: { $0 == "*" }).count }
        for title in outline {
            let candidates = headings.filter {
                $0.startByte >= lower && $0.startByte < upper && headingLevel($0) == level + 1
                    && $0.child(ofType: "heading_title")?.text.trimmingCharacters(in: .whitespacesAndNewlines) == title
            }
            guard candidates.count <= 1 else { throw ConfigurationFailure(message: "capture: ambiguous target heading \(title).") }
            guard let match = candidates.first else {
                guard createMissing else { throw ConfigurationFailure(message: "capture: missing target heading \(title). Confirm creation first.") }
                let remaining = outline.dropFirst(level)
                let prefix = remaining.enumerated().map { String(repeating: "*", count: level + $0.offset + 1) + " " + $0.element }.joined(separator: "\n") + "\n"
                let entry = try adjusted(rendered, type: template.type, level: outline.count + 1)
                let newline = source.contains("\r\n") ? "\r\n" : "\n"
                let text = ((upper > 0 ? "\n" : "") + prefix + entry + "\n")
                    .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: newline)
                return try OrgSourceMutation(startByte: upper, endByte: upper, replacement: text).applied(to: source)
            }
            parent = match
            level += 1
            lower = match.endByte
            upper = headings.first(where: { $0.startByte > match.startByte && headingLevel($0) <= level })?.startByte ?? source.utf8.count
        }
        var insertion = template.prepend ? (parent?.endByte ?? 0) : upper
        if template.prepend, let parent {
            for node in parsed.root.children where node.startByte >= parent.endByte && node.startByte < upper {
                guard ["planning", "property_drawer", "drawer", "blank_line"].contains(node.type) else { break }
                insertion = node.endByte
            }
        } else if template.prepend {
            // File keywords must stay in the preamble, before captured entries.
            insertion = headings.first?.startByte ?? source.utf8.count
        }
        let body = try adjusted(rendered, type: template.type, level: level + 1)
        let spacing = String(repeating: "\n", count: template.emptyLines)
        let before = String(decoding: source.utf8.prefix(insertion), as: UTF8.self)
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        let text = ((before.isEmpty || before.hasSuffix("\n") ? "" : "\n") + spacing + body + "\n" + spacing)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: newline)
        return try OrgSourceMutation(startByte: insertion, endByte: insertion, replacement: text).applied(to: source)
    }

    private static func adjusted(_ source: String, type: WorkspaceConfiguration.CaptureType, level: Int) throws -> String {
        switch type {
        case .plain: return source
        case .item: return source.hasPrefix("- ") ? source : "- " + source
        case .checkitem: return source.hasPrefix("- [") ? source : "- [ ] " + source
        case .entry:
            guard source.hasPrefix("* ") else { throw ConfigurationFailure(message: "capture: entry templates must begin with '* '.") }
            // Use the parser so stars inside blocks remain literal.
            let document = WorkspaceDocument(path: "capture.org", title: "", contents: source, kind: .org)
            let parsed = OrgIndexService.parseSynchronously([document])[0]
            return try parsed.root.children.filter { $0.type == "heading" }.reversed().reduce(source) { result, heading in
                let count = heading.text.prefix(while: { $0 == "*" }).count
                return try OrgSourceMutation(startByte: heading.startByte, endByte: heading.startByte + count,
                                             replacement: String(repeating: "*", count: count + level - 1)).applied(to: result)
            }
        }
    }
}
