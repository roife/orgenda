import SwiftUI

struct OrgPreviewRow: Identifiable {
    let node: ParsedOrgNode
    let parentHeadingIDs: [String]
    let headingLevel: Int?
    let parentHeadingLevel: Int?
    var hasDescendants: Bool

    var id: String { node.id }

    var indentation: CGFloat {
        if let headingLevel {
            return CGFloat(max(headingLevel - 1, 0)) * 12
        }
        guard let parentHeadingLevel else { return 0 }
        return CGFloat(max(parentHeadingLevel - 1, 0)) * 12 + 14
    }

    var spacingBefore: CGFloat {
        switch node.type {
        case "heading": headingLevel == 1 ? 10 : 6
        case "property_drawer", "drawer", "planning": 3
        case "list_item": 0
        default: 3
        }
    }
}

enum OrgPreviewOutline {
    private struct HeadingAncestor {
        let id: String
        let level: Int
    }

    static func rows(from nodes: [ParsedOrgNode]) -> [OrgPreviewRow] {
        var rows: [OrgPreviewRow] = []
        var ancestors: [HeadingAncestor] = []

        for node in presentationOrder(OrgPreviewCustomBlocks.group(nodes)) {
            if node.type == "heading" {
                let level = headingLevel(node)
                while ancestors.last.map({ $0.level >= level }) == true {
                    ancestors.removeLast()
                }
                rows.append(
                    OrgPreviewRow(
                        node: node,
                        parentHeadingIDs: ancestors.map(\.id),
                        headingLevel: level,
                        parentHeadingLevel: ancestors.last?.level,
                        hasDescendants: false
                    )
                )
                ancestors.append(HeadingAncestor(id: node.id, level: level))
                continue
            }

            let displayNodes: [ParsedOrgNode]
            if node.type == "list" {
                displayNodes = node.children
            } else {
                displayNodes = [node]
            }

            rows.append(contentsOf: displayNodes.map {
                OrgPreviewRow(
                    node: $0,
                    parentHeadingIDs: ancestors.map(\.id),
                    headingLevel: nil,
                    parentHeadingLevel: ancestors.last?.level,
                    hasDescendants: false
                )
            })
        }

        let parentIDs = Set(rows.flatMap(\.parentHeadingIDs))
        for index in rows.indices where rows[index].node.type == "heading" {
            rows[index].hasDescendants = parentIDs.contains(rows[index].id)
        }
        return rows
    }

    /// Org places planning lines before property drawers in source. In preview,
    /// keep the compact drawers together directly below the heading and show
    /// the more prominent dates beneath them.
    private static func presentationOrder(_ nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        var ordered: [ParsedOrgNode] = []
        var index = nodes.startIndex

        while index < nodes.endIndex {
            let node = nodes[index]
            ordered.append(node)
            index += 1

            guard node.type == "heading" else { continue }

            let metadataStart = index
            while index < nodes.endIndex, isHeadingMetadata(nodes[index]) {
                index += 1
            }
            let metadata = nodes[metadataStart..<index]
            ordered.append(contentsOf: metadata.filter(isDrawer))
            ordered.append(contentsOf: metadata.filter { $0.type == "planning" })
            ordered.append(contentsOf: metadata.filter { $0.type == "blank_line" })
        }

        return ordered
    }

    private static func isHeadingMetadata(_ node: ParsedOrgNode) -> Bool {
        isDrawer(node) || node.type == "planning" || node.type == "blank_line"
    }

    private static func isDrawer(_ node: ParsedOrgNode) -> Bool {
        node.type == "property_drawer" || node.type == "drawer"
    }

    private static func headingLevel(_ node: ParsedOrgNode) -> Int {
        let marker = node.child(ofType: "heading_marker")?.text ?? node.text
        return max(1, marker.prefix { $0 == "*" }.count)
    }
}

/// Preview-only containers; the parser's nodes and source offsets stay intact
/// so controls inside a special block still edit their exact original ranges.
enum OrgPreviewCustomBlocks {
    private struct Boundary {
        let opens: Bool
        let name: String
        let title: String
    }

    private struct Candidate {
        let nodes: [ParsedOrgNode]
        let boundary: Boundary?
        var text: String { nodes.map(\.text).joined() }
    }

    private static let standardNames: Set<String> = [
        "src", "quote", "example", "export", "comment", "verse", "center"
    ]
    private static let boundaryExpression = try! NSRegularExpression(
        pattern: #"^[ \t]*#\+(begin|end)_([^\s]+)(?:[ \t]+([^\r\n]*))?[ \t]*\r?\n?$"#,
        options: [.caseInsensitive]
    )

    static func group(_ nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        let candidates = boundaryLines(nodes)
        var stack: [(index: Int, name: String)] = []
        var pairs: [Int: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            // An unfinished block must never consume another Org heading.
            if candidate.nodes.contains(where: { $0.type == "heading" }) {
                stack.removeAll()
            }
            guard let boundary = candidate.boundary else { continue }
            if boundary.opens {
                stack.append((index, boundary.name))
            } else if let opening = stack.last, opening.name == boundary.name {
                pairs[opening.index] = index
                stack.removeLast()
            } else {
                stack.removeAll()
            }
        }

        func containers(in range: Range<Int>) -> [ParsedOrgNode] {
            var result: [ParsedOrgNode] = []
            var index = range.lowerBound
            while index < range.upperBound {
                let candidate = candidates[index]
                if let end = pairs[index], end < range.upperBound,
                   let first = candidate.nodes.first,
                   let last = candidates[end].nodes.last {
                    result.append(ParsedOrgNode(
                        id: "custom:\(first.id):\(last.endByte)",
                        type: "custom_block",
                        text: candidates[index...end].map(\.text).joined(),
                        startByte: first.startByte,
                        endByte: last.endByte,
                        children: containers(in: (index + 1)..<end)
                    ))
                    index = end + 1
                } else {
                    result.append(contentsOf: candidate.nodes)
                    index += 1
                }
            }
            return result
        }
        return containers(in: candidates.indices)
    }

    static func title(for node: ParsedOrgNode) -> String {
        let firstLine = node.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return boundary(in: String(firstLine))?.title ?? ""
    }

    private static func boundary(in text: String) -> Boundary? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = boundaryExpression.firstMatch(in: text, range: range),
              match.range == range else { return nil }
        let source = text as NSString
        let name = source.substring(with: match.range(at: 2))
        guard !standardNames.contains(name.lowercased()) else { return nil }
        let opens = source.substring(with: match.range(at: 1)).lowercased() == "begin"
        let arguments = match.range(at: 3).location == NSNotFound ? ""
            : source.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        guard opens || arguments.isEmpty else { return nil }
        return Boundary(opens: opens, name: name.lowercased(),
                        title: name + (arguments.isEmpty ? "" : " " + arguments))
    }

    private static func boundaryLines(_ nodes: [ParsedOrgNode]) -> [Candidate] {
        var result: [Candidate] = []
        var index = nodes.startIndex
        let lineTypes: Set<String> = ["paragraph", "keyword", "ERROR"]
        while index < nodes.endIndex {
            let first = nodes[index]
            guard lineTypes.contains(first.type) else {
                result.append(Candidate(nodes: [first], boundary: nil))
                index += 1
                continue
            }
            var pieces = [first]
            var cursor = index + 1
            // The grammar can split indentation or a standard-name prefix
            // (e.g. begin_src_extra) into an ERROR plus a paragraph on one line.
            while let last = pieces.last, !last.text.contains("\n"),
                  cursor < nodes.endIndex, last.endByte == nodes[cursor].startByte,
                  lineTypes.contains(nodes[cursor].type) {
                pieces.append(nodes[cursor])
                cursor += 1
            }
            let text = pieces.map(\.text).joined()
            if let boundary = boundary(in: text) {
                result.append(Candidate(nodes: pieces, boundary: boundary))
            } else {
                result.append(contentsOf: pieces.map { Candidate(nodes: [$0], boundary: nil) })
            }
            index = cursor
        }
        return result
    }
}

extension ParsedOrgNode {
    func child(ofType type: String) -> ParsedOrgNode? {
        children.first { $0.type == type }
    }

    var todoNode: ParsedOrgNode? {
        child(ofType: "todo_keyword")
    }

    var checkboxNode: ParsedOrgNode? {
        child(ofType: "checkbox")
    }

    var descendantsByID: [String: ParsedOrgNode] {
        var result = [id: self]
        for child in children {
            result.merge(child.descendantsByID) { current, _ in current }
        }
        return result
    }
}
