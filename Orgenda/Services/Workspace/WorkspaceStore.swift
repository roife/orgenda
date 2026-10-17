import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceStore {
    var configuration = WorkspaceConfiguration.standard
    var configurationDocument = ConfigurationDocument(configuration: .standard)
    var configurationError: String?
    var configurationRevision: UInt64 = 0
    var isSavingConfiguration = false
    var configurationSource: String?
    /// Connected workspaces use their persisted configuration.
    var hasWorkspaceConfiguration = false
    var items: [OrgItem] {
        didSet { rebuildDerivedCollections() }
    }
    var journalEntries: [JournalEntry]
    /// Edits and storage deltas address documents by path; the sorted array is
    /// a lazily rebuilt projection for views.
    var documentsByPath: [String: WorkspaceDocument] = [:] {
        didSet { sortedDocuments = nil }
    }
    @ObservationIgnored private var sortedDocuments: [WorkspaceDocument]?
    var documents: [WorkspaceDocument] {
        get {
            let byPath = documentsByPath // Registers observation.
            if let sortedDocuments { return sortedDocuments }
            let result = byPath.values.sorted { $0.path < $1.path }
            sortedDocuments = result
            return result
        }
        set {
            documentsByPath = Dictionary(newValue.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
            storageContentGeneration &+= 1
        }
    }
    var parsedDocuments: [String: ParsedOrgDocument] = [:]
    var selectedDate: Date
    var workspaceName = String(localized: "Org Workspace")
    var workspaceLocation = String(localized: "Workspace is not connected")
    var isStartingWorkspace = true
    var isFolderConnected = false
    var isSynchronizing = false
    var fileSyncError: String?
    var lastFileSync: Date?
    var pendingFileCount: Int { dirtyFilePaths.union(pendingUploadPaths).count }
    var storageConnection: StorageConnection?
    var syncState: WorkspaceSyncState = .idle
    var syncConflicts: [WorkspaceConflict] = []
    var pendingUploadPaths: Set<String> = []
    var hasPendingStorageOperation = false
    var pendingUploadCount: Int { pendingUploadPaths.count }
    var isWorkspaceReady: Bool { isFolderConnected }
    var hasPendingStorageChanges: Bool { !dirtyFilePaths.isEmpty || !pendingUploadPaths.isEmpty || !syncConflicts.isEmpty || hasPendingStorageOperation }
    var fileSaveErrors: [String: String] = [:]
    var pathSyncErrors: [String: String] = [:]
    @ObservationIgnored var isStorageForeground = false
    var externalDocumentRevisions: [String: UInt64] = [:]

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

    @ObservationIgnored var localStore: LocalStore?
    @ObservationIgnored var connectionDefaults: UserDefaults = .standard
    @ObservationIgnored var isChangingStorage = false
    @ObservationIgnored var syncEngine: SyncEngine?
    @ObservationIgnored var storageObservationTask: Task<Void, Never>?
    @ObservationIgnored var syncStatusTask: Task<Void, Never>?
    @ObservationIgnored var persistenceTask: Task<Void, Never>?
    @ObservationIgnored var folderMonitor: WorkspaceFolderMonitor?
    var syncRetryAt: Date?
    @ObservationIgnored var storageContentGeneration: UInt64 = 0
    @ObservationIgnored var appliedStorageRevision: UInt64 = 0
    @ObservationIgnored var storageCacheDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Workspace Storage", isDirectory: true)
    @ObservationIgnored var folderAccessURL: URL?
    @ObservationIgnored var persistedBlobs: [String: String] = [:]
    /// Baselines of documents removed by storage while an editor may still save.
    @ObservationIgnored var retiredBlobs: [String: String] = [:]
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
        self.selectedDate = selectedDate.startOfDay
        self.documents = documents
        rebuildDerivedCollections()
    }

    /// Rebuilds the materialized derived collections. Called from the `items`
    /// observer and configuration updates, so every mutation path (index
    /// publishing, edits, moves, sync) refreshes them exactly once.
    func rebuildDerivedCollections() {
        let agendaItems = hasWorkspaceConfiguration ? items.filter { configuration.agenda.includes($0.source.file) } : items
        self.agendaItems = agendaItems
        datedItems = agendaItems
            .filter {
                $0.agendaDate != nil
                    && (!hasWorkspaceConfiguration || $0.isOpen)
            }
            .sorted { $0.agendaDate! < $1.agendaDate! }
        openTodos = agendaItems
            .filter {
                $0.isOpen && $0.agendaDate == nil && $0.hasWorkflowState
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
