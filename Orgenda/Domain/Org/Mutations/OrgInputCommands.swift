import Foundation

struct OrgTextEdit: Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

enum OrgInputCommand {
    case heading, checkbox, indent, outdent

    var title: String {
        switch self {
        case .heading: String(localized: "Insert heading")
        case .checkbox: String(localized: "Insert checkbox")
        case .indent: String(localized: "Indent")
        case .outdent: String(localized: "Outdent")
        }
    }
}

/// All editor ranges are UTF-16, including emoji and CJK selections.
enum OrgInputCommands {
    static func edit(_ command: OrgInputCommand, source: String, selection: NSRange) -> OrgTextEdit? {
        let text = source as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= text.length else { return nil }
        // A selection ending at the next line's start must not change that line.
        let selected = NSRange(location: selection.location, length: max(0, selection.length - 1))
        let range = text.lineRange(for: selected)
        let original = text.substring(with: range)
        var lines = original.components(separatedBy: "\n")
        let hasTrailingNewline = lines.last == "" && lines.count > 1
        if hasTrailingNewline { lines.removeLast() }
        var deltas: [(Int, Int)] = []
        var offset = range.location
        for index in lines.indices {
            let line = lines[index]
            let prefix: String
            var removed = 0
            let heading = match(#"^(\*+)[ \t]+"#, in: line)
            switch command {
            case .heading:
                prefix = heading == nil ? "* " : "*"
            case .checkbox:
                if let item = match(#"^([ \t]*(?:[-+]|\d+[.)])[ \t]+)(\[[ Xx-]\][ \t]*)?"#, in: line) {
                    guard item.range(at: 2).location == NSNotFound else {
                        offset += line.utf16.count + 1
                        continue
                    }
                    let insertAt = item.range(at: 1).length
                    lines[index] = (line as NSString).replacingCharacters(in: NSRange(location: insertAt, length: 0), with: "[ ] ")
                    deltas.append((offset + insertAt, 4))
                    offset += line.utf16.count + 1
                    continue
                }
                prefix = "- [ ] "
            case .indent:
                prefix = heading == nil ? "  " : "*"
            case .outdent:
                prefix = ""
                if let heading {
                    removed = heading.range(at: 1).length > 1 ? 1 : 0
                } else {
                    removed = line.hasPrefix("\t") ? 1 : min(2, line.prefix { $0 == " " }.count)
                }
            }
            lines[index] = prefix + String(line.dropFirst(removed))
            deltas.append((offset, prefix.utf16.count - removed))
            offset += line.utf16.count + 1
        }
        let replacement = lines.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        guard replacement != original else { return nil }
        func mapped(_ position: Int) -> Int {
            max(range.location, position + deltas.filter { $0.0 <= position }.reduce(0) { $0 + $1.1 })
        }
        let start = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        return OrgTextEdit(range: range, replacement: replacement,
                           selection: NSRange(location: start, length: max(0, end - start)))
    }

    static func newline(source: String, selection: NSRange) -> OrgTextEdit? {
        let text = source as NSString
        guard selection.length == 0, selection.location <= text.length else { return nil }
        let lineRange = text.lineRange(for: selection)
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        // Source/example blocks are literal text; Return must not synthesize Org lists.
        let before = text.substring(to: lineRange.location)
        var inBlock = false
        var inDrawer = false
        for previous in before.components(separatedBy: .newlines) {
            let marker = previous.trimmingCharacters(in: .whitespaces).uppercased()
            if marker.hasPrefix("#+BEGIN_") { inBlock = true }
            if marker.hasPrefix("#+END_") { inBlock = false }
            if marker == ":END:" { inDrawer = false }
            else if match(#"^:[A-Z0-9_@#%]+:$"#, in: marker) != nil { inDrawer = true }
        }
        guard !inBlock, !inDrawer,
              let item = match(#"^([ \t]*)([-+]|\d+[.)])([ \t]+)(?:\[[ Xx-]\]([ \t]+))?"#, in: line),
              selection.location >= lineRange.location + item.range.length else { return nil }
        let nsLine = line as NSString
        let body = nsLine.substring(from: item.range.length)
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            let range = NSRange(location: lineRange.location, length: line.utf16.count)
            return OrgTextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
        }
        let indentation = nsLine.substring(with: item.range(at: 1))
        var bullet = nsLine.substring(with: item.range(at: 2))
        if let number = Int(bullet.dropLast()), number < Int.max { bullet = "\(number + 1)\(bullet.suffix(1))" }
        let checkbox = item.range(at: 4).location == NSNotFound ? "" : "[ ] "
        let insertion = "\n" + indentation + bullet + " " + checkbox
        return OrgTextEdit(range: selection, replacement: insertion,
                           selection: NSRange(location: selection.location + insertion.utf16.count, length: 0))
    }

    /// Use a character-boundary diff so native text undo remains valid on either side.
    static func difference(from old: String, to new: String) -> OrgTextEdit {
        let prefix = zip(old, new).prefix { $0 == $1 }.map(\.0)
        let oldTail = old.dropFirst(prefix.count)
        let newTail = new.dropFirst(prefix.count)
        let suffixCount = zip(oldTail.reversed(), newTail.reversed()).prefix { $0 == $1 }.count
        let removed = oldTail.dropLast(suffixCount)
        let inserted = String(newTail.dropLast(suffixCount))
        let location = String(prefix).utf16.count
        return OrgTextEdit(range: NSRange(location: location, length: removed.utf16.count), replacement: inserted,
                           selection: NSRange(location: location + inserted.utf16.count, length: 0))
    }

    private static let expressions: [String: NSRegularExpression] = {
        let patterns = [
            #"^(\*+)[ \t]+"#,
            #"^([ \t]*(?:[-+]|\d+[.)])[ \t]+)(\[[ Xx-]\][ \t]*)?"#,
            #"^:[A-Z0-9_@#%]+:$"#,
            #"^([ \t]*)([-+]|\d+[.)])([ \t]+)(?:\[[ Xx-]\]([ \t]+))?"#,
        ]
        return patterns.reduce(into: [:]) { result, pattern in
            result[pattern] = try? NSRegularExpression(pattern: pattern)
        }
    }()

    private static func match(_ pattern: String, in string: String) -> NSTextCheckingResult? {
        let expression = expressions[pattern] ?? (try? NSRegularExpression(pattern: pattern))
        return expression?.firstMatch(in: string, range: NSRange(location: 0, length: string.utf16.count))
    }
}
