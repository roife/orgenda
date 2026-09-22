import Foundation

/// Capture destinations and Org syntax shared with init-agenda.el.
enum OrgCaptureTemplate: String, CaseIterable, Identifiable, Sendable {
    case inboxTask, inboxNote, nextAction, workProject, personalProject
    case reminder, repeatingReminder, someday, calendarEvent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inboxTask: String(localized: "Inbox task")
        case .inboxNote: String(localized: "Inbox note")
        case .nextAction: String(localized: "Next action")
        case .workProject: String(localized: "Work project")
        case .personalProject: String(localized: "Personal project")
        case .reminder: String(localized: "Reminder")
        case .repeatingReminder: String(localized: "Repeating reminder")
        case .someday: String(localized: "Someday")
        case .calendarEvent: String(localized: "Calendar event")
        }
    }

    var destinationPath: String {
        switch self {
        case .inboxTask, .inboxNote, .reminder: "agenda/inbox.org"
        case .nextAction: "agenda/actions.org"
        case .workProject: "agenda/work.org"
        case .personalProject: "agenda/personal.org"
        case .repeatingReminder: "agenda/routines.org"
        case .someday: "agenda/someday.org"
        case .calendarEvent: "agenda/calendar.org"
        }
    }

    var parentHeading: String? {
        switch self {
        case .nextAction: "Actions"
        case .repeatingReminder: "Recurring"
        case .someday: "Someday / Maybe"
        default: nil
        }
    }

    var isProject: Bool { self == .workProject || self == .personalProject }
    var includesAppointmentWarning: Bool {
        [.reminder, .repeatingReminder, .calendarEvent].contains(self)
    }

    static let repeatingIntervals = [".+1d", ".+1w", ".+1m", "++1w", "++1m", "++1y"]

    /// Switching a capture template retains the user's title and notes.
    func applyingDefaults(to item: OrgItem, date: Date = .now, preservingPlanning: Bool = false) -> OrgItem {
        var result = item
        result.source = SourceLocation(file: destinationPath, startByte: 0, endByte: 0, startLine: 1)
        result.state = switch self {
        case .nextAction: .next
        case .someday: .someday
        default: .todo
        }
        result.kind = isProject ? .project : self == .inboxNote ? .note : self == .calendarEvent ? .event : .task
        result.tags.removeAll { $0 == "project" || $0 == "note" || $0 == "event" || $0 == "habit" }
        if isProject { result.tags.append("project") }
        if self == .inboxNote { result.tags.append("note") }
        result.scheduled = self == .reminder || self == .repeatingReminder ? date : nil
        result.eventDate = self == .calendarEvent ? date : nil
        result.deadline = nil
        result.closed = nil
        result.hasTime = includesAppointmentWarning
        result.recurrence = self == .repeatingReminder ? ".+1d" : nil
        if includesAppointmentWarning {
            result.properties["APPT_WARNTIME"] = "15"
        } else {
            result.properties.removeValue(forKey: "APPT_WARNTIME")
        }
        if preservingPlanning {
            // A capture destination must not silently remove an explicit date.
            // Events use an active timestamp; other templates use SCHEDULED.
            if self == .calendarEvent {
                result.eventDate = item.eventDate ?? item.scheduled ?? result.eventDate
            } else {
                result.scheduled = item.scheduled ?? item.eventDate ?? result.scheduled
            }
            result.deadline = item.deadline
            result.recurrence = item.recurrence ?? result.recurrence
            if item.agendaDate != nil { result.hasTime = item.hasTime }
            if includesAppointmentWarning, let warning = item.properties["APPT_WARNTIME"] {
                result.properties["APPT_WARNTIME"] = warning
            }
        }
        return result
    }

    /// The store inserts this entry at the root or below `parentHeading`.
    func source(for item: OrgItem, createdAt: Date = .now, firstAction: String = "") -> String {
        let level = parentHeading == nil ? 1 : 2
        let title = Self.singleLine(item.title)
        let priority = item.priority == .none ? "" : "[#\(item.priority.rawValue)] "
        var tags = item.tags
        let requiredTag: String? = isProject ? "project" : self == .inboxNote ? "note" : nil
        if let requiredTag, !tags.contains(requiredTag) { tags.append(requiredTag) }
        let tagsText = tags.isEmpty ? "" : " :\(tags.joined(separator: ":")):"
        let state = self == .inboxNote || self == .calendarEvent ? "" : "\(item.state.rawValue) "
        var lines = ["\(String(repeating: "*", count: level)) \(state)\(priority)\(title)\(tagsText)"]
        if let scheduled = item.scheduled, self != .calendarEvent {
            lines.append("SCHEDULED: \(Self.timestamp(scheduled, hasTime: item.hasTime, recurrence: item.recurrence))")
        }
        if let deadline = item.deadline {
            lines.append("DEADLINE: \(Self.timestamp(deadline, hasTime: item.hasTime, recurrence: item.scheduled == nil ? item.recurrence : nil))")
        }
        var properties = item.properties
        properties["CREATED"] = properties["CREATED"] ?? Self.timestamp(createdAt, hasTime: true, active: false)
        if includesAppointmentWarning { properties["APPT_WARNTIME"] = properties["APPT_WARNTIME"] ?? "15" }
        lines.append(":PROPERTIES:")
        let keys = ["CREATED"] + properties.keys.filter { $0 != "CREATED" }.sorted()
        for key in keys {
            guard let value = properties[key], !key.contains(":"), !key.contains(where: \.isWhitespace) else { continue }
            lines.append(":\(key): \(Self.singleLine(value))")
        }
        lines.append(":END:")
        if self == .calendarEvent, let date = item.eventDate ?? item.agendaDate {
            lines.append(Self.timestamp(date, hasTime: item.hasTime, recurrence: item.recurrence))
        }
        if !item.body.isEmpty { lines.append(item.body) }
        if isProject { lines.append("** NEXT \(Self.singleLine(firstAction))") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func singleLine(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timestamp(_ date: Date, hasTime: Bool, recurrence: String? = nil, active: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = hasTime ? "yyyy-MM-dd EEE HH:mm" : "yyyy-MM-dd EEE"
        let repeatText = recurrence.map { " \($0)" } ?? ""
        return "\(active ? "<" : "[")\(formatter.string(from: date))\(repeatText)\(active ? ">" : "]")"
    }
}
