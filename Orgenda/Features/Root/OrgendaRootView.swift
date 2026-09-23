import SwiftUI

enum OrgendaTab: Hashable {
    case dashboard
    case calendar
    case files
    case search
}

struct OrgendaRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sceneDelegate: OrgendaSceneDelegate
    @AppStorage("appearance") private var appearance = "System"
    @State private var store = WorkspaceStore.startup()
    @State private var selectedTab: OrgendaTab = .dashboard
    @State private var searchQuery = ""
    @State private var dashboardNavigationRequest: OrgAgendaPerspective?
    @State private var capture: CaptureDestination?
    @State private var fileNavigationRequest: WorkspaceFileNavigationRequest?
    @State private var showsWorkspaceSettings = false
    @State private var calendarNavigationID = UUID()
    @State private var filesNavigationID = UUID()
    @State private var searchNavigationID: UUID?
    private let isUITestWorkspace = WorkspaceStore.isUITestWorkspace(arguments: ProcessInfo.processInfo.arguments)

    var body: some View {
        Group {
            if !store.isStartingWorkspace && !store.isFolderConnected && !isUITestWorkspace {
                workspaceUnavailable
            } else {
                workspaceTabs
            }
        }
        .tint(OrgendaTheme.accent)
        .allowsHitTesting(!store.isStartingWorkspace && !store.isPerformingFileAction)
        .sheet(item: $capture) { destination in
            Group {
                switch destination {
                case .agenda(let date):
                    OrgItemEditor(
                        store: store,
                        draft: OrgItem(
                            id: UUID(),
                            title: "",
                            state: .todo,
                            kind: .task,
                            priority: .none,
                            tags: [],
                            scheduled: date,
                            deadline: nil,
                            hasTime: false,
                            durationMinutes: 30,
                            recurrence: nil,
                            body: "",
                            source: SourceLocation(
                                file: store.usesEmacsConfiguration ? OrgCaptureTemplate.inboxTask.destinationPath : "inbox.org",
                                startByte: 0,
                                endByte: 0,
                                startLine: 1
                            ),
                            habitHistory: []
                        )
                    )
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsWorkspaceSettings) {
            SettingsView(store: store, initialDestination: .workspace)
        }
        .task {
            #if DEBUG
            // Hold the real startup state long enough for deterministic UI checks.
            if isUITestWorkspace,
               let value = ProcessInfo.processInfo.environment["ORGENDA_UI_TEST_STARTUP_DELAY"],
               let delay = Double(value), delay.isFinite, delay > 0 {
                do { try await Task.sleep(for: .seconds(min(delay, 60))) }
                catch { return }
            }
            #endif
            await store.startWorkspace()
        }
        .task(id: actionableShortcutID) {
            guard let requestID = actionableShortcutID else { return }
            // A quick action must not discard a draft in an existing sheet.
            // Wait only while a request is pending; readiness changes cancel this task.
            while sceneDelegate.isPresentingModal {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
            guard !Task.isCancelled, let request = sceneDelegate.pendingAction,
                  request.id == requestID else { return }
            sceneDelegate.pendingAction = nil
            performQuickAction(request.action)
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                if store.isFolderConnected { await store.refreshReminders() }
                while !Task.isCancelled {
                    await store.synchronizeFiles()
                    try? await Task.sleep(for: .seconds(3))
                }
            } else {
                await store.synchronizeFiles()
            }
        }
        .preferredColorScheme(
            appearance == "Light" ? .light
                : appearance == "Dark" ? .dark : nil
        )
    }
}

private extension OrgendaRootView {
    var actionableShortcutID: UUID? {
        guard scenePhase == .active, !store.isStartingWorkspace, !store.isPerformingFileAction,
              store.isFolderConnected || isUITestWorkspace else { return nil }
        return sceneDelegate.pendingAction?.id
    }

    func performQuickAction(_ action: OrgendaQuickAction) {
        switch action {
        case .newTask:
            selectedTab = .dashboard
            capture = .agenda(nil)
        case .today:
            store.selectedDate = .now.startOfDay
            calendarNavigationID = UUID()
            selectedTab = .calendar
        case .search:
            searchQuery = ""
            searchNavigationID = UUID()
            selectedTab = .search
        case .files:
            fileNavigationRequest = nil
            filesNavigationID = UUID()
            selectedTab = .files
        }
    }

    var workspaceUnavailable: some View {
        ContentUnavailableView {
            Label("Workspace unavailable", systemImage: "folder.badge.questionmark")
        } description: {
            Text(store.fileSyncError ?? String(localized: "Your files could not be opened. Try again or choose a folder."))
        } actions: {
            Button("Try Again") { Task { await store.startWorkspace() } }
                .buttonStyle(.borderedProminent)
            Button("Choose Folder") { showsWorkspaceSettings = true }
                .buttonStyle(.bordered)
        }
    }

    var workspaceTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: .dashboard) {
                AgendaView(store: store, onCapture: { date in
                    capture = .agenda(date)
                }, onShowInFile: showInFile, onShowOverdue: showOverdue,
                   navigationRequest: $dashboardNavigationRequest,
                   expectsConnectedWorkspace: !isUITestWorkspace)
                .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                AgendaView(store: store, mode: .calendar, onCapture: { date in
                    capture = .agenda(date)
                }, onShowInFile: showInFile, onShowOverdue: showOverdue,
                   expectsConnectedWorkspace: !isUITestWorkspace)
                .id(calendarNavigationID)
                .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
            Tab("Files", systemImage: "folder.fill", value: .files) {
                FilesView(store: store, navigationRequest: $fileNavigationRequest)
                    .id(filesNavigationID)
                    .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
            Tab(value: .search, role: .search) {
                SearchView(store: store, query: $searchQuery, focusRequest: searchNavigationID)
                    .id(searchNavigationID)
                    .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
    }

    func showOverdue() {
        dashboardNavigationRequest = .overdue
        selectedTab = .dashboard
    }

    func showInFile(_ item: OrgItem) {
        let current = store.item(withID: item.id) ?? item
        fileNavigationRequest = WorkspaceFileNavigationRequest(source: current.source, itemID: current.id)
        selectedTab = .files
    }
}

private enum CaptureDestination: Identifiable {
    case agenda(Date?)

    var id: String {
        switch self {
        case .agenda(let date): "agenda-\(date?.orgendaDayKey ?? "unscheduled")"
        }
    }
}

/// The system owns the toolbar's material, placement and content insets.
/// Use the toolbar's glass surface without adding a second button background.
struct OrgendaCaptureToolbar: ToolbarContent {
    let onCapture: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("New task", systemImage: "plus", action: onCapture)
                .labelStyle(.iconOnly)
                .foregroundStyle(OrgendaTheme.accentText)
                .accessibilityLabel("New task")
                .accessibilityIdentifier("orgenda.capture")
        }
    }
}
