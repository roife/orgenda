import SwiftUI

struct SettingsRow: View {
    @ScaledMetric(relativeTo: .body) private var iconSize = 18.0
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var isSelected: Bool? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconTile
            text
            selectionIndicator
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var iconTile: some View {
        Image(systemName: icon)
            .font(.system(size: min(iconSize, 24), weight: .medium))
            .foregroundStyle(color)
            .frame(width: min(iconSize, 24) + 16, height: min(iconSize, 24) + 16)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var selectionIndicator: some View {
        if let isSelected {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(OrgendaTheme.accentText)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}
