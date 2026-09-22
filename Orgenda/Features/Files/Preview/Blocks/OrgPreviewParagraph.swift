import SwiftUI

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
