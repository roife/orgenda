import Foundation

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case tasks = "Tasks"
    case journal = "Journal"
    case calendar = "Calendar"
    case files = "Files"
    case settings = "Settings"

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .tasks: String(localized: "Tasks")
        case .journal: String(localized: "Journal")
        case .calendar: String(localized: "Calendar")
        case .files: String(localized: "Files")
        case .settings: String(localized: "Settings")
        }
    }

    var id: String { rawValue }
}

enum SearchResult: Identifiable, Hashable, Sendable {
    case item(OrgItem)
    case journal(JournalEntry)
    case document(WorkspaceDocument)
    case setting(SettingsDestination)

    var id: String {
        switch self {
        case .item(let item): "item-\(item.id)"
        case .journal(let entry): "journal-\(entry.id)"
        case .document(let document): "document-\(document.path)"
        case .setting(let destination): "setting-\(destination.rawValue)"
        }
    }
}
