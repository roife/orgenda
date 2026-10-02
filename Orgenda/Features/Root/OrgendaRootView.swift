import SwiftUI

enum OrgendaTab: Hashable {
    case dashboard
    case dashboardView(OrgAgendaPerspective)
    case calendar
    case files
    case search
}

struct OrgendaRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var sceneDelegate: OrgendaSceneDelegate
    @AppStorage("appearance") private var appearance = "System"
    @State private var store = WorkspaceStore.startup()
    @State private var storageNetwork = StorageNetworkMonitor()
    @State private var selectedTab: OrgendaTab = .dashboard
    @State private var searchQuery = ""
    @State private var dashboardPerspective: OrgAgendaPerspective = .todos
    @State private var capture: CaptureDestination?
    @State private var fileNavigationRequest: WorkspaceFileNavigationRequest?
    @State private var showsWorkspaceSettings = false
    @State private var calendarNavigationID = UUID()
    @State private var filesNavigationID = UUID()
    @State private var searchNavigationID: UUID?
    private let isUITestWorkspace = WorkspaceStore.isUITestWorkspace(arguments: ProcessInfo.processInfo.arguments)

    var body: some View {
        Group {
            if !store.isStartingWorkspace && !store.isWorkspaceReady && !isUITestWorkspace {
                workspaceUnavailable
            } else {
                workspaceTabs
            }
        }
        .tint(OrgendaTheme.accent)
        .environment(\.workspaceConfiguration, store.effectiveConfiguration)
        .environment(\.orgWorkflow, store.effectiveConfiguration.workflow)
        .onChange(of: store.usesEmacsConfiguration, initial: true) { _, configured in
            dashboardPerspective = configured ? .dashboard : .todos
            if isDashboardSelected { selectDashboard() }
        }
        .onChange(of: store.configurationRevision) { _, _ in
            if !store.dashboardPerspectives.contains(dashboardPerspective) {
                dashboardPerspective = store.primaryConfiguredPerspective
                if isDashboardSelected { selectDashboard() }
            }
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            if isDashboardSelected { selectDashboard() }
        }
        .allowsHitTesting(!store.isStartingWorkspace && !store.isPerformingFileAction)
        .sheet(item: $capture) { destination in
            Group {
                switch destination {
                case .agenda(let date):
                    if store.hasWorkspaceConfiguration, date == nil {
                        ConfiguredCaptureView(store: store)
                    } else {
                    OrgItemEditor(
                        store: store,
                        draft: OrgItem(
                            id: UUID(),
                            title: "",
                            state: store.hasWorkspaceConfiguration ? store.configuration.workflow.initial : .todo,
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
                                file: store.hasWorkspaceConfiguration ? store.configuration.files.inbox : store.usesEmacsConfiguration ? OrgCaptureTemplate.inboxTask.destinationPath : "inbox.org",
                                startByte: 0,
                                endByte: 0,
                                startLine: 1
                            ),
                            habitHistory: []
                        )
                    )
                    }
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
                    await store.synchronizeFiles(automatic: true)
                    try? await Task.sleep(for: .seconds(store.storageConnection?.provider.isRemote == true ? 30 : 3))
                }
            } else {
                await store.finishStorageBeforeSuspending()
            }
        }
        .onChange(of: storageNetwork.recoveryGeneration) { _, _ in
            guard scenePhase == .active else { return }
            Task { await store.synchronizeFiles() }
        }
        .onChange(of: appearance, initial: true) { _, appearance in
            sceneDelegate.updateAppearance(appearance)
        }
    }
}

private extension OrgendaRootView {
    var actionableShortcutID: UUID? {
        guard scenePhase == .active, !store.isStartingWorkspace, !store.isPerformingFileAction,
              store.isWorkspaceReady || isUITestWorkspace else { return nil }
        return sceneDelegate.pendingAction?.id
    }

    func performQuickAction(_ action: OrgendaQuickAction) {
        switch action {
        case .newTask:
            selectDashboard()
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
        .orgendaEmptyState()
    }

    @ViewBuilder
    var workspaceTabs: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            workspaceTabContent.tabViewStyle(.sidebarAdaptable)
        } else {
            workspaceTabContent
        }
    }

    var workspaceTabContent: some View {
        TabView(selection: tabSelection) {
            if usesDashboardSection {
                // Sections keep their declared order in the tab bar, while
                // the native sidebar places them below standalone tabs.
                TabSection {
                    ForEach(store.dashboardPerspectives) { option in
                        Tab(value: dashboardTab(for: option)) {
                            dashboardContent(perspective: Binding(
                                get: { option }, set: { selectDashboard($0) }
                            ))
                        } label: {
                            Label(option.menuTitle, systemImage: option.symbol)
                                .accessibilityIdentifier("sidebar.perspective.\(option.controlID)")
                        }
                        .customizationID("sidebar.perspective.\(option.controlID)")
                        .tabPlacement(.sidebarOnly)
                    }
                } header: {
                    Text("Dashboard")
                        .accessibilityIdentifier("sidebar.dashboard")
                }
                .customizationID("orgenda.dashboard.section")
                .defaultSectionExpansion(.expanded)
            } else {
                Tab("Dashboard", systemImage: "square.grid.2x2", value: OrgendaTab.dashboard) {
                    dashboardContent(perspective: Binding(
                        get: { dashboardPerspective }, set: { selectDashboard($0) }
                    ))
                }
                .customizationID("orgenda.dashboard")
            }

            Tab("Calendar", systemImage: "calendar", value: OrgendaTab.calendar) {
                AgendaView(store: store, mode: .calendar, perspective: .constant(.agenda), onCapture: { date in
                    capture = .agenda(date)
                }, onShowInFile: showInFile, onShowOverdue: showOverdue,
                   expectsConnectedWorkspace: !isUITestWorkspace)
                .id(calendarNavigationID)
                .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
            Tab("Files", systemImage: "folder.fill", value: OrgendaTab.files) {
                FilesView(store: store, navigationRequest: $fileNavigationRequest)
                    .id(filesNavigationID)
                    .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
            Tab(value: OrgendaTab.search, role: .search) {
                SearchView(store: store, query: $searchQuery, focusRequest: searchNavigationID)
                    .id(searchNavigationID)
                    .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .environment(\.orgendaCalendarMinimumDensity,
                     OrgendaCalendar.minimumDensity(for: horizontalSizeClass))
    }

    var tabSelection: Binding<OrgendaTab> {
        Binding(get: { selectedTab }, set: { tab in
            if case .dashboardView(let perspective) = tab {
                dashboardPerspective = perspective
            } else if tab == .dashboard && usesDashboardSection {
                dashboardPerspective = primaryDashboardPerspective
            }
            selectedTab = tab
        })
    }

    func dashboardContent(perspective: Binding<OrgAgendaPerspective>) -> some View {
        AgendaView(store: store, perspective: perspective, onCapture: { date in
            capture = .agenda(date)
        }, onShowInFile: showInFile, onShowOverdue: showOverdue,
           expectsConnectedWorkspace: !isUITestWorkspace)
        .disabled(store.isStartingWorkspace || store.isPerformingFileAction)
    }

    var usesDashboardSection: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    var primaryDashboardPerspective: OrgAgendaPerspective {
        store.usesEmacsConfiguration || store.hasWorkspaceConfiguration ? .dashboard : .todos
    }

    var isDashboardSelected: Bool {
        if case .dashboardView = selectedTab { return true }
        return selectedTab == .dashboard
    }

    func dashboardTab(for perspective: OrgAgendaPerspective) -> OrgendaTab {
        usesDashboardSection && perspective != primaryDashboardPerspective
            ? .dashboardView(perspective) : .dashboard
    }

    func selectDashboard(_ perspective: OrgAgendaPerspective? = nil) {
        if let perspective { dashboardPerspective = perspective }
        selectedTab = dashboardTab(for: dashboardPerspective)
    }

    func showOverdue() {
        selectDashboard(.overdue)
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
                .keyboardShortcut("n", modifiers: .command)
                .labelStyle(.iconOnly)
                .foregroundStyle(OrgendaTheme.accentText)
                .accessibilityLabel("New task")
                .accessibilityIdentifier("orgenda.capture")
        }
    }
}
