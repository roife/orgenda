import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceStore {
    var items: [OrgItem] {
        didSet { rebuildDerivedCollections() }
    }
    var journalEntries: [JournalEntry]
    var documents: [WorkspaceDocument]
    var parserStatus = String(localized: "Tree-sitter parser is warming up")
    var parseDurationMilliseconds: Double = 0
    var parsedDocuments: [String: ParsedOrgDocument] = [:]
    var selectedDate: Date
    var workspaceName = String(localized: "Org Workspace")
    var workspaceLocation = String(localized: "Workspace is not connected")
    var isStartingWorkspace = true
    var isFolderConnected = false
    var isSynchronizing = false
    var fileSyncError: String?
    var lastFileSync: Date?
    var pendingFileCount = 0
    var fileSaveErrors: [String: String] = [:]
    var externalDocumentRevisions: [String: UInt64] = [:]
    var usesEmacsConfiguration = false {
        didSet { rebuildDerivedCollections() }
    }

    // Derived collections materialized once per `items` change. Views read
    // these O(1) snapshots instead of re-filtering and re-sorting the same
    // arrays on every body evaluation.
    private(set) var agendaItems: [OrgItem] = []
    private(set) var datedItems: [OrgItem] = []
    private(set) var openTodos: [OrgItem] = []
    private(set) var overdueItems: [OrgItem] = []
    private(set) var markedAgendaDays: Set<String> = []
    /// Lazily filled per-day agenda projections; cleared on every rebuild.
    @ObservationIgnored var itemsByDayCache: [String: [OrgItem]] = [:]
    @ObservationIgnored var itemIndicesByID: [UUID: Int] = [:]
    var operationError: String?
    var workspaceFileSessionID = UUID()
    var isPerformingFileAction = false
    var fileActionError: String?
    var fileUndo: WorkspaceFileUndo?
    var recentlyDeleted: [WorkspaceTrashEntry] = []
    @ObservationIgnored var demoDeletedFiles: [UUID: [WorkspaceDocument]] = [:]
    var reminderStatus = String(localized: "Off")
    var reminderPermissionDenied = false
    @ObservationIgnored let reminderScheduler = OrgReminderScheduler()

    @ObservationIgnored var fileStore: WorkspaceFileStore?
    @ObservationIgnored var folderAccessURL: URL?
    @ObservationIgnored var persistedContents: [String: String] = [:]
    var dirtyFilePaths: Set<String> = []
    @ObservationIgnored var fileSaveTask: Task<Void, Never>?
    @ObservationIgnored var hasStarted = false

    // Internal state shared by the indexing and editing extensions.
    @ObservationIgnored let indexService = OrgIndexService()
    @ObservationIgnored var parseTask: Task<Void, Never>?
    @ObservationIgnored var parseGeneration: UInt64 = 0
    @ObservationIgnored var pendingDirtyPaths: Set<String> = []

    init(
        items: [OrgItem] = [],
        journalEntries: [JournalEntry] = [],
        documents: [WorkspaceDocument] = [],
        selectedDate: Date = .now
    ) {
        self.items = items
        self.journalEntries = journalEntries
        self.documents = documents
        self.selectedDate = selectedDate.startOfDay
        rebuildDerivedCollections()
    }

    /// Rebuilds the materialized derived collections. Called from the `items`
    /// and `usesEmacsConfiguration` observers, so every mutation path (index
    /// publishing, edits, moves, sync) refreshes them exactly once.
    func rebuildDerivedCollections() {
        let agendaItems = usesEmacsConfiguration
            ? items.filter { OrgWorkspaceConfiguration.isAgendaSource($0.source.file) }
            : items
        self.agendaItems = agendaItems
        datedItems = agendaItems
            .filter {
                $0.agendaDate != nil
                    && (!usesEmacsConfiguration || ($0.isOpen && OrgWorkspaceConfiguration.datedPaths.contains($0.source.file)))
            }
            .sorted { $0.agendaDate! < $1.agendaDate! }
        openTodos = agendaItems
            .filter {
                $0.isOpen && $0.agendaDate == nil && $0.hasWorkflowState
                    && (!usesEmacsConfiguration || OrgWorkspaceConfiguration.actionPaths.contains($0.source.file))
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
                return lhs.title < rhs.title
            }
        overdueItems = datedItems.filter(\.isOverdue)
        markedAgendaDays = Set(datedItems.flatMap { item in
            [item.scheduled, item.deadline, item.eventDate].compactMap { $0?.orgendaDayKey }
        })
        itemIndicesByID = Dictionary(
            items.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        itemsByDayCache.removeAll()
    }

}
