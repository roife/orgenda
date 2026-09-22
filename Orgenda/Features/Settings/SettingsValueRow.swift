import SwiftUI

/// Keep long paths, localized values, and accessibility text readable without
/// squeezing either side of a settings row.
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).fixedSize()
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                Text(value)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
