import Foundation

extension OrgAgendaPerspective {
    var title: String {
        switch self {
        case .agenda: String(localized: "Calendar")
        case .todos: String(localized: "Unscheduled")
        default: localizedName
        }
    }

    var menuTitle: String {
        switch self {
        case .agenda: String(localized: "Calendar")
        case .todos: String(localized: "Unscheduled")
        default: localizedName
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .agenda: "calendar"
        case .overdue: "exclamationmark.circle"
        case .todos: "checklist"
        case .projects: "folder"
        case .status(let state): state.symbol
        }
    }

    var controlID: String { id }
}
