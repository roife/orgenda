import SwiftUI

extension ConfigurationColor {
    /// `default` means inherit the original style at the usage site, not black,
    /// system teal, or a fixed palette entry.
    func resolved(or fallback: @autoclosure () -> Color) -> Color {
        self == .default ? fallback() : swiftUIColor
    }

    var swiftUIColor: Color {
        let base: UIColor
        switch self {
        case .default: return .primary
        case .gray: base = .systemGray
        case .red: base = .systemRed
        case .orange: base = .systemOrange
        case .amber:
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.95, green: 0.73, blue: 0.30, alpha: 1)
                    : UIColor(red: 0.55, green: 0.36, blue: 0.02, alpha: 1)
            })
        case .green: base = .systemGreen
        case .cyan: base = .systemTeal
        case .blue: base = .systemBlue
        case .purple: base = .systemPurple
        case .pink: base = .systemPink
        }
        return Color(uiColor: base)
    }
}
