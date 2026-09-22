import Foundation

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
            let trimmed = OrgPreviewMarkup.trimmed(inline, spaces: false)
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

}
