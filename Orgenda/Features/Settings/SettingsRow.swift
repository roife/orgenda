import SwiftUI

struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize = 18.0
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var isSelected: Bool? = nil

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        iconTile
                        Spacer(minLength: 0)
                        selectionIndicator
                    }
                    text
                }
            } else {
                HStack(spacing: 14) {
                    iconTile
                    text
                    selectionIndicator
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var iconTile: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: iconSize + 18, height: iconSize + 18)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
