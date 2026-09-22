import SwiftUI

/// Wraps readable tags without truncating them to make a horizontal row fit.
struct OrgendaTagList: View {
    let tags: [String]

    var body: some View {
        OrgendaFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(tags.enumerated(), id: \.offset) { _, tag in
                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OrgendaTheme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OrgendaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
