import Foundation

enum OrgAgendaPerspective: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case agenda = "Agenda"
    case overdue = "Overdue"
    case todos = "TODOs"
    case urgent = "Urgent actions"
    case next = "Next actions"
    case waiting = "Waiting"
    case projects = "Projects"
    case someday = "Someday"
    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .dashboard: String(localized: "Dashboard")
        case .agenda: String(localized: "Agenda")
        case .overdue: String(localized: "Overdue")
        case .todos: String(localized: "Tasks")
        case .urgent: String(localized: "Urgent actions")
        case .next: String(localized: "Next actions")
        case .waiting: String(localized: "Waiting")
        case .projects: String(localized: "Projects")
        case .someday: String(localized: "Someday")
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
