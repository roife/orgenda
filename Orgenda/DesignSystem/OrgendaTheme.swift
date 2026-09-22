import SwiftUI

enum OrgendaTheme {
    static let syntaxTeal = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.78, blue: 0.83, alpha: 1)
            : UIColor(red: 0.12, green: 0.40, blue: 0.46, alpha: 1)
    }
    static let accent = Color(red: 0.18, green: 0.43, blue: 0.53)
    // Text uses a brighter tint in dark mode; filled controls retain the accent
    // above so their white labels keep enough contrast.
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.76, blue: 0.84, alpha: 1)
            : UIColor(red: 0.18, green: 0.43, blue: 0.53, alpha: 1)
    })
    static let weekend = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.75, green: 0.62, blue: 0.90, alpha: 1)
            : UIColor(red: 0.43, green: 0.29, blue: 0.57, alpha: 1)
    })
    static let accentSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.23, blue: 0.27, alpha: 1)
            : UIColor(red: 0.91, green: 0.96, blue: 0.97, alpha: 1)
    })
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    // Opaque secondary text keeps small Preview labels readable on both surfaces.
    static let previewMetadataColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1)
            : UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1)
    }
    static let previewMetadata = Color(uiColor: previewMetadataColor)
    static let overdue = Color(red: 0.76, green: 0.09, blue: 0.36)
    static let event = Color(red: 0.19, green: 0.49, blue: 0.80)
    static let habit = Color(red: 0.00, green: 0.54, blue: 0.29)

    static func kindColor(_ kind: OrgItemKind) -> Color {
        switch kind {
        case .event: event
        case .task: accent
        case .project: Color(red: 0.88, green: 0.49, blue: 0.16)
        case .habit: habit
        case .note: secondaryInk
        }
    }

    static func workflowColor(_ state: OrgWorkflowState) -> Color {
        switch state {
        case .todo: previewMetadata
        case .next: adaptiveForeground(
            UIColor(red: 0.10, green: 0.36, blue: 0.78, alpha: 1),
            UIColor(red: 0.38, green: 0.67, blue: 1.00, alpha: 1)
        )
        case .urgent: adaptiveForeground(
            UIColor(red: 0.78, green: 0.16, blue: 0.15, alpha: 1),
            UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1)
        )
        case .done: adaptiveForeground(
            UIColor(red: 0.52, green: 0.53, blue: 0.56, alpha: 1),
            UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1)
        )
        case .wait: adaptiveForeground(
            UIColor(red: 0.68, green: 0.35, blue: 0.04, alpha: 1),
            UIColor(red: 1.00, green: 0.68, blue: 0.30, alpha: 1)
        )
        case .someday: weekend
        case .canceled: adaptiveForeground(
            UIColor(red: 0.69, green: 0.20, blue: 0.43, alpha: 1),
            UIColor(red: 0.95, green: 0.53, blue: 0.72, alpha: 1)
        )
        }
    }

    private static func adaptiveForeground(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
