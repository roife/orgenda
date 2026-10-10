import SwiftUI

struct SettingsRow: View {
    @ScaledMetric(relativeTo: .body) private var assetIconSize = 18.0
    let icon: String
    let color: Color
    let title: String
    var subtitle: String = ""
    var subtitleIcon: String? = nil
    var iconAsset: String? = nil

    var body: some View {
        Label {
            text
        } icon: {
            rowIcon
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }

    private var rowIcon: some View {
        Group {
            if let iconAsset {
                Image(iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: assetIconSize, height: assetIconSize)
            } else {
                Image(systemName: icon)
            }
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            if !subtitle.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let subtitleIcon {
                        Image(systemName: subtitleIcon)
                            .accessibilityHidden(true)
                    }
                    Text(subtitle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
