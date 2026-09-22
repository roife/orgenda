import SwiftUI

struct OrgPreviewQuote: View {
    let node: ParsedOrgNode

    var body: some View {
        OrgPreviewMathFlow(
            fragments: OrgPreviewContainerMath.blockFragments(node),
            textStyle: .subheadline
        )
            .font(.subheadline.italic())
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
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
