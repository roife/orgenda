import Foundation

/// Portable values from the current init-agenda.el and init-org.el. Paths stay
/// relative so the same workspace can be selected from any Files provider.
enum OrgWorkspaceConfiguration {
    static let attachmentDirectory = ".attach"
    static let taskStates = OrgWorkflowState.allCases
    static let agendaPaths: Set<String> = Set(["actions", "calendar", "inbox", "personal", "routines", "someday", "work"].map { "agenda/\($0).org" })
    static let refilePaths = ["agenda/actions.org", "agenda/work.org", "agenda/personal.org", "agenda/routines.org", "agenda/someday.org"]
}
