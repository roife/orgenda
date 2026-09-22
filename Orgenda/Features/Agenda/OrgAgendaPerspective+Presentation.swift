import Foundation

extension OrgAgendaPerspective {
    static let browsingViews: [Self] = [.dashboard, .overdue, .todos]
    static let taskViews: [Self] = [.urgent, .next, .waiting, .projects, .someday]

    var title: String {
        switch self {
        case .agenda: String(localized: "Calendar")
        case .todos: String(localized: "Unscheduled")
        case .urgent: String(localized: "Urgent")
        case .someday: String(localized: "Someday")
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
        case .urgent: OrgWorkflowState.urgent.symbol
        case .next: OrgWorkflowState.next.symbol
        case .waiting: OrgWorkflowState.wait.symbol
        case .projects: "folder"
        case .someday: OrgWorkflowState.someday.symbol
        }
    }

    var workflowState: OrgWorkflowState? {
        switch self {
        case .urgent: .urgent
        case .next: .next
        case .waiting: .wait
        case .someday: .someday
        default: nil
        }
    }

    var controlID: String {
        switch self {
        case .dashboard: "dashboard"
        case .agenda: "agenda"
        case .overdue: "overdue"
        case .todos: "todos"
        case .urgent: "urgent"
        case .next: "next"
        case .waiting: "waiting"
        case .projects: "projects"
        case .someday: "someday"
        }
    }
}
