import SwiftUI

struct SearchResultLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var query = ""
    var detail: String?
    var state: OrgWorkflowState?

    var body: some View {
        HStack(alignment: .top, spacing: OrgendaSpacing.contentInset) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(OrgendaTheme.tintedBackground(tint), in: OrgendaCorners.standard)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OrgendaSpacing.compactInset) {
                HStack(alignment: .firstTextBaseline, spacing: OrgendaSpacing.rowInset) {
                    if let state { OrgWorkflowIcon(state) }
                    Text(highlightedTitle)
                        .foregroundStyle(state.map(OrgendaTheme.workflowColor) ?? .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(highlighted(subtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty,
              let range = result.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return result
        }
        result[range].inlinePresentationIntent = .stronglyEmphasized
        result[range].foregroundColor = OrgendaTheme.accentText
        return result
    }

    private var highlightedTitle: AttributedString {
        var value = highlighted(title)
        if let state { value.foregroundColor = OrgendaTheme.workflowColor(state) }
        return value
    }
}
