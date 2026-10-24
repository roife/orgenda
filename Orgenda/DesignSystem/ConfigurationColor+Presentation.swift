import SwiftUI

extension ConfigurationColor {
    /// `default` means inherit the original style at the usage site, not black,
    /// system teal, or a fixed palette entry.
    func resolved(or fallback: @autoclosure () -> Color) -> Color {
        self == .default ? fallback() : swiftUIColor
    }

    var swiftUIColor: Color {
        OrgendaTheme.configurationColor(self)
    }
}
