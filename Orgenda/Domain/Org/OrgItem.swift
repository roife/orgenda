import Foundation

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
