import SwiftUI
import UIKit

/// App colors live here; views use semantic roles rather than choosing a palette.
enum OrgendaTheme {
    // AccentColor is also the system's default tint, so keep one source of truth.
    static let accent = Color("AccentColor")
    // Text uses a brighter tint in dark mode; filled controls retain the accent
    // above so their white labels keep enough contrast.
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.76, blue: 0.84, alpha: 1)
            : UIColor(named: "AccentColor") ?? .systemTeal
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
    static let inkColor = UIColor.label
    static let secondaryInkColor = UIColor.secondaryLabel
    static let onAccent = Color.white
    static let backgroundColor = UIColor.systemBackground
    static let background = Color(uiColor: backgroundColor)
    static let pinnedHeaderBackground = background.opacity(0.96)
    static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let secondaryFillColor = UIColor.secondarySystemFill
    static let secondaryFill = Color(uiColor: secondaryFillColor)
    static let tertiaryFillColor = UIColor.tertiarySystemFill
    static let tertiaryFill = Color(uiColor: tertiaryFillColor)
    static let quaternaryFill = Color(uiColor: .quaternarySystemFill)
    static let separator = Color(uiColor: .separator)
    static let calendarHandle = secondaryInk.opacity(0.35)
    static let timelineConnector = accent.opacity(0.18)
    static let habitPlaceholder = secondaryInk.opacity(0.16)
    static let todayOutline = accent.opacity(0.72)
    static let dropTargetBackground = tintedBackground(accentText)
    static let dropTargetBorder = accentText.opacity(0.55)
    static let previewDrawerBackground = accentSoft.opacity(0.55)

    static let error = Color(uiColor: Palette.red)
    static let success = Color(uiColor: Palette.green)
    static let warning = Color(uiColor: Palette.orange)
    static let info = Color(uiColor: Palette.blue)
    static let neutral = Color(uiColor: Palette.gray)
    static let folder = warning
    static let pinned = warning
    static let searchHighlight = Color.yellow.opacity(0.45)
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
    static let project = Color(red: 0.88, green: 0.49, blue: 0.16)

    /// Badges, result icons and metadata cards share the same tint strength.
    static func tintedBackground(_ tint: Color) -> Color {
        tint.opacity(0.10)
    }

    static func calendarDayColor(isWeekend: Bool, isDimmed: Bool, contrast: ColorSchemeContrast) -> Color {
        let opacity = isDimmed ? (contrast == .increased ? 0.75 : 0.55) : 1
        return (isWeekend ? weekend : ink).opacity(opacity)
    }

    static func priorityColor(_ priority: OrgPriority) -> Color {
        switch priority {
        case .high: error
        case .medium: warning
        case .low: info
        case .none: secondaryInk
        }
    }

    static func configurationColor(_ color: ConfigurationColor) -> Color {
        let base: UIColor
        switch color {
        case .default: return ink
        case .gray: base = Palette.gray
        case .red: base = Palette.red
        case .orange: base = Palette.orange
        case .amber: base = Palette.amber
        case .green: base = Palette.green
        case .cyan: base = Palette.cyan
        case .blue: base = Palette.blue
        case .purple: base = Palette.purple
        case .pink: base = Palette.pink
        }
        return Color(uiColor: base)
    }

    static func kindColor(_ kind: OrgItemKind) -> Color {
        switch kind {
        case .event: event
        case .task: accent
        case .project: project
        case .habit: habit
        case .note: secondaryInk
        }
    }

    static func workflowColor(_ state: OrgWorkflowState) -> Color {
        state.color.resolved(or: defaultWorkflowColor(state))
    }

    static func defaultWorkflowColor(_ state: OrgWorkflowState) -> Color {
        switch state.rawValue {
        case "TODO": return previewMetadata
        case "NEXT": return adaptiveForeground(
            UIColor(red: 0.10, green: 0.36, blue: 0.78, alpha: 1),
            UIColor(red: 0.38, green: 0.67, blue: 1.00, alpha: 1))
        case "URGENT": return adaptiveForeground(
            UIColor(red: 0.78, green: 0.16, blue: 0.15, alpha: 1),
            UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1))
        case "DONE": return completedWorkflowColor
        case "WAIT": return adaptiveForeground(
            UIColor(red: 0.68, green: 0.35, blue: 0.04, alpha: 1),
            UIColor(red: 1.00, green: 0.68, blue: 0.30, alpha: 1))
        case "SOMEDAY": return weekend
        case "CANCELED": return adaptiveForeground(
            UIColor(red: 0.69, green: 0.20, blue: 0.43, alpha: 1),
            UIColor(red: 0.95, green: 0.53, blue: 0.72, alpha: 1))
        default: return state.isTerminal ? completedWorkflowColor : previewMetadata
        }
    }

    private static let completedWorkflowColor = adaptiveForeground(
        UIColor(red: 0.52, green: 0.53, blue: 0.56, alpha: 1),
        UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1))

    private static func adaptiveForeground(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: adaptiveColor(light, dark))
    }

    private static func adaptiveColor(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// UIKit colors keep dynamic appearance when used by TextKit or SwiftUI.
    enum Syntax {
        static let heading = Palette.indigo
        static let tag = Palette.purple
        static let timestamp = adaptiveColor(
            UIColor(red: 0.12, green: 0.40, blue: 0.46, alpha: 1),
            UIColor(red: 0.48, green: 0.78, blue: 0.83, alpha: 1))
        static let property = Palette.indigo
        static let keyword = Palette.purple
        static let progress = Palette.blue
        static let literal = Palette.brown
        static let code = Palette.pink
        static let footnote = Palette.purple
        static let link = UIColor.link

        static func codeTheme(for colorScheme: ColorScheme) -> String {
            colorScheme == .dark ? "github-dark" : "github"
        }

        static func tagBackground(contrast: ColorSchemeContrast) -> UIColor {
            tag.withAlphaComponent(contrast == .increased ? 0.22 : 0.12)
        }

        static func drawerBackground(contrast: ColorSchemeContrast) -> UIColor {
            property.withAlphaComponent(contrast == .increased ? 0.16 : 0.06)
        }

        static func progressBackground(contrast: ColorSchemeContrast) -> UIColor {
            progress.withAlphaComponent(contrast == .increased ? 0.22 : 0.12)
        }
    }

    private enum Palette {
        static let gray = UIColor.systemGray
        static let red = UIColor.systemRed
        static let orange = UIColor.systemOrange
        static let amber = adaptiveColor(
            UIColor(red: 0.55, green: 0.36, blue: 0.02, alpha: 1),
            UIColor(red: 0.95, green: 0.73, blue: 0.30, alpha: 1))
        static let green = UIColor.systemGreen
        static let cyan = UIColor.systemTeal
        static let blue = UIColor.systemBlue
        static let indigo = UIColor.systemIndigo
        static let purple = UIColor.systemPurple
        static let pink = UIColor.systemPink
        static let brown = UIColor.systemBrown
    }
}
