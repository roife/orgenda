import SwiftUI

/// The grammar emits one paragraph node per source line. Group prose only
/// for presentation, retaining the original nodes and their editable ranges.
enum OrgPreviewParagraphs {
    static func group(_ nodes: [ParsedOrgNode]) -> [ParsedOrgNode] {
        var result: [ParsedOrgNode] = []
        var lines: [ParsedOrgNode] = []

        func appendParagraph() {
            guard let first = lines.first, let last = lines.last else { return }
            result.append(ParsedOrgNode(
                id: "paragraph:\(first.id):\(last.endByte)",
                type: "paragraph_group",
                text: lines.map(\.text).joined(),
                startByte: first.startByte,
                endByte: last.endByte,
                children: lines
            ))
            lines.removeAll(keepingCapacity: true)
        }

        for node in nodes {
            guard node.type == "paragraph" || node.type == "quote_line" else {
                appendParagraph()
                result.append(node)
                continue
            }
            if node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendParagraph()
                result.append(ParsedOrgNode(
                    id: node.id, type: "blank_line", text: node.text,
                    startByte: node.startByte, endByte: node.endByte, children: []
                ))
            } else {
                if let last = lines.last, last.endByte != node.startByte {
                    appendParagraph()
                }
                lines.append(node)
            }
        }
        appendParagraph()
        return result
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
            let fragments = linkedFragments
            Group {
                if fragments.count == 1, case .math(let expression) = fragments[0], expression.mode == .display {
                    OrgPreviewMathBlock(expression: expression)
                } else {
                    OrgPreviewRichText(fragments: fragments)
                }
            }
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if OrgPreviewMarkup.externalURL(url.absoluteString) != nil { return .systemAction }
                    guard let timestamp = timestamps.first(where: { URL(string: "orgenda-timestamp://edit/\($0.startByte)") == url }),
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

    private var linkedFragments: [OrgPreviewInlineFragment] {
        let timestampIDs = Set(timestamps.map(\.id))
        return OrgPreviewMarkup.fragments(node) { timestamp in
            guard timestampIDs.contains(timestamp.id) else { return nil }
            guard let draft = draft(for: timestamp) else { return AttributedString(timestamp.text) }
            let presentation = OrgPreviewDateText(draft: draft, locale: locale)
            var date = AttributedString(([presentation.date] + presentation.details).joined(separator: " · "))
            date.link = URL(string: "orgenda-timestamp://edit/\(timestamp.startByte)")
            return date
        }
    }

}
