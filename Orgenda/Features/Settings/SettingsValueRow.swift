import SwiftUI

/// A system information row that allows long values to wrap.
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}
