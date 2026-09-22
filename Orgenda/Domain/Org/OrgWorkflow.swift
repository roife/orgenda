import Foundation

enum OrgItemKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case event
    case task
    case project
    case habit
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .event: String(localized: "Event")
        case .task: String(localized: "Task")
        case .project: String(localized: "Project")
        case .habit: String(localized: "Habit")
        case .note: String(localized: "Note")
        }
    }

    var systemImage: String {
        switch self {
        case .event: "calendar"
        case .task: "checkmark.circle"
        case .project: "square.stack.3d.up"
        case .habit: "repeat.circle"
        case .note: "note.text"
        }
    }
}

enum OrgWorkflowState: String, CaseIterable, Codable, Identifiable, Sendable {
    case todo = "TODO"
    case next = "NEXT"
    case wait = "WAIT"
    case someday = "SOMEDAY"
    case urgent = "URGENT"
    case done = "DONE"
    case canceled = "CANCELED"

    /// Display names are localized; raw values remain Org source tokens.
    var title: String {
        switch self {
        case .todo: String(localized: "TODO")
        case .next: String(localized: "NEXT")
        case .wait: String(localized: "WAIT")
        case .someday: String(localized: "SOMEDAY")
        case .urgent: String(localized: "URGENT")
        case .done: String(localized: "DONE")
        case .canceled: String(localized: "CANCELED")
        }
    }

    var id: String { rawValue }
    var isTerminal: Bool { self == .done || self == .canceled }
}

enum OrgPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case none = ""
    case high = "A"
    case medium = "B"
    case low = "C"

    var id: String { rawValue }
    var displayName: String { self == .none ? String(localized: "None") : rawValue }
}
