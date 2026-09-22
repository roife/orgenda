import SwiftUI

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
