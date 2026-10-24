import SwiftUI

struct OrgPreviewQuote: View {
    let node: ParsedOrgNode

    var body: some View {
        OrgPreviewMathFlow(
            nodes: OrgPreviewMarkup.contents(of: node),
            textStyle: .subheadline
        )
            .font(.subheadline.italic())
            .foregroundStyle(.secondary)
            .padding(.leading, OrgendaSpacing.contentInset)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(OrgendaTheme.accent)
                    .frame(width: 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier("org.preview.quote.\(node.startByte)")
    }

}
