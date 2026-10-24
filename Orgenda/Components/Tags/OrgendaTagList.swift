import SwiftUI

/// Wraps readable tags without truncating them to make a horizontal row fit.
struct OrgendaTagList: View {
    let tags: [String]

    var body: some View {
        OrgendaFlowLayout(horizontalSpacing: OrgendaSpacing.inlineGap, verticalSpacing: OrgendaSpacing.inlineGap) {
            ForEach(tags.enumerated(), id: \.offset) { _, tag in
                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OrgendaTheme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, OrgendaSpacing.rowInset)
                    .padding(.vertical, OrgendaSpacing.compactInset)
                    .background(OrgendaTheme.accentSoft, in: OrgendaCorners.standard)
            }
        }
    }
}
