import SwiftUI

struct OrgPreviewMetadataSurface: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OrgendaSpacing.rowInset)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(fill, in: OrgendaCorners.standard)
            .contentShape(Rectangle())
    }
}

struct OrgPreviewKeyword: View {
    let node: ParsedOrgNode

    @ViewBuilder
    var body: some View {
        if node.text.lowercased().hasPrefix("#+title:") {
            OrgPreviewSearchText(node.text.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.title2.bold())
                .padding(.bottom, OrgendaSpacing.compactInset)
                .accessibilityAddTraits(.isHeader)
        } else if node.text.lowercased().hasPrefix("#+caption:"),
                  let value = node.child(ofType: "keyword_value") {
            OrgPreviewRichText(fragments: OrgPreviewMarkup.fragments(value, trimSpaces: true), textStyle: .subheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } else {
            OrgPreviewSearchText(node.text.trimmingCharacters(in: .newlines))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

struct OrgPreviewFallback: View {
    @Environment(\.orgWorkflow) private var workflow
    let source: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: OrgendaSpacing.inlineGap) {
            ForEach(Array(source.components(separatedBy: .newlines).enumerated()), id: \.offset) { line in
                let parts = line.element.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                Group {
                    if parts.count == 3, parts[0].allSatisfy({ $0 == "*" }),
                       let state = workflow.state(String(parts[1])) {
                        HStack(alignment: .firstTextBaseline, spacing: OrgendaSpacing.rowInset) {
                            Text(parts[0]).foregroundStyle(.secondary)
                            OrgWorkflowIcon(state)
                            OrgPreviewSearchText(parts[2]).foregroundStyle(OrgendaTheme.workflowColor(state))
                        }
                    } else {
                        OrgPreviewSearchText(line.element.isEmpty ? " " : line.element)
                    }
                }
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(OrgendaSpacing.documentInsets)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("org.preview.fallback")
    }
}
