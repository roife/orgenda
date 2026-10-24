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
        case "heading": headingLevel == 1 ? OrgendaSpacing.contentInset : OrgendaSpacing.inlineGap
        case "property_drawer", "drawer", "planning": 0
        case "list_item": 0
        case "paragraph_group": OrgendaSpacing.contentInset
        default: OrgendaSpacing.compactInset
        }
    }
}

enum OrgPreviewOutline {
    private struct HeadingAncestor {
        let id: String
        let level: Int
    }

    /// Reuse paragraph grouping per heading section. Ancestor paths
    /// are still recomputed because a heading-level change affects later sections.
    struct Cache {
        private struct Section {
            let source: [ParsedOrgNode]
            let grouped: [ParsedOrgNode]
        }
        private var sections: [String: Section] = [:]

        mutating func rows(from nodes: [ParsedOrgNode]) -> [OrgPreviewRow] {
            var parts: [[ParsedOrgNode]] = []
            for node in nodes {
                if parts.isEmpty || node.type == "heading" { parts.append([]) }
                parts[parts.count - 1].append(node)
            }
            var next: [String: Section] = [:]
            var prepared: [ParsedOrgNode] = []
            for part in parts {
                let first = part[0]
                let grouped: [ParsedOrgNode]
                if let old = sections[first.id] {
                    let delta = first.startByte - old.source[0].startByte
                    let unchanged = old.source.elementsEqual(part) { before, after in
                        before.id == after.id && before.startByte + delta == after.startByte
                            && before.text.utf8.elementsEqual(after.text.utf8)
                    }
                    grouped = unchanged ? old.grouped.map { $0.shifted(by: delta) } : prepare(part)
                } else { grouped = prepare(part) }
                next[first.id] = Section(source: part, grouped: grouped)
                prepared.append(contentsOf: grouped)
            }
            sections = next
            return layout(prepared)
        }
    }

    static func rows(from nodes: [ParsedOrgNode]) -> [OrgPreviewRow] {
        layout(prepare(nodes))
    }

    private static func prepare(_ nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        OrgPreviewParagraphs.group(presentationOrder(nodes))
    }

    private static func layout(_ nodes: [ParsedOrgNode]) -> [OrgPreviewRow] {
        var rows: [OrgPreviewRow] = []
        var ancestors: [HeadingAncestor] = []

        for node in nodes {
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
