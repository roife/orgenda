import Foundation

/// Capture definitions retained by the classic workspace preset.
enum OrgCaptureTemplate: String, CaseIterable, Sendable {
    case inboxTask, inboxNote, nextAction, workProject, personalProject
    case reminder, repeatingReminder, someday, calendarEvent

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
}
