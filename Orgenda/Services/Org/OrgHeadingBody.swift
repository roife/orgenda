import Foundation

/// Shared by indexing and source edits so editing notes never consumes drawer
/// metadata or logs. Containers come directly from the tree-sitter grammar.
enum OrgHeadingBody {
    static func nodesOutsideDrawers(in nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        nodes.filter { !["property_drawer", "drawer"].contains($0.type) }
    }

    static func firstActiveTimestamp(in nodes: [ParsedOrgNode]) -> ParsedOrgNode? {
        func first(in node: ParsedOrgNode) -> ParsedOrgNode? {
            if node.type == "active_timestamp" { return node }
            if node.type == "timestamp_range",
               node.children.allSatisfy({ $0.text.hasPrefix("<") }) { return node }
            return node.children.lazy.compactMap { first(in: $0) }.first
        }
        return nodesOutsideDrawers(in: nodes)
            .filter { ["paragraph", "list"].contains($0.type) }
            .lazy.compactMap { first(in: $0) }.first
    }

    static func editableNodes(in nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        nodesOutsideDrawers(in: nodes).filter {
            ["paragraph", "list", "quote_block"].contains($0.type) && !isTimestampOnly($0)
        }
    }

    private static let timestampOnlyExpression = try? NSRegularExpression(
        pattern: #"^<\d{4}-\d{2}-\d{2}[^>\r\n]*>(?:--<\d{4}-\d{2}-\d{2}[^>\r\n]*>)?$"#
    )

    private static func isTimestampOnly(_ node: ParsedOrgNode) -> Bool {
        guard node.type == "paragraph" else { return false }
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return timestampOnlyExpression?
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
