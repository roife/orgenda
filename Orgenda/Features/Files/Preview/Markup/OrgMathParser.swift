import Foundation

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
                index = source.utf8.index(source.startIndex, offsetBy: match.endByte)
                continue
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix(#"\["#),
               let match = delimited(in: source, from: index, opening: #"\["#, closing: #"\]"#, mode: .display) {
                append(match)
                index = source.utf8.index(source.startIndex, offsetBy: match.endByte)
                continue
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix(#"\("#),
               let match = delimited(in: source, from: index, opening: #"\("#, closing: #"\)"#, mode: .inline) {
                append(match)
                index = source.utf8.index(source.startIndex, offsetBy: match.endByte)
                continue
            }
            if isUnescaped(index, in: source), source[index...].hasPrefix(#"\begin{"#),
               let match = environment(in: source, from: index) {
                append(match)
                index = source.utf8.index(source.startIndex, offsetBy: match.endByte)
                continue
            }
            if source[index] == "$", isUnescaped(index, in: source),
               validInlineDollarStart(at: index, in: source),
               let match = delimited(in: source, from: index, opening: "$", closing: "$", mode: .inline,
                                     validateEnd: { validInlineDollarEnd(at: $0, in: source) }) {
                append(match)
                index = source.utf8.index(source.startIndex, offsetBy: match.endByte)
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

    private static func validInlineDollarStart(at index: String.Index, in source: String) -> Bool {
        let next = source.index(after: index)
        guard next < source.endIndex, !source[next].isWhitespace, source[next] != "$" else { return false }
        guard index > source.startIndex else { return true }
        let previous = source[source.index(before: index)]
        return !previous.isLetter && !previous.isNumber && previous != "$"
    }

    private static func validInlineDollarEnd(at index: String.Index, in source: String) -> Bool {
        let next = source.index(after: index)
        guard next < source.endIndex else { return true }
        // TeX in algorithm blocks commonly uses '$bb$s' and '$x \\gets $'.
        // Keep adjacent amounts such as '$5 and $6' from forming a pair.
        return !source[next].isNumber && source[next] != "$"
    }
}
