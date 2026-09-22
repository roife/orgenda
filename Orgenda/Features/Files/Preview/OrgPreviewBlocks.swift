import SwiftUI
import Highlighter
import SwiftMath
import UIKit

struct OrgPreviewTable: View {
    let node: ParsedOrgNode

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, row in
                    if row.type == "table_separator" {
                        Divider().gridCellColumns(columnCount).gridCellUnsizedAxes(.horizontal)
                    } else {
                        GridRow {
                            ForEach(0..<columnCount, id: \.self) { column in
                                let cells = cells(in: row)
                                OrgPreviewRichText(
                                    fragments: column < cells.count ? cells[column].map {
                                        OrgPreviewMarkup.fragments($0, trimSpaces: true)
                                    } ?? [.text(AttributedString(" "))] : [.text(AttributedString(" "))],
                                    textStyle: .subheadline
                                )
                                .font(.subheadline)
                                .fontWeight(index == 0 && hasHeader ? .semibold : .regular)
                                .padding(.vertical, 5)
                                .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("org.preview.table.\(node.startByte)")
    }

    private var hasHeader: Bool { node.children.dropFirst().first?.type == "table_separator" }
    private var columnCount: Int { max(1, node.children.map { cells(in: $0).count }.max() ?? 1) }

    private func cells(in row: ParsedOrgNode) -> [ParsedOrgNode?] {
        var result: [ParsedOrgNode?] = []
        var current: ParsedOrgNode?
        var hasPipe = false
        for child in row.children {
            if child.type == "table_pipe" {
                if hasPipe { result.append(current); current = nil }
                hasPipe = true
            } else if child.type == "table_cell" { current = child }
        }
        if let current { result.append(current) }
        return result
    }
}

struct OrgPreviewSourceBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let node: ParsedOrgNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: node.type == "source_block" ? "chevron.left.forwardslash.chevron.right" : "text.alignleft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(renderedCode)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("org.preview.source.content.\(node.startByte)")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("org.preview.source.\(node.startByte)")
    }

    private var renderedCode: AttributedString {
        let source = OrgPreviewMarkup.literalText(node)
        guard node.type == "source_block" else {
            var plain = AttributedString(source)
            plain.font = .system(.footnote, design: .monospaced)
            return plain
        }
        return OrgCodeHighlighting.attributed(
            source,
            language: sourceLanguage,
            colorScheme: colorScheme,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var sourceLanguage: String? {
        node.child(ofType: "source_block_begin")?.child(ofType: "source_language")?.text
    }

    private var label: String {
        switch node.type {
        case "example_block": return String(localized: "Example")
        case "export_block":
            let format = node.children.first?.text.split(whereSeparator: \.isWhitespace).dropFirst().first.map(String.init)
            return format.map { String(localized: "\($0.uppercased()) export") } ?? String(localized: "Export")
        case "fixed_width": return String(localized: "Fixed width")
        default:
            return sourceLanguage ?? String(localized: "Code")
        }
    }
}

struct OrgPreviewRichText: View {
    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body

    var body: some View {
        if fragments.contains(where: { if case .image = $0 { return true }; return false }) {
            OrgPreviewImageFlow(fragments: fragments, textStyle: textStyle)
        } else {
            OrgPreviewInlineText(fragments: fragments, textStyle: textStyle)
        }
    }
}

struct OrgPreviewInlineText: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body

    var body: some View {
        renderedText
    }

    private var renderedText: Text {
        fragments.reduce(Text("")) { result, fragment in
            switch fragment {
            case .text(let value):
                return result + Text(value)
            case .image(let reference):
                return result + Text(reference.label)
            case .math(let expression):
                guard let rendered = OrgMathRendering.render(
                    expression,
                    textStyle: textStyle,
                    dynamicTypeSize: dynamicTypeSize,
                    colorScheme: colorScheme
                ) else {
                    return result + Text(expression.original)
                }
                return result + Text(Image(uiImage: rendered.image))
                    .baselineOffset(-rendered.descent)
            }
        }
    }
}

struct OrgPreviewMathBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let expression: OrgMathExpression

    var body: some View {
        ScrollView(.horizontal) {
            if let rendered = OrgMathRendering.render(
                expression,
                textStyle: .body,
                dynamicTypeSize: dynamicTypeSize,
                colorScheme: colorScheme
            ) {
                Image(uiImage: rendered.image)
                    .accessibilityLabel(expression.original)
            } else {
                Text(expression.original)
                    .font(.body.monospaced())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
    }
}

final class OrgMathCacheEntry: NSObject {
    let image: UIImage
    let descent: CGFloat

    init(image: UIImage, descent: CGFloat) {
        self.image = image
        self.descent = descent
    }
}

@MainActor
enum OrgMathRendering {
    private static let cache: NSCache<NSString, OrgMathCacheEntry> = {
        let cache = NSCache<NSString, OrgMathCacheEntry>()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func render(
        _ expression: OrgMathExpression,
        textStyle: UIFont.TextStyle,
        dynamicTypeSize: DynamicTypeSize,
        colorScheme: ColorScheme
    ) -> OrgMathCacheEntry? {
        let fontSize = OrgPreviewFontMetrics.pointSize(for: textStyle, dynamicTypeSize: dynamicTypeSize)
        let scale = UIScreen.main.scale
        let latex = compatibleLatex(expression.latex)
        let key = "\(expression.mode.rawValue)\u{0}\(colorScheme == .dark ? "dark" : "light")\u{0}\(fontSize)\u{0}\(scale)\u{0}\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let color = UIColor.label.resolvedColor(with: traits)
        var renderer = MathImage(
            latex: latex,
            fontSize: expression.mode == .display ? fontSize * 1.08 : fontSize,
            textColor: color,
            labelMode: expression.mode == .display ? .display : .text,
            textAlignment: .center
        )
        let (_, image, layout) = renderer.asImage()
        guard let image, let layout else { return nil }
        let entry = OrgMathCacheEntry(image: image, descent: layout.descent)
        cache.setObject(entry, forKey: key, cost: imageCost(image))
        return entry
    }

    static func compatibleLatex(_ latex: String) -> String {
        registerCompatibilitySymbols()
        return normalizeLatex(latex)
    }

    private static let compatibilitySymbolsRegistered: Void = {
        // Register the actual Unicode glyph with the correct atom class, rather
        // than approximate double brackets, harpoons or definition relations.
        let symbols: [(String, String, MTMathAtomType)] = [
            ("llbracket", "⟦", .open), ("rrbracket", "⟧", .close),
            // Latin Modern lacks U+2A74; these two supported glyphs spell
            // the same double-colon equals relation without a missing-glyph box.
            ("Coloneqq", "∷=", .relation), ("coloneqq", "≔", .relation),
            ("rightharpoonup", "⇀", .relation), ("leftharpoonup", "↼", .relation),
            ("rightharpoondown", "⇁", .relation), ("leftharpoondown", "↽", .relation),
            ("vDash", "⊨", .relation), ("nrightarrow", "↛", .relation),
            ("orgendaBullet", "•", .ordinary), ("orgendaAmpersand", "&", .ordinary),
            ("orgendaHyphen", "-", .ordinary),
            ("orgendaSubtype", "<:", .relation),
        ]
        for (name, glyph, type) in symbols where MTMathAtomFactory.atom(forLatexSymbol: name) == nil {
            guard let atom = MTMathAtomFactory.atom(forCharacter: "=") else { continue }
            atom.nucleus = glyph
            atom.type = type
            MTMathAtomFactory.add(latexSymbol: name, value: atom)
        }
    }()

    private static func registerCompatibilitySymbols() {
        _ = compatibilitySymbolsRegistered
    }

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
    private static func normalizeLatex(_ source: String, textMode: Bool = false, preserveTextHyphens: Bool = false) -> String {
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
                        if let columns = readArgument(characters, index: &argumentIndex, groupedOnly: true),
                           let count = Int(columns.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
                            replacement = "aligned"
                        } else {
                            argumentIndex = index
                            _ = readArgument(characters, index: &argumentIndex, groupedOnly: true)
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
            if ["xRightarrow", "xLeftarrow", "xLeftrightarrow", "xrightarrow", "xleftarrow", "xleftrightarrow"].contains(command) {
                let arrows = ["xRightarrow": "Longrightarrow", "xLeftarrow": "Longleftarrow", "xLeftrightarrow": "Longleftrightarrow",
                              "xrightarrow": "longrightarrow", "xleftarrow": "longleftarrow", "xleftrightarrow": "longleftrightarrow"]
                skipWhitespace(characters, index: &argumentIndex)
                var lower: String?
                if argumentIndex < characters.count, characters[argumentIndex] == "[" {
                    lower = readGroup(characters, index: &argumentIndex, opening: "[", closing: "]")
                    if lower == nil {
                        result += String(characters[commandStart..<index])
                        continue
                    }
                }
                if let upper = readArgument(characters, index: &argumentIndex), let arrow = arrows[command] {
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
                index += min(2, characters.count - index)
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
        var error: NSError?
        guard let list = MTMathListBuilder.build(fromString: normalized, error: &error), error == nil,
              list.atoms.count == 1, let atom = list.atoms.first,
              [.relation, .binaryOperator, .ordinary].contains(atom.type),
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
        guard index < characters.count, characters[index] == opening else { return nil }
        let start = index + 1
        var cursor = start
        var depth = 1
        var braceDepth = 0
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\" {
                cursor += min(2, characters.count - cursor)
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

    private static func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

@MainActor
enum OrgCodeHighlighting {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 128
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    private static var highlighters: [String: Highlighter] = [:]

    static func attributed(
        _ source: String,
        language: String?,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize
    ) -> AttributedString {
        let fontSize = OrgPreviewFontMetrics.pointSize(for: .footnote, dynamicTypeSize: dynamicTypeSize)
        let theme = colorScheme == .dark ? "github-dark" : "github"
        let normalizedLanguage = normalized(language)
        let highlighterKey = "\(theme)\u{0}\(fontSize)"
        let key = "\(theme)\u{0}\(fontSize)\u{0}\(normalizedLanguage ?? "")\u{0}\(source)" as NSString
        if let cached = cache.object(forKey: key) { return AttributedString(cached) }

        let highlighter: Highlighter
        if let existing = highlighters[highlighterKey] {
            highlighter = existing
        } else if let created = Highlighter() {
            created.setTheme(theme, withFont: "Menlo-Regular", ofSize: fontSize)
            highlighters[highlighterKey] = created
            highlighter = created
        } else {
            return fallback(source)
        }

        guard let highlighted = highlighter.highlight(source, as: normalizedLanguage) else {
            return fallback(source)
        }
        let mutable = NSMutableAttributedString(attributedString: highlighted)
        mutable.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: mutable.length))
        cache.setObject(mutable, forKey: key, cost: max(1, mutable.length * 16))
        return AttributedString(mutable)
    }

    private static func normalized(_ language: String?) -> String? {
        guard let language = language?.lowercased(), !language.isEmpty else { return nil }
        let aliases = [
            "c++": "cpp", "c#": "csharp", "elisp": "lisp", "emacs-lisp": "lisp",
            "js": "javascript", "objc": "objectivec", "py": "python", "rb": "ruby",
            "sh": "shell", "shell-script": "shell", "ts": "typescript", "yml": "yaml",
        ]
        return aliases[language] ?? language
    }

    private static func fallback(_ source: String) -> AttributedString {
        var value = AttributedString(source)
        value.font = .system(.footnote, design: .monospaced)
        return value
    }
}

enum OrgPreviewFontMetrics {
    static func pointSize(for style: UIFont.TextStyle, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory(dynamicTypeSize))
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    }

    private static func contentSizeCategory(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

struct OrgPreviewQuote: View {
    let node: ParsedOrgNode

    var body: some View {
        OrgPreviewMathFlow(
            fragments: OrgPreviewContainerMath.blockFragments(node),
            textStyle: .subheadline
        )
            .font(.subheadline.italic())
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(OrgendaTheme.accent)
                    .frame(width: 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier("org.preview.quote.\(node.startByte)")
    }

}

/// Render a block's body as one source range so display formulas can span its
/// line nodes and blank lines without including Org's block delimiters.
enum OrgPreviewContainerMath {
    enum Segment {
        case inline([OrgPreviewInlineFragment])
        case display(OrgMathExpression)
    }

    static func blockFragments(_ node: ParsedOrgNode) -> [OrgPreviewInlineFragment] {
        let children = OrgPreviewMarkup.contents(of: node)
        guard let first = children.first, let last = children.last else { return [] }
        let lower = first.startByte - node.startByte
        let upper = last.endByte - node.startByte
        let bytes = Array(node.text.utf8)
        guard lower >= 0, upper >= lower, upper <= bytes.count else { return [] }
        let body = ParsedOrgNode(
            id: "\(node.id):body", type: "block_content",
            text: String(decoding: bytes[lower..<upper], as: UTF8.self),
            startByte: first.startByte, endByte: last.endByte, children: children
        )
        return OrgPreviewMarkup.fragments(body)
    }

    static func segments(_ fragments: [OrgPreviewInlineFragment]) -> [Segment] {
        var result: [Segment] = []
        var inline: [OrgPreviewInlineFragment] = []
        func flush() {
            let trimmed = trimmingBoundaryNewlines(inline)
            if !trimmed.isEmpty { result.append(.inline(trimmed)) }
            inline.removeAll(keepingCapacity: true)
        }
        for fragment in fragments {
            if case .math(let expression) = fragment, expression.mode == .display {
                flush()
                result.append(.display(expression))
            } else {
                inline.append(fragment)
            }
        }
        flush()
        return result
    }

    private static func trimmingBoundaryNewlines(
        _ fragments: [OrgPreviewInlineFragment]
    ) -> [OrgPreviewInlineFragment] {
        var result = fragments
        while let first = result.first, case .text(var value) = first {
            while value.characters.first?.isNewline == true {
                value.removeSubrange(value.startIndex..<value.characters.index(after: value.startIndex))
            }
            if value.characters.isEmpty { result.removeFirst() }
            else { result[0] = .text(value); break }
        }
        while let last = result.last, case .text(var value) = last {
            while value.characters.last?.isNewline == true {
                value.removeSubrange(value.characters.index(before: value.endIndex)..<value.endIndex)
            }
            if value.characters.isEmpty { result.removeLast() }
            else { result[result.count - 1] = .text(value); break }
        }
        return result
    }
}

struct OrgPreviewMathFlow: View {
    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body
    var centered = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 4) {
            ForEach(Array(OrgPreviewContainerMath.segments(fragments).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .inline(let fragments):
                    OrgPreviewRichText(fragments: fragments, textStyle: textStyle)
                        .fixedSize(horizontal: false, vertical: true)
                case .display(let expression):
                    OrgPreviewMathBlock(expression: expression)
                }
            }
        }
    }
}

struct OrgPreviewParagraph: View {
    @Environment(\.locale) private var locale
    let node: ParsedOrgNode
    let pendingReplacements: [String: PendingSourceReplacement]
    let onEdit: (ParsedOrgNode, OrgPlanningEntryDraft) -> Void

    @ViewBuilder
    var body: some View {
        if timestamps.count == 1, let timestamp = timestamps.first,
           node.text.trimmingCharacters(in: .whitespacesAndNewlines) == timestamp.text,
           let draft = draft(for: timestamp) {
            OrgPreviewPlanningEntryControl(
                entry: timestamp,
                draft: draft,
                isUpdating: pendingReplacements[timestamp.id] != nil,
                onEdit: { onEdit(timestamp, draft) }
            )
        } else {
            Group {
                if let expression = displayExpression {
                    OrgPreviewMathBlock(expression: expression)
                } else {
                    OrgPreviewRichText(fragments: linkedFragments)
                }
            }
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if OrgPreviewMarkup.externalURL(url.absoluteString) != nil { return .systemAction }
                    guard let timestamp = timestamps.first(where: { link(for: $0) == url }),
                          pendingReplacements[timestamp.id] == nil,
                          let draft = draft(for: timestamp) else { return .discarded }
                    onEdit(timestamp, draft)
                    return .handled
                })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("org.preview.paragraph.\(node.startByte)")
        }
    }

    private var timestamps: [ParsedOrgNode] {
        func collect(_ node: ParsedOrgNode) -> [ParsedOrgNode] {
            if ["timestamp_range", "timestamp", "active_timestamp", "inactive_timestamp"].contains(node.type) {
                return [node]
            }
            return node.children.flatMap(collect)
        }
        return collect(node)
    }

    private func draft(for timestamp: ParsedOrgNode) -> OrgPlanningEntryDraft? {
        OrgPlanningEntryDraft(timestampSource: pendingReplacements[timestamp.id]?.replacement ?? timestamp.text)
    }

    private func link(for timestamp: ParsedOrgNode) -> URL? {
        URL(string: "orgenda-timestamp://edit/\(timestamp.startByte)")
    }

    private var linkedFragments: [OrgPreviewInlineFragment] {
        let timestampIDs = Set(timestamps.map(\.id))
        return OrgPreviewMarkup.fragments(node) { timestamp in
            guard timestampIDs.contains(timestamp.id) else { return nil }
            guard let draft = draft(for: timestamp) else { return AttributedString(timestamp.text) }
            let presentation = OrgPreviewDateText(draft: draft, locale: locale)
            var date = AttributedString(([presentation.date] + presentation.details).joined(separator: " · "))
            date.link = link(for: timestamp)
            return date
        }
    }

    private var displayExpression: OrgMathExpression? {
        guard linkedFragments.count == 1, case .math(let expression) = linkedFragments[0],
              expression.mode == .display else { return nil }
        return expression
    }
}

struct OrgPreviewKeyword: View {
    let node: ParsedOrgNode

    @ViewBuilder
    var body: some View {
        if node.text.lowercased().hasPrefix("#+title:") {
            Text(node.text.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.title2.bold())
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
        } else if node.text.lowercased().hasPrefix("#+caption:"),
                  let value = node.child(ofType: "keyword_value") {
            OrgPreviewRichText(fragments: OrgPreviewMarkup.fragments(value, trimSpaces: true), textStyle: .subheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } else {
            Text(node.text.trimmingCharacters(in: .newlines))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

struct OrgPreviewFallback: View {
    let source: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(source.components(separatedBy: .newlines).enumerated()), id: \.offset) { line in
                let parts = line.element.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                Group {
                    if parts.count == 3, parts[0].allSatisfy({ $0 == "*" }),
                       let state = OrgWorkflowState(rawValue: String(parts[1])) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(parts[0]).foregroundStyle(.secondary)
                            OrgWorkflowIcon(state)
                            Text(parts[2]).foregroundStyle(OrgendaTheme.workflowColor(state))
                        }
                    } else {
                        Text(line.element.isEmpty ? " " : line.element)
                    }
                }
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .padding(.bottom, 16)
        .accessibilityIdentifier("org.preview.fallback")
    }
}
