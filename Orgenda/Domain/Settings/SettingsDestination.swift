import Foundation

/// Settings navigation and search share this inventory so results always open
/// the page they describe.
enum SettingsDestination: String, CaseIterable, Hashable, Sendable {
    case workspace
    case appearance
    case reminders

    var title: String {
        switch self {
        case .workspace: String(localized: "Workspace & Sync")
        case .appearance: String(localized: "Appearance")
        case .reminders: String(localized: "Reminders")
        }
    }

    var subtitle: String {
        switch self {
        case .workspace: String(localized: "Workspace folder, saving, and sync")
        case .appearance: String(localized: "System, light, or dark theme")
        case .reminders: String(localized: "Agenda reminders and notification permission")
        }
    }
}
