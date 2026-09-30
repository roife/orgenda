import Foundation

/// Settings navigation and search share this inventory so results always open
/// the page they describe.
enum SettingsDestination: String, CaseIterable, Hashable, Sendable {
    case workspace
    case appearance
    case reminders
    case workflow
    case capture
    case files
    case emacs
    case configuration

    var title: String {
        switch self {
        case .workspace: String(localized: "Workspace & Sync")
        case .appearance: String(localized: "Appearance")
        case .reminders: String(localized: "Reminders")
        case .workflow: String(localized: "Workflow")
        case .capture: String(localized: "Capture templates")
        case .files: String(localized: "Files & agenda")
        case .emacs: String(localized: "Extract from Emacs")
        case .configuration: String(localized: "Configuration file")
        }
    }

    var subtitle: String {
        switch self {
        case .workspace: String(localized: "Workspace folder, saving, and sync")
        case .appearance: String(localized: "System, light, or dark theme")
        case .reminders: String(localized: "Notifications, permission and reminder timing")
        case .workflow: String(localized: "Task states, icons, colors and history rules")
        case .capture: String(localized: "Capture templates, destinations and quick keys")
        case .files: String(localized: "Agenda sources, inbox, attachments, journal, archive and refile")
        case .emacs: String(localized: "Copy a prompt to extract your Emacs Org settings")
        case .configuration: String(localized: "config.json, saving, presets and reset")
        }
    }
}
