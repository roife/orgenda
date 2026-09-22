import SwiftUI

struct OrgPreviewDrawer: View {
    let node: ParsedOrgNode
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            OrgPreviewReadOnlyContent(nodes: contents)
                .padding(.top, 2)
        } label: {
            Text(name)
                .font(.caption2)
                .foregroundStyle(OrgendaTheme.previewMetadata)
                .frame(minHeight: 24, alignment: .leading)
        }
        .controlSize(.mini)
        .tint(OrgendaTheme.accentText)
        .padding(.horizontal, 6)
        .background(OrgendaTheme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("org.preview.drawer.\(node.startByte)")
    }

    private var name: String {
        (node.children.first?.text ?? String(localized: "Drawer"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }

    private var contents: [ParsedOrgNode] { OrgPreviewMarkup.contents(of: node) }
}

struct OrgPreviewClock: View {
    @Environment(\.locale) private var locale
    let node: ParsedOrgNode

    var body: some View {
        let value = OrgPreviewClockValue(node)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "clock")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.minutes == nil ? "Running clock" : "Clock")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if let interval = value.interval(locale: locale) {
                    Text(interval)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(value.duration)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(OrgendaTheme.accentText)
                .fixedSize()
        }
        .font(.caption2)
        .padding(.vertical, 1)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("org.preview.clock.\(node.startByte)")
    }
}

/// Drawer contents are readable without turning historical log entries into
/// editable planning controls. Dynamic blocks share the same block layouts.
struct OrgPreviewReadOnlyContent: View {
    @Environment(\.locale) private var locale
    let nodes: [ParsedOrgNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(nodes) { node in
                switch node.type {
                case "clock": OrgPreviewClock(node: node)
                case "property":
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.child(ofType: "property_name")?.text ?? "")
                            .font(.caption.monospaced().weight(.semibold)).foregroundStyle(.secondary)
                        if let value = node.child(ofType: "property_value") {
                            OrgPreviewRichText(
                                fragments: drawerFragments(value, trimSpaces: true),
                                textStyle: .subheadline
                            )
                            .font(.subheadline)
                        }
                    }
                    .textSelection(.enabled)
                case "table": OrgPreviewTable(node: node)
                case "source_block", "example_block", "export_block", "fixed_width":
                    OrgPreviewSourceBlock(node: node)
                case "quote_block": OrgPreviewQuote(node: node)
                case "verse_block", "center_block", "dynamic_block": OrgPreviewTextBlock(node: node)
                case "comment", "comment_block": OrgPreviewComment(node: node)
                case "horizontal_rule": Divider()
                case "list":
                    ForEach(node.children) { item in
                        if let entry = workflowEntry(item) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if let previous = entry.previous {
                                    OrgWorkflowIcon(keyword: previous)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                }
                                OrgWorkflowIcon(keyword: entry.current)
                                OrgPreviewRichText(
                                    fragments: entry.details,
                                    textStyle: .subheadline
                                )
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.checkboxNode?.text.trimmingCharacters(in: .whitespaces) ?? OrgPreviewMarkup.listMarker(item))
                                    .foregroundStyle(.secondary)
                                if let content = item.children.first(where: { $0.type == "list_item_content" }) {
                                    OrgPreviewRichText(
                                        fragments: drawerFragments(content, trimSpaces: true),
                                        textStyle: .subheadline
                                    )
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                case "blank_line": EmptyView()
                default:
                    OrgPreviewRichText(
                        fragments: drawerFragments(node),
                        textStyle: .subheadline
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func drawerFragments(
        _ node: ParsedOrgNode,
        trimSpaces: Bool = false
    ) -> [OrgPreviewInlineFragment] {
        OrgPreviewMarkup.readableDrawerFragments(
            node,
            trimSpaces: trimSpaces,
            locale: locale
        )
    }

    private func workflowEntry(_ item: ParsedOrgNode) -> OrgWorkflowLogPresentation? {
        guard let content = item.children.first(where: { $0.type == "list_item_content" }),
              let entry = OrgWorkflowLogEntry(String(OrgPreviewMarkup.attributed(content, trimSpaces: true).characters))
        else { return nil }

        return OrgWorkflowLogPresentation(
            current: entry.current,
            previous: entry.previous,
            details: drawerFragments(content, trimSpaces: true).droppingPrefix(entry.sourcePrefix)
        )
    }
}

/// Recognizes Org's state log syntax without changing the underlying entry.
struct OrgWorkflowLogEntry {
    let current: String
    let previous: String?
    let details: String
    let sourcePrefix: String

    private static let expression = try? NSRegularExpression(
        pattern: #"^State\s+"([^"]+)"(?:\s+from\s+"([^"]*)")?\s*(.*)$"#,
        options: .dotMatchesLineSeparators
    )

    init?(_ source: String) {
        guard let expression = Self.expression,
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let currentRange = Range(match.range(at: 1), in: source),
              let detailsRange = Range(match.range(at: 3), in: source) else { return nil }
        current = String(source[currentRange])
        previous = Range(match.range(at: 2), in: source).flatMap {
            source[$0].isEmpty ? nil : String(source[$0])
        }
        details = String(source[detailsRange])
        sourcePrefix = String(source[..<detailsRange.lowerBound])
    }
}

private struct OrgWorkflowLogPresentation {
    let current: String
    let previous: String?
    let details: [OrgPreviewInlineFragment]
}

private extension Array where Element == OrgPreviewInlineFragment {
    func droppingPrefix(_ prefix: String) -> [OrgPreviewInlineFragment] {
        var result = self
        var remaining = prefix.count
        while remaining > 0, !result.isEmpty {
            guard case .text(var value) = result[0] else { break }
            let count = Swift.min(remaining, value.characters.count)
            let end = value.characters.index(value.startIndex, offsetBy: count)
            value.removeSubrange(value.startIndex..<end)
            remaining -= count
            if value.characters.isEmpty { result.removeFirst() }
            else { result[0] = .text(value) }
        }
        return result
    }
}

struct OrgPreviewComment: View {
    let node: ParsedOrgNode

    var body: some View {
        DisclosureGroup {
            Text(node.type == "comment_block" ? OrgPreviewMarkup.literalText(node) : node.child(ofType: "comment_text")?.text ?? "")
                .font(.subheadline.italic()).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Comment", systemImage: "text.bubble").font(.subheadline).frame(minHeight: 44)
        }
        .tint(.secondary)
    }
}

struct OrgPreviewTextBlock: View {
    let node: ParsedOrgNode

    @ViewBuilder
    var body: some View {
        if node.type == "dynamic_block" {
            VStack(alignment: .leading, spacing: 4) {
                OrgPreviewReadOnlyContent(nodes: OrgPreviewMarkup.contents(of: node))
            }
        } else {
            OrgPreviewMathFlow(
                fragments: OrgPreviewContainerMath.blockFragments(node),
                centered: node.type == "center_block"
            )
                .font(.body)
                .multilineTextAlignment(node.type == "center_block" ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: node.type == "center_block" ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
