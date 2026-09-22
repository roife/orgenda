import Foundation
import SwiftMath

/// Normalizes Org/LaTeX notation for the math renderer without touching source text.
@MainActor
enum OrgLatexCompatibility {
    private static let unicodeSubscripts: [Character: String] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
        "₊": "+", "₋": "-", "₌": "=", "₍": "(", "₎": ")", "ₐ": "a", "ₑ": "e", "ₕ": "h", "ᵢ": "i", "ⱼ": "j",
        "ₖ": "k", "ₗ": "l", "ₘ": "m", "ₙ": "n", "ₒ": "o", "ₚ": "p", "ᵣ": "r", "ₛ": "s", "ₜ": "t",
        "ᵤ": "u", "ᵥ": "v", "ₓ": "x", "ᵦ": #"\beta "#, "ᵧ": #"\gamma "#, "ᵨ": #"\rho "#, "ᵩ": #"\phi "#, "ᵪ": #"\chi "#,
    ]

    private static let unicodeSuperscripts: [Character: String] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁺": "+", "⁻": "-", "⁼": "=", "⁽": "(", "⁾": ")", "ⁱ": "i", "ⁿ": "n",
    ]

    private static let unicodeMathCommands: [Character: String] = [
        "−": "-", "×": #"\times{}"#, "∖": #"\setminus{}"#, "∈": #"\in{}"#, "∉": #"\notin{}"#,
        "∀": #"\forall{}"#, "∃": #"\exists{}"#, "∅": #"\emptyset{}"#, "∗": #"\ast{}"#, "•": #"\orgendaBullet{}"#,
        "⋃": #"\bigcup{}"#, "⋂": #"\bigcap{}"#, "∪": #"\cup{}"#, "∩": #"\cap{}"#,
        "≤": #"\leq{}"#, "≥": #"\geq{}"#, "≠": #"\neq{}"#, "→": #"\rightarrow{}"#, "⇒": #"\Rightarrow{}"#,
        "α": #"\alpha{}"#, "β": #"\beta{}"#, "γ": #"\gamma{}"#, "δ": #"\delta{}"#, "ε": #"\varepsilon{}"#,
        "λ": #"\lambda{}"#, "μ": #"\mu{}"#, "ν": #"\nu{}"#, "π": #"\pi{}"#, "σ": #"\sigma{}"#,
        "τ": #"\tau{}"#, "φ": #"\varphi{}"#, "χ": #"\chi{}"#, "ω": #"\omega{}"#,
        "Γ": #"\Gamma{}"#, "Δ": #"\Delta{}"#, "Σ": #"\Sigma{}"#, "Ω": #"\Omega{}"#,
    ]

    /// Work on TeX tokens and balanced arguments. Global command replacement
    /// corrupts escaped backslashes, longer control words and nested labels.
    static func normalizeLatex(_ source: String, textMode: Bool = false, preserveTextHyphens: Bool = false) -> String {
        let characters = Array(source)
        var index = 0
        var result = ""
        var environments: [(source: String, replacement: String)] = []
        let environmentAliases = [
            "align*": "aligned", "align": "aligned", "gather*": "gather",
            "eqnarray*": "eqnarray", "multline*": "displaylines", "multline": "displaylines",
        ]
        while index < characters.count {
            let character = characters[index]
            if textMode, preserveTextHyphens, character == "-" {
                result += #"\orgendaHyphen{}"#
                index += 1
                continue
            }
            if !textMode, let script = unicodeSubscripts[character] ?? unicodeSuperscripts[character] {
                let isSubscript = unicodeSubscripts[character] != nil
                let alphabet = isSubscript ? unicodeSubscripts : unicodeSuperscripts
                var contents = script
                index += 1
                while index < characters.count, let next = alphabet[characters[index]] {
                    contents += next
                    index += 1
                }
                result += (isSubscript ? "_{" : "^{") + contents + "}"
                continue
            }
            if !textMode, let command = unicodeMathCommands[character] {
                result += command
                index += 1
                continue
            }
            guard character == "\\" else {
                if !textMode, character.unicodeScalars.contains(where: { $0.value > 127 }),
                   !character.isWhitespace, MTMathAtomFactory.atom(forCharacter: character) == nil {
                    // SwiftMath silently drops unknown non-ASCII math characters.
                    // Fail visibly to the original-source fallback instead.
                    result += #"\orgendaUnsupportedUnicode{}"#
                } else {
                    result.append(character)
                }
                index += 1
                continue
            }
            let commandStart = index
            index += 1
            guard index < characters.count else { result += "\\"; break }
            guard isControlLetter(characters[index]) else {
                // In particular, consume \\ as one token; its following braces
                // are not the same thing as a literal \{ or \}.
                result += characters[index] == "&" ? #"\orgendaAmpersand{}"# : "\\" + String(characters[index])
                index += 1
                continue
            }
            let nameStart = index
            while index < characters.count, isControlLetter(characters[index]) { index += 1 }
            let command = String(characters[nameStart..<index])
            var argumentIndex = index
            if command == "text", let argument = readArgument(characters, index: &argumentIndex, groupedOnly: true) {
                result += textWithEmbeddedMath(argument, preserveTextHyphens: preserveTextHyphens)
                index = argumentIndex
                continue
            }
            if command == "begin" || command == "end",
               let environment = readArgument(characters, index: &argumentIndex, groupedOnly: true) {
                if command == "begin" {
                    var replacement = environmentAliases[environment] ?? environment
                    var option = ""
                    if ["alignat", "alignat*", "alignedat"].contains(environment) {
                        var columnsIndex = argumentIndex
                        if let columns = readArgument(characters, index: &columnsIndex, groupedOnly: true),
                           let count = Int(columns.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
                            replacement = "aligned"
                            argumentIndex = columnsIndex
                        }
                    } else if environment == "array" {
                        var specificationIndex = argumentIndex
                        if let specification = readArgument(characters, index: &specificationIndex, groupedOnly: true) {
                            let alignment = specification.filter { !$0.isWhitespace }
                            // A homogeneous array is exactly a starred matrix
                            // with that alignment. Keep mixed/ruled arrays intact.
                            if let first = alignment.first, "lcr".contains(first), alignment.allSatisfy({ $0 == first }) {
                                replacement = "matrix*"
                                option = "[\(first)]"
                                argumentIndex = specificationIndex
                            }
                        }
                    }
                    environments.append((environment, replacement))
                    result += #"\begin{"# + replacement + "}" + option
                } else {
                    let replacement: String
                    if let last = environments.last, last.source == environment {
                        replacement = last.replacement
                        environments.removeLast()
                    } else {
                        replacement = environmentAliases[environment] ?? environment
                    }
                    result += #"\end{"# + replacement + "}"
                }
                index = argumentIndex
                continue
            }
            if command == "tag" {
                let starred = argumentIndex < characters.count && characters[argumentIndex] == "*"
                if starred { argumentIndex += 1 }
                if let label = readArgument(characters, index: &argumentIndex, groupedOnly: true) {
                    let contents = starred ? label : "(" + label + ")"
                    result += #"\qquad"# + textWithEmbeddedMath(contents, preserveTextHyphens: true)
                    index = argumentIndex
                    continue
                }
            }
            if command == "overset" || command == "underset",
               let label = readArgument(characters, index: &argumentIndex),
               let base = readArgument(characters, index: &argumentIndex),
               let normalizedBase = simpleLimitBase(base) {
                let script = command == "overset" ? "^" : "_"
                result += #"{\operatorname*{"# + normalizedBase + "}" + script + "{" + normalizeLatex(label) + "}}"
                index = argumentIndex
                continue
            }
            let arrows = ["xRightarrow": "Longrightarrow", "xLeftarrow": "Longleftarrow", "xLeftrightarrow": "Longleftrightarrow",
                          "xrightarrow": "longrightarrow", "xleftarrow": "longleftarrow", "xleftrightarrow": "longleftrightarrow"]
            if let arrow = arrows[command] {
                skipWhitespace(characters, index: &argumentIndex)
                var lower: String?
                if argumentIndex < characters.count, characters[argumentIndex] == "[" {
                    lower = readGroup(characters, index: &argumentIndex, opening: "[", closing: "]")
                    if lower == nil {
                        result += String(characters[commandStart..<index])
                        continue
                    }
                }
                if let upper = readArgument(characters, index: &argumentIndex) {
                    // SwiftMath centers operator limits in inline/display math.
                    // The long arrow preserves direction and both annotations;
                    // its shaft is fixed length (the engine has no x-arrow atom).
                    result += #"{\operatorname*{\"# + arrow + "}"
                    if !upper.isEmpty { result += "^{" + normalizeLatex(upper) + "}" }
                    if let lower, !lower.isEmpty { result += "_{" + normalizeLatex(lower) + "}" }
                    result += "}"
                    index = argumentIndex
                    continue
                }
            }
            if command == "mathrel", let argument = readArgument(characters, index: &argumentIndex, groupedOnly: true) {
                // Only this known relation idiom may lose its appearance-only
                // raisebox wrapper. Keep all other mathrel payloads intact.
                let raisedRelation = argument.replacingOccurrences(
                    of: #"(?<!\\)\\raisebox\s*\{\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:ex|em|pt)\s*\}\s*\{\s*\\scriptsize\s*\$\s*([<>=])\s*\$\s*\}"#,
                    with: "$1", options: .regularExpression
                )
                let normalized = normalizeLatex(raisedRelation)
                if ["<", ">", "="].contains(normalized.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    result += normalized
                    index = argumentIndex
                    continue
                }
                if normalized.range(of: #"^\s*\{?\s*<\s*\}?\s*\\!\s*\\colon\s*$"#, options: .regularExpression) != nil {
                    result += #"\orgendaSubtype{}"#
                    index = argumentIndex
                    continue
                }
                result += String(characters[commandStart..<argumentIndex])
                index = argumentIndex
                continue
            }
            if command == "not" {
                skipWhitespace(characters, index: &argumentIndex)
                let suffix = String(characters[argumentIndex...])
                for (original, replacement) in [(#"\lt"#, #"\nless{}"#), (#"\gt"#, #"\ngtr{}"#), ("<", #"\nless{}"#), (">", #"\ngtr{}"#)] {
                    if suffix.hasPrefix(original) {
                        let end = argumentIndex + original.count
                        if original.count == 1 || end == characters.count || !isControlLetter(characters[end]) {
                            result += replacement
                            index = end
                            break
                        }
                    }
                }
                if index != nameStart + command.count { continue }
            }
            let aliases = ["exist": "exists", "plusmn": "pm"]
            if command == "lt" || command == "gt" {
                result += command == "lt" ? "<" : ">"
            } else if command == "dots" {
                // AMS \dots is centered next to binary operators/relations and
                // low in lists or at the end of a sequence.
                skipWhitespace(characters, index: &argumentIndex)
                let suffix = String(characters[argumentIndex...])
                let centered = suffix.first.map { "+-=<>".contains($0) } == true
                    || [#"\times"#, #"\cdot"#, #"\pm"#, #"\mp"#, #"\oplus"#, #"\otimes"#].contains { suffix.hasPrefix($0) }
                result += centered ? #"\cdots{}"# : #"\ldots{}"#
            } else {
                result += "\\" + (aliases[command] ?? command)
                // SwiftMath accidentally consumes * as part of every control
                // word. Only operatorname has a legitimate starred command.
                if index < characters.count, characters[index] == "*", command != "operatorname",
                   MTMathAtomFactory.atom(forLatexSymbol: aliases[command] ?? command) != nil {
                    result += "{}"
                }
            }
        }
        return result
    }

    private static func textWithEmbeddedMath(_ source: String, preserveTextHyphens: Bool) -> String {
        let characters = Array(source)
        var delimiters: [Int] = []
        var index = 0
        var braceDepth = 0
        while index < characters.count {
            switch characters[index] {
            case "\\":
                index += 2
                continue
            case "{": braceDepth += 1
            case "}": braceDepth -= 1
            case "$" where braceDepth == 0: delimiters.append(index)
            default: break
            }
            index += 1
        }
        func text(_ content: String) -> String {
            #"\text{"# + normalizeLatex(content, textMode: true, preserveTextHyphens: preserveTextHyphens) + "}"
        }
        guard !delimiters.isEmpty else { return text(source) }
        guard delimiters.count.isMultiple(of: 2),
              !stride(from: 0, to: delimiters.count, by: 2).contains(where: { delimiters[$0 + 1] == delimiters[$0] + 1 }) else {
            // An unmatched dollar or a display-math delimiter inside a text box
            // is not a valid inline switch; do not silently draw the raw marker.
            return #"\orgendaUnsupportedTextMath{}"#
        }
        var result = "{"
        var cursor = 0
        for pair in stride(from: 0, to: delimiters.count, by: 2) {
            let opening = delimiters[pair]
            let closing = delimiters[pair + 1]
            if opening > cursor { result += text(String(characters[cursor..<opening])) }
            result += "{" + normalizeLatex(String(characters[(opening + 1)..<closing])) + "}"
            cursor = closing + 1
        }
        if cursor < characters.count { result += text(String(characters[cursor...])) }
        return result + "}"
    }

    private static func simpleLimitBase(_ source: String) -> String? {
        let normalized = normalizeLatex(source)
        guard let list = MTMathListBuilder.build(fromString: normalized), list.atoms.count == 1 else { return nil }
        let atom = list.atoms[0]
        guard [.relation, .binaryOperator, .ordinary].contains(atom.type),
              atom.nucleus.count == 1, atom.subScript == nil, atom.superScript == nil else { return nil }
        return normalized
    }

    private static func isControlLetter(_ character: Character) -> Bool {
        character.isASCII && (character.isLowercase || character.isUppercase)
    }

    private static func skipWhitespace(_ characters: [Character], index: inout Int) {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    private static func readArgument(_ characters: [Character], index: inout Int, groupedOnly: Bool = false) -> String? {
        skipWhitespace(characters, index: &index)
        guard index < characters.count else { return nil }
        if characters[index] == "{" { return readGroup(characters, index: &index, opening: "{", closing: "}") }
        guard !groupedOnly, !"}^_&".contains(characters[index]) else { return nil }
        let start = index
        index += 1
        if characters[start] == "\\", index < characters.count {
            if isControlLetter(characters[index]) {
                while index < characters.count, isControlLetter(characters[index]) { index += 1 }
            } else { index += 1 }
        }
        return String(characters[start..<index])
    }

    private static func readGroup(_ characters: [Character], index: inout Int, opening: Character, closing: Character) -> String? {
        let start = index + 1
        var cursor = start
        var depth = 1
        var braceDepth = 0
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\" {
                cursor += 2
                continue
            }
            // Braced material inside an optional argument may contain ] itself.
            if opening == "[" {
                if character == "{" { braceDepth += 1 }
                if character == "}" { braceDepth -= 1 }
            }
            if braceDepth == 0 {
                if character == opening { depth += 1 }
                if character == closing {
                    depth -= 1
                    if depth == 0 {
                        index = cursor + 1
                        return String(characters[start..<cursor])
                    }
                }
            }
            cursor += 1
        }
        return nil
    }
}
