#if DEBUG
import Foundation

extension WorkspaceStore {
    func configureLaunchFixtures(arguments: [String]) async {
        // Exercise empty pages without touching the connected workspace.
        if arguments.contains("--empty-workspace-fixture") {
            items = []
            journalEntries = []
            documents = []
        }
        if arguments.contains("--workflow-settings-fixture") {
            // Real local persistence for reorder/add UI tests, never the
            // user's selected workspace or standard connection preferences.
            do {
                let id = UUID().uuidString
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workflow Settings-" + id)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var configuration = WorkspaceConfiguration.standard
                if arguments.contains("--native-selection-fixture") {
                    configuration.agenda.sources = ["projects/work.org", "offline/planned.org"]
                    configuration.workflow.keywords["TODO"] = .init(key: "t")
                    configuration.workflow.keywords["DONE"] = .init(key: "d")
                    try FileManager.default.createDirectory(at: root.appendingPathComponent("projects"), withIntermediateDirectories: true)
                    try "* TODO Inbox selection probe\n".write(to: root.appendingPathComponent("inbox.org"), atomically: true, encoding: .utf8)
                    try "* TODO Project selection probe\n".write(to: root.appendingPathComponent("projects/work.org"), atomically: true, encoding: .utf8)
                }
                let source = try ConfigurationDocument(configuration: configuration).encoded(configuration)
                try source.write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
                let defaults = UserDefaults(suiteName: "orgenda.workflow-ui." + id)!
                await connectFolder(root, remember: false, defaults: defaults)
            } catch { fileSyncError = error.localizedDescription }
            return
        }
        if arguments.contains("--calendar-layout-fixture") {
            usesEmacsConfiguration = true
            items = []
            journalEntries = []
            let days = (0..<8).map { offset in
                let date = Date.now.startOfDay.adding(days: offset).orgDateText(includesTime: false)
                return """
                * Calendar day \(offset) event :event:
                SCHEDULED: <\(date)>
                * TODO Calendar day \(offset) first :work:focus:
                SCHEDULED: <\(date) 09:00>
                * TODO Calendar day \(offset) second :home:
                SCHEDULED: <\(date) 16:00>
                """
            }.joined(separator: "\n")
            let today = Date.now.startOfDay.orgDateText(includesTime: false)
            let recurring = """
            * TODO Daily morning routine :habit:health:
            SCHEDULED: <\(today) 07:00 +1d>
            * TODO Daily evening routine :habit:health:
            SCHEDULED: <\(today) 18:00 +1d>
            """
            documents = [WorkspaceDocument(path: "agenda/work.org", title: "Calendar", contents:
                "* TODO Calendar layout setup\n" + days + "\n" + recurring, kind: .org)]
        }
        if arguments.contains("--configured-agenda-fixture") {
            usesEmacsConfiguration = true
            items = []
            journalEntries = []
            documents = [
                WorkspaceDocument(path: "agenda/actions.org", title: "Actions", contents: """
                * URGENT Fix launch blocker
                * NEXT Prepare release notes
                * WAIT Waiting for review
                """, kind: .org),
                WorkspaceDocument(path: "agenda/inbox.org", title: "Inbox", contents: "* TODO Unscheduled sidebar task\n", kind: .org),
                WorkspaceDocument(path: "agenda/personal.org", title: "Personal", contents: "* TODO Overdue sidebar task\nSCHEDULED: <2020-01-01 Wed>\n", kind: .org),
                WorkspaceDocument(path: "agenda/work.org", title: "Work", contents: "* TODO Sidebar project\n** NEXT Project next step\n", kind: .org),
                WorkspaceDocument(path: "agenda/someday.org", title: "Someday", contents: "* SOMEDAY Learn ceramics\n", kind: .org)
            ]
        }
        if arguments.contains("--image-preview-fixture") {
            do { try await configureImagePreviewFixture() }
            catch { fileSyncError = error.localizedDescription }
            return
        }
        if arguments.contains("--file-browser-fixture") {
            items = []
            journalEntries = []
            documents = [
                WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: "* TODO File gesture probe\n", kind: .org),
                WorkspaceDocument(path: "projects", title: "Projects", contents: "", kind: .folder),
                WorkspaceDocument(path: "projects/child", title: "Child", contents: "", kind: .folder),
                WorkspaceDocument(path: "projects/child/notes.org", title: "Notes", contents: "* Nested content 中文\n", kind: .org),
                WorkspaceDocument(path: "destination", title: "Destination", contents: "", kind: .folder)
            ]
        }
        if arguments.contains("--storage-sync-fixture") {
            configureStorageSyncFixture()
        }
        scheduleWorkspaceParse()
        await waitForWorkspaceIndex()
    }
}
#endif
