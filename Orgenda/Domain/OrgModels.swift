import Foundation
import SwiftUI

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

struct SourceLocation: Hashable, Codable, Sendable {
    var file: String
    var startByte: Int
    var endByte: Int
    var startLine: Int
}

struct OrgItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var state: OrgWorkflowState
    var kind: OrgItemKind
    var priority: OrgPriority
    var tags: [String]
    var scheduled: Date?
    var deadline: Date?
    var closed: Date? = nil
    /// A plain active Org timestamp, distinct from SCHEDULED and DEADLINE.
    var eventDate: Date? = nil
    var hasTime: Bool
    var durationMinutes: Int
    var recurrence: String?
    var body: String
    var source: SourceLocation
    var habitHistory: [Date]
    var properties: [String: String] = [:]
    var hasWorkflowState = true

    var agendaDate: Date? { scheduled ?? deadline ?? eventDate }
    var appointmentWarningMinutes: Int? {
        guard let value = properties["APPT_WARNTIME"], let minutes = Int(value), minutes >= 0 else {
            return nil
        }
        return minutes
    }
    var isOpen: Bool { !state.isTerminal }
    var isRepeatingEvent: Bool {
        kind == .event && recurrence.flatMap(OrgRepeater.init) != nil
    }
    var canComplete: Bool { hasWorkflowState || isRepeatingEvent }
    var isOverdue: Bool {
        guard hasWorkflowState, isOpen, let agendaDate else { return false }
        return agendaDate.startOfDay < Date().startOfDay
    }

    var orgHeading: String {
        let priorityText = priority == .none ? "" : " [#\(priority.rawValue)]"
        let tagText = tags.isEmpty ? "" : " :\(tags.joined(separator: ":")):"
        return "* \(state.rawValue)\(priorityText) \(title)\(tagText)"
    }
}

struct JournalEntry: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var date: Date
    var title: String
    var body: String
    var source: SourceLocation
}

struct WorkspaceDocument: Identifiable, Hashable, Codable, Sendable {
    var id: String { path }
    var path: String
    var title: String
    var contents: String
    var kind: Kind

    enum Kind: String, Codable, Sendable {
        case org
        case markdown
        case folder
    }
}

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

/// Source rebasing and habit history are refreshed by indexing. Conflict checks
/// compare the values a user actually edited, consistently for save and move.
extension OrgItem {
    func hasSameEditableValues(as other: OrgItem) -> Bool {
        var comparable = self
        comparable.source = other.source
        comparable.habitHistory = other.habitHistory
        return comparable == other
    }
}
