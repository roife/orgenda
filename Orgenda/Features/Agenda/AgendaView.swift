import SwiftUI

struct AgendaView: View {
    typealias Perspective = OrgAgendaPerspective

    enum Mode {
        case agenda
        case calendar
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var store: WorkspaceStore
    let mode: Mode
    let onCapture: (Date?) -> Void
    let onShowInFile: (OrgItem) -> Void
    let onShowOverdue: () -> Void
    @Binding var navigationRequest: Perspective?
    var expectsConnectedWorkspace = false
    @State private var perspective: Perspective
    @State private var visitedPerspectives: Set<Perspective>
    @State private var lastWorkspaceConfiguration: Bool?
    @State private var editorItem: OrgItem?
    @State private var showsCompletionError = false
    @State private var reschedulingItem: OrgItem?
    @State private var revealedItemID: UUID?
    @State private var gestureUndo: WorkspaceGestureUndo?

    init(
        store: WorkspaceStore,
        mode: Mode = .agenda,
        onCapture: @escaping (Date?) -> Void,
        onShowInFile: @escaping (OrgItem) -> Void,
        onShowOverdue: @escaping () -> Void,
        navigationRequest: Binding<Perspective?> = .constant(nil),
        expectsConnectedWorkspace: Bool = false
    ) {
        self.store = store
        self.mode = mode
        self.onCapture = onCapture
        self.onShowInFile = onShowInFile
        self.onShowOverdue = onShowOverdue
        _navigationRequest = navigationRequest
        self.expectsConnectedWorkspace = expectsConnectedWorkspace
        let initial: Perspective = mode == .calendar ? .agenda : (store.usesEmacsConfiguration ? .dashboard : .todos)
        _perspective = State(initialValue: initial)
        _visitedPerspectives = State(initialValue: [initial])
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if store.isStartingWorkspace {
                    AgendaStartupSkeleton(
                        date: store.selectedDate,
                        showsCalendar: displayedPerspective == .agenda
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ForEach(availablePerspectives.filter { visitedPerspectives.contains($0) }) { option in
                        perspectiveContent(option)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .opacity(perspective == option ? 1 : 0)
                            .zIndex(perspective == option ? 1 : 0)
                            .allowsHitTesting(perspective == option)
                            .accessibilityHidden(perspective != option)
                            .animation(OrgendaMotion.animation(.content, reduceMotion: reduceMotion), value: perspective)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(mode == .calendar ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if mode == .agenda {
                    ToolbarItem(placement: .topBarLeading) {
                        perspectiveMenu
                    }
                    OrgendaCaptureToolbar {
                        onCapture(nil)
                    }
                }
            }
            .sheet(item: $editorItem) { item in
                OrgItemEditor(store: store, draft: item)
            }
            .sheet(item: $reschedulingItem) { item in
                AgendaRescheduleSheet(item: item) { date in reschedule(item, to: date) }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let change = gestureUndo {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Text(change.label)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Undo", systemImage: "arrow.uturn.backward") {
                                if !store.undoGesture(change) { showsCompletionError = true }
                                gestureUndo = nil
                            }
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.bold())
                            .foregroundStyle(OrgendaTheme.accentText)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("agenda.gesture.undo")
                            Button("Dismiss", systemImage: "xmark") { gestureUndo = nil }
                                .labelStyle(.iconOnly).frame(width: 44, height: 44)
                        }
                        .fixedSize()
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16).padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .sensoryFeedback(.selection, trigger: perspective)
            .alert("Couldn't Update Item", isPresented: $showsCompletionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.operationError ?? String(localized: "The source changed. Please reopen this item."))
            }
        }
        .onChange(of: store.usesEmacsConfiguration, initial: true) { _, configured in
            // The initial callback also runs when returning to this tab.
            // Only apply the default when the workspace configuration changes.
            guard lastWorkspaceConfiguration != configured else { return }
            lastWorkspaceConfiguration = configured
            selectPerspective(mode == .calendar ? .agenda : (configured ? .dashboard : .todos))
        }
        .task(id: navigationRequest) {
            guard let requested = navigationRequest,
                  availablePerspectives.contains(requested) else { return }
            selectPerspective(requested)
            navigationRequest = nil
        }
    }

    private var availablePerspectives: [Perspective] {
        if mode == .calendar { return [.agenda] }
        return store.usesEmacsConfiguration
            ? Perspective.allCases.filter { $0 != .agenda }
            : [.overdue, .todos]
    }

    private var displayedPerspective: Perspective {
        if mode == .calendar { return .agenda }
        if store.isStartingWorkspace {
            return expectsConnectedWorkspace || store.usesEmacsConfiguration ? .dashboard : .todos
        }
        return perspective
    }

    private func selectPerspective(_ option: Perspective) {
        revealedItemID = nil
        visitedPerspectives.insert(option)
        perspective = option
    }

    private var perspectiveMenu: some View {
        Menu {
            Picker("Dashboard view", selection: Binding(
                get: { perspective },
                set: selectPerspective
            )) {
                ForEach(availablePerspectives) { option in
                    Label(option.menuTitle, systemImage: option.symbol)
                        .tag(option)
                        .accessibilityIdentifier("agenda.mode.\(option.controlID)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(displayedPerspective.title)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
        }
        .accessibilityLabel("Switch view")
        .accessibilityValue(displayedPerspective.menuTitle)
        .accessibilityHint("Choose which tasks to show")
        .accessibilityIdentifier("agenda.viewMenu")
    }

    @ViewBuilder
    private func perspectiveContent(_ option: Perspective) -> some View {
        switch option {
        // Keep Calendar's fixed date header separate from its timeline. Other
        // views extend beneath the system bars for the progressive edge blur.
        case .agenda:
            AgendaCalendarView(
                store: store, isActive: perspective == .agenda,
                onCapture: onCapture, onReschedule: reschedule,
                onToggle: toggle, onOpen: { editorItem = store.item(withID: $0.id) ?? $0 },
                onShowInFile: showInFile,
                onShowOverdue: onShowOverdue,
                onPageChange: { revealedItemID = nil }, row: configuredItem
            )
            .clipped()
        case .overdue: AgendaOverdueList(items: store.overdueItems, row: configuredItem)
        case .todos: AgendaTodoList(items: store.openTodos, row: configuredItem)
        default:
            AgendaPerspectiveContent(
                option: option, groups: store.agendaGroups(for: option),
                deadlines: option == .dashboard ? store.upcomingDeadlines() : [],
                overdue: option == .dashboard ? store.overdueItems : [],
                row: configuredItem
            )
        }
    }

    private func configuredItem(_ item: OrgItem) -> some View {
        let canonical = store.item(withID: item.id) ?? item
        return OrgItemRow(item: item, onToggle: { toggle(item) }, onOpen: {
            editorItem = canonical
        }, onReschedule: { reschedulingItem = canonical }, onShowInFile: {
            showInFile(item)
        }, dragItem: canonical, topPadding: mode == .agenda ? 4.5 : 9,
           bottomPadding: mode == .agenda ? 3.5 : 9,
           tagSpacing: mode == .agenda ? 2 : 6,
           allowsSwipeActions: mode != .calendar,
           revealedItemID: $revealedItemID)
    }

    private func showInFile(_ item: OrgItem) {
        revealedItemID = nil
        onShowInFile(item)
    }

    private func toggle(_ item: OrgItem) {
        withAnimation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion)) {
            let label = item.state.isTerminal ? String(localized: "Task reopened")
                : (item.isRepeatingEvent ? String(localized: "Occurrence completed")
                   : (item.kind == .habit && item.recurrence != nil ? String(localized: "Habit completed") : String(localized: "Task completed")))
            let change = store.gestureChange(for: item, label: label) {
                store.toggleDone(item)
            }
            if let change { gestureUndo = change }
        }
        if store.operationError != nil { showsCompletionError = true }
    }

    private func reschedule(_ item: OrgItem, to date: Date) {
        if let change = store.reschedule(item, to: date) { gestureUndo = change }
        if store.operationError != nil { showsCompletionError = true }
    }
}
