import Foundation

/// Portable values from the current init-agenda.el and init-org.el. Paths stay
/// relative so the same workspace can be selected from any Files provider.
enum OrgWorkspaceConfiguration {
    static let agendaDirectory = "agenda"
    static let inboxPath = "agenda/inbox.org"
    static let attachmentDirectory = ".attach"
    static let deadlineWarningDays = 3
    static let appointmentWarningMinutes = 15
    static let appointmentRepeatMinutes = 5
    static let taskStates = OrgWorkflowState.allCases
    static let contextTags = ["@home", "@work", "note"]
    static let agendaPaths: Set<String> = Set(["actions", "calendar", "inbox", "personal", "routines", "someday", "work"].map { "agenda/\($0).org" })
    static let datedPaths = agendaPaths.subtracting(["agenda/someday.org"])
    static let actionPaths = datedPaths.subtracting(["agenda/calendar.org"])
    static let projectPaths: Set<String> = ["agenda/work.org", "agenda/personal.org"]
    static let somedayPaths: Set<String> = ["agenda/work.org", "agenda/personal.org", "agenda/someday.org"]
    static let refilePaths = ["agenda/actions.org", "agenda/work.org", "agenda/personal.org", "agenda/routines.org", "agenda/someday.org"]

    static func isAgendaSource(_ path: String) -> Bool { agendaPaths.contains(path) }
}
