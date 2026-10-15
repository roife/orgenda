import Foundation

struct OrgMathExpression: Hashable, Sendable {
    enum Mode: String, Hashable, Sendable {
        case inline
        case display
    }

    let latex: String
    let original: String
    let mode: Mode

    init(_ node: ParsedOrgNode) {
        original = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = node.type == "latex_block" ? .display : .inline
        if original.hasPrefix("\\begin{") {
            // Environments are TeX input, including their begin/end commands.
            latex = original
        } else {
            let count = original.hasPrefix("$$") || original.hasPrefix("\\") ? 2 : 1
            latex = String(original.dropFirst(count).dropLast(count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
