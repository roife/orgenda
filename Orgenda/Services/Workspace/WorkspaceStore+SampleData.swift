import Foundation

extension WorkspaceStore {
    /// Production always begins empty and waits for the persistent workspace.
    /// Only explicit debug launches may use the isolated UI-test fixtures.
    static func startup(arguments: [String] = ProcessInfo.processInfo.arguments) -> WorkspaceStore {
        isUITestWorkspace(arguments: arguments) ? preview() : WorkspaceStore()
    }

    nonisolated static func isUITestWorkspace(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        // Preserve the old argument for existing developer test runners.
        arguments.contains("--ui-test-workspace") || arguments.contains("--demo-workspace")
        #else
        false
        #endif
    }

    static func preview(now: Date = .now) -> WorkspaceStore {
        let calendar = Calendar.autoupdatingCurrent
        func at(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: now.startOfDay) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let inbox = """
        #+title: orgenda Inbox
        #+startup: overview

        * TODO [#A] Review quarterly roadmap :work:focus:
        SCHEDULED: <\(WorkspaceStore.orgDateFormatter.string(from: at(0, hour: 9, minute: 30)))>
        Bring the product brief and parser performance notes.

        * TODO [#B] Write tree-sitter Org queries :dev:org:project:
        DEADLINE: <\(WorkspaceStore.orgDateFormatter.string(from: at(0, hour: 14)))>

        * TODO Evening walk :habit:health:
        SCHEDULED: <\(WorkspaceStore.orgDateFormatter.string(from: at(0, hour: 19))) +1d>

        * TODO Plan iPad reading workflow :project:
        """

        let notes = """
        #+title: Reading Notes

        * Org mode on the move
        - [X] Keep files portable
        - [ ] Make capture effortless
        - [ ] Preserve unknown syntax

        #+begin_quote
        Plain text remains the source of truth.
        #+end_quote
        """

        let calendarSource = """
        #+title: Calendar

        * orgenda anniversary — 6 years :event:anniversary:
        SCHEDULED: <\(WorkspaceStore.orgDayFormatter.string(from: at(0, hour: 0)))>

        * Weekend review :event:review:
        SCHEDULED: <\(WorkspaceStore.orgDayFormatter.string(from: at(0, hour: 0)))>

        * Design sync :team:event:
        SCHEDULED: <\(WorkspaceStore.orgDateFormatter.string(from: at(0, hour: 11)))>
        Weekly design review.
        """

        let personalSource = """
        #+title: Personal

        * WAIT [#C] Renew library card :errands:
        SCHEDULED: <\(WorkspaceStore.orgDateFormatter.string(from: at(-2, hour: 16)))>
        Bring proof of address.
        """

        let items: [OrgItem] = [
            OrgItem(id: UUID(), title: "orgenda anniversary — 6 years", state: .todo, kind: .event, priority: .none, tags: ["event", "anniversary"], scheduled: at(0, hour: 0), deadline: nil, hasTime: false, durationMinutes: 0, recurrence: nil, body: "", source: SourceLocation(file: "calendar.org", startByte: 0, endByte: 0, startLine: 3), habitHistory: []),
            OrgItem(id: UUID(), title: "Weekend review", state: .todo, kind: .event, priority: .none, tags: ["event", "review"], scheduled: at(0, hour: 0), deadline: nil, hasTime: false, durationMinutes: 0, recurrence: nil, body: "", source: SourceLocation(file: "calendar.org", startByte: 0, endByte: 0, startLine: 6), habitHistory: []),
            OrgItem(id: UUID(), title: "Review quarterly roadmap", state: .todo, kind: .task, priority: .high, tags: ["work", "focus"], scheduled: at(0, hour: 9, minute: 30), deadline: nil, hasTime: true, durationMinutes: 45, recurrence: nil, body: "Bring the product brief and parser performance notes.", source: SourceLocation(file: "inbox.org", startByte: 44, endByte: 180, startLine: 4), habitHistory: []),
            OrgItem(id: UUID(), title: "Design sync", state: .todo, kind: .event, priority: .none, tags: ["team"], scheduled: at(0, hour: 11), deadline: nil, hasTime: true, durationMinutes: 60, recurrence: nil, body: "Weekly design review", source: SourceLocation(file: "calendar.org", startByte: 0, endByte: 98, startLine: 1), habitHistory: []),
            OrgItem(id: UUID(), title: "Write tree-sitter Org queries", state: .todo, kind: .project, priority: .medium, tags: ["dev", "org", "project"], scheduled: at(0, hour: 14), deadline: at(1, hour: 17), hasTime: true, durationMinutes: 90, recurrence: nil, body: "Cover agenda, journal, preview and search captures.", source: SourceLocation(file: "inbox.org", startByte: 182, endByte: 310, startLine: 8), habitHistory: []),
            OrgItem(id: UUID(), title: "Evening walk", state: .todo, kind: .habit, priority: .none, tags: ["habit", "health"], scheduled: at(0, hour: 19), deadline: nil, hasTime: true, durationMinutes: 30, recurrence: "+1d", body: "", source: SourceLocation(file: "inbox.org", startByte: 312, endByte: 402, startLine: 12), habitHistory: (1...14).compactMap { $0.isMultiple(of: 3) ? nil : at(-$0, hour: 19) }),
            OrgItem(id: UUID(), title: "Renew library card", state: .wait, kind: .task, priority: .low, tags: ["errands"], scheduled: at(-2, hour: 16), deadline: nil, hasTime: true, durationMinutes: 20, recurrence: nil, body: "Bring proof of address.", source: SourceLocation(file: "personal.org", startByte: 0, endByte: 108, startLine: 1), habitHistory: []),
            OrgItem(id: UUID(), title: "Plan iPad reading workflow", state: .todo, kind: .project, priority: .medium, tags: ["project"], scheduled: nil, deadline: nil, hasTime: false, durationMinutes: 0, recurrence: nil, body: "Collect files, annotations and capture templates.", source: SourceLocation(file: "inbox.org", startByte: 404, endByte: 472, startLine: 15), habitHistory: [])
        ]

        let journal: [JournalEntry] = [
            JournalEntry(id: UUID(), date: at(0, hour: 8, minute: 10), title: "Morning note", body: "A calm start. Today I want the parser boundary to stay small and explicit.", source: SourceLocation(file: "journal/2026.org", startByte: 0, endByte: 120, startLine: 2)),
            JournalEntry(id: UUID(), date: at(-1, hour: 21, minute: 40), title: "What moved forward", body: "The agenda interactions finally feel native on a phone.", source: SourceLocation(file: "journal/2026.org", startByte: 122, endByte: 230, startLine: 7))
        ]

        let documents: [WorkspaceDocument] = [
            WorkspaceDocument(path: "inbox.org", title: "Inbox", contents: inbox, kind: .org),
            WorkspaceDocument(path: "calendar.org", title: "Calendar", contents: calendarSource, kind: .org),
            WorkspaceDocument(path: "personal.org", title: "Personal", contents: personalSource, kind: .org),
            WorkspaceDocument(path: "notes/reading.org", title: "Reading Notes", contents: notes, kind: .org),
            WorkspaceDocument(path: "journal/2026.org", title: "2026 Journal", contents: "* \(now.formatted(date: .long, time: .omitted))\n** Morning note\nA calm start.", kind: .org),
            WorkspaceDocument(path: "projects", title: "Projects", contents: "", kind: .folder)
        ]

        let store = WorkspaceStore(items: items, journalEntries: journal, documents: documents, selectedDate: now)
        store.workspaceLocation = String(localized: "Preview workspace")
        store.usesEmacsConfiguration = false
        return store
    }
}
