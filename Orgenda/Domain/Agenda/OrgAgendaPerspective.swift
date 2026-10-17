import Foundation

enum OrgAgendaPerspective: Hashable, Identifiable {
    case dashboard
    case agenda
    case overdue
    case todos
    case status(OrgWorkflowState)

    var id: String {
        switch self {
        case .dashboard: "dashboard"
        case .agenda: "agenda"
        case .overdue: "overdue"
        case .todos: "todos"
        case .status(let state): "status.\(state.rawValue)"
        }
    }

    // Selection survives changes to a state's label, icon, or logging rules.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var localizedName: String {
        switch self {
        case .dashboard: String(localized: "Dashboard")
        case .agenda: String(localized: "Agenda")
        case .overdue: String(localized: "Overdue")
        case .todos: String(localized: "Tasks")
        case .status(let state): state.title
        }
    }
}

struct OrgAgendaGroup: Identifiable {
    var id: String { title }
    let title: String
    let items: [OrgItem]
    var isDateGroup = false
    var state: OrgWorkflowState? = nil
}
