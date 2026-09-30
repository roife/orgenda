import CryptoKit
import Foundation

extension WorkspaceStore {
    nonisolated static var localWorkspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    var storageDescription: String {
        storageConnection?.provider.isRemote == true ? String(localized: "Edits are saved on this device before syncing.") : (isFolderConnected ? String(localized: "Changes save to the connected folder.") : String(localized: "Connect a folder to save changes."))
    }

    func startWorkspace(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        localWorkspaceURL: URL? = nil
    ) async {
        guard !hasStarted, !Task.isCancelled else { return }
        hasStarted = true
        isStartingWorkspace = true
        let isUITestWorkspace = Self.isUITestWorkspace(arguments: arguments)
        defer {
            if Task.isCancelled {
                hasStarted = false
            } else {
                isStartingWorkspace = false
                // A failed startup can be retried after the folder becomes available.
                hasStarted = isFolderConnected || isUITestWorkspace
            }
        }
        if isUITestWorkspace {
            #if DEBUG
            if arguments.contains("--workflow-settings-fixture") {
                // Real local persistence for reorder/add UI tests, never the
                // user's selected workspace or standard connection preferences.
                do {
                    let id = UUID().uuidString
                    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workflow Settings-" + id)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let source = try ConfigurationDocument(configuration: .standard).encoded(.standard)
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
                    let date = Self.orgDayFormatter.string(from: Date.now.startOfDay.adding(days: offset))
                    return """
                    * Calendar day \(offset) event :event:
                    SCHEDULED: <\(date)>
                    * TODO Calendar day \(offset) first :work:focus:
                    SCHEDULED: <\(date) 09:00>
                    * TODO Calendar day \(offset) second :home:
                    SCHEDULED: <\(date) 16:00>
                    """
                }.joined(separator: "\n")
                let today = Self.orgDayFormatter.string(from: Date.now.startOfDay)
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
            #endif
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
            #if DEBUG
            if arguments.contains("--storage-sync-fixture") {
                configureStorageSyncFixture()
            }
            #endif
            scheduleWorkspaceParse()
            await waitForWorkspaceIndex()
            return
        }
        await restoreConfiguredStorage(defaults: defaults, localURL: localWorkspaceURL ?? Self.localWorkspaceURL)
        await waitForWorkspaceIndex()
    }

    static func unsavedEditsFolder(for workspaceIdentity: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unsaved Edits", isDirectory: true)
            .appendingPathComponent(recoveryDigest(workspaceIdentity), isDirectory: true)
    }

    func waitForFileOperation() async -> Bool {
        while isSynchronizing {
            do { try await Task.sleep(for: .milliseconds(25)) }
            catch { return false }
        }
        return !Task.isCancelled
    }

    static func recoveryDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func preserveUnsaved(_ contents: String, path: String, workspaceIdentity: String) async throws {
        let recovery = unsavedEditsFolder(for: workspaceIdentity)
        // Content addressing keeps every distinct draft, without duplicating an
        // unchanged conflict on each refresh or colliding across workspaces.
        let name = recoveryDigest(path) + "-" + recoveryDigest(contents)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: recovery.appendingPathComponent(name + ".txt"), options: .atomic)
            let metadata = ["workspace": workspaceIdentity, "path": path]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: recovery.appendingPathComponent(name + ".json"), options: .atomic)
        }.value
    }
}
