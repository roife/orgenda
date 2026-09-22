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
    @State private var density: OrgendaCalendar.Density = .week
    @State private var perspective: Perspective
    @State private var visitedPerspectives: Set<Perspective>
    @State private var lastWorkspaceConfiguration: Bool?
    @State private var editorItem: OrgItem?
    @State private var timelineAnchor = Date.now.startOfDay
    /// Precomputed (key, date) pairs: rebuilding 396 calendar dates and day
    /// keys on every body evaluation was the agenda's main scroll cost.
    @State private var timelineDays: [AgendaDay] = AgendaDay.days(around: Date.now.startOfDay)
    @State private var timelineScrollRequest = 0
    @State private var timelineTopVisibleDayKey: String?
    @State private var timelineScrollSelection: Date?
    @State private var isScrollingTimeline = false
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
        .onChange(of: dynamicTypeSize.isAccessibilitySize) { _, usesAccessibilityText in
            // Reserve room for the agenda on entry to larger text sizes.
            // Subsequent manual Month/Year choices remain under user control.
            if usesAccessibilityText {
                density = .week
            }
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            // Larger section headers change timeline geometry; keep the selected
            // day in view instead of leaving the same obsolete pixel offset.
            timelineScrollSelection = nil
            timelineScrollRequest &+= 1
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
                set: { selectPerspective($0) }
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
        case .agenda: agenda.clipped()
        case .overdue: overdue
        case .todos: todos
        default: configuredPerspective(option)
        }
    }

    private func configuredPerspective(_ option: Perspective) -> some View {
        let groups = store.agendaGroups(for: option)
        let deadlines = option == .dashboard ? store.upcomingDeadlines() : []
        let overdue = option == .dashboard ? store.overdueItems : []
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if groups.allSatisfy({ $0.items.isEmpty }) && deadlines.isEmpty && overdue.isEmpty {
                    ContentUnavailableView(
                        option == .dashboard ? "No items in Dashboard" : "No items",
                        systemImage: option.symbol,
                        description: Text(option == .dashboard
                            ? "Scheduled items and open tasks will appear here."
                            : "Items in this view will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else if option == .dashboard {
                    if !overdue.isEmpty {
                        configuredGroup(OrgAgendaGroup(title: String(localized: "Overdue"), items: overdue))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "Next 7 days"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("agenda.dashboard.dateScope")
                        let dates = groups.filter { $0.isDateGroup && !$0.items.isEmpty }
                        if dates.isEmpty {
                            Text(String(localized: "Nothing scheduled in the next 7 days."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(dates) { configuredGroup($0) }
                    }
                    if !deadlines.isEmpty {
                        configuredGroup(OrgAgendaGroup(title: String(localized: "Deadlines · next 3 days"), items: deadlines))
                    }
                    ForEach(groups.filter { !$0.isDateGroup && !$0.items.isEmpty }) { group in
                        configuredGroup(group)
                    }
                } else {
                    ForEach(groups) { group in
                        Text("\(group.items.count) open")
                            .font(.subheadline).foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(group.items) { item in
                                configuredItem(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground))
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("agenda.view.\(option.controlID)")
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
           revealedItemID: $revealedItemID)
    }

    private func showInFile(_ item: OrgItem) {
        revealedItemID = nil
        onShowInFile(item)
    }

    private func configuredGroup(_ group: OrgAgendaGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if group.state == nil {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title).font(.headline)
                    Spacer(minLength: 8)
                    Text("\(group.items.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if group.items.isEmpty {
                Text("No items").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(group.items) { item in
                        configuredItem(item)
                    }
                }
            }
        }
    }

    private var agenda: some View {
        VStack(spacing: 0) {
            OrgendaCalendar(
                selectedDate: $store.selectedDate,
                density: $density,
                markedDates: store.markedAgendaDays,
                showsNavigationControls: perspective == .agenda,
                controlsInHeader: true,
                onCapture: { onCapture(store.selectedDate) },
                onScheduleTask: { transfer, date in reschedule(transfer.item, to: date) },
                onReturnToday: {
                    timelineScrollSelection = nil
                    timelineScrollRequest &+= 1
                }
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                        ForEach(timelineDays) { day in
                            Section {
                                dayContents(day.date)
                            } header: {
                                dayHeader(day.date)
                            }
                            .id(day.key)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("orgenda.agenda.timeline")
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { visibleDayKeys in
                    updateTopVisibleTimelineDay(from: visibleDayKeys)
                }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        isScrollingTimeline = true
                        selectTopTimelineDay()
                    case .idle:
                        selectTopTimelineDay()
                        isScrollingTimeline = false
                    case .animating:
                        isScrollingTimeline = false
                    @unknown default:
                        isScrollingTimeline = false
                    }
                }
                .onChange(of: timelineAnchor) { _, anchor in
                    timelineDays = AgendaDay.days(around: anchor)
                }
                .task(id: "\(store.selectedDate.timeIntervalSince1970)-\(timelineScrollRequest)") {
                    let date = store.selectedDate
                    // A scroll-derived selection must not trigger a scroll back
                    // to the beginning of the day or interrupt deceleration.
                    guard date != timelineScrollSelection else { return }
                    timelineScrollSelection = nil
                    isScrollingTimeline = false
                    if date < timelineAnchor.adding(days: -30) || date > timelineAnchor.adding(days: 365) {
                        timelineAnchor = date.startOfDay
                    }
                    // Let a new date range enter the layout before resolving its ID.
                    await Task.yield()
                    guard !Task.isCancelled, !isScrollingTimeline else { return }
                    if reduceMotion {
                        proxy.scrollTo(date.orgendaDayKey, anchor: .top)
                    } else {
                        withAnimation(OrgendaMotion.animation(.content, reduceMotion: false)) {
                            proxy.scrollTo(date.orgendaDayKey, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func updateTopVisibleTimelineDay(from visibleDayKeys: [String]) {
        let visibleDayKeys = Set(visibleDayKeys)
        timelineTopVisibleDayKey = timelineDays.first(where: { visibleDayKeys.contains($0.key) })?.key
        selectTopTimelineDay()
    }

    private func selectTopTimelineDay() {
        guard perspective == .agenda, isScrollingTimeline,
              let key = timelineTopVisibleDayKey,
              let day = timelineDays.first(where: { $0.key == key }),
              day.date != store.selectedDate else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineScrollSelection = day.date
            store.selectedDate = day.date
        }
    }

    private var todos: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Unscheduled · \(store.openTodos.count) open")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                if store.openTodos.isEmpty {
                    ContentUnavailableView("No open tasks", systemImage: "checkmark.circle", description: Text("Tasks without a schedule appear here."))
                        .padding(.top, 80)
                } else {
                    ForEach(groupedTodos, id: \.0) { file, items in
                        VStack(alignment: .leading, spacing: 0) {
                            Label(file.replacingOccurrences(of: ".org", with: "").capitalized, systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                            ForEach(items) { item in
                                configuredItem(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("agenda.view.todos")
    }

    private var overdue: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Overdue · \(store.overdueItems.count) open")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                if store.overdueItems.isEmpty {
                    ContentUnavailableView("Nothing overdue", systemImage: "checkmark.circle", description: Text("Open items past their scheduled or deadline date appear here."))
                        .padding(.top, 80)
                } else {
                    ForEach(groupedOverdue, id: \.0) { day, items in
                        VStack(alignment: .leading, spacing: 0) {
                            Label(OrgendaDatePresentation.relativeDate(day), systemImage: "calendar.badge.exclamationmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OrgendaTheme.overdue)
                                .padding(.vertical, 8)
                            ForEach(items) { item in
                                configuredItem(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("agenda.view.overdue")
    }

    @ViewBuilder
    private func dayContents(_ date: Date) -> some View {
        let dayItems = store.items(on: date)
        let allDayEvents = dayItems.filter { $0.kind == .event && !$0.hasTime }
        let regularItems = dayItems.filter { !($0.kind == .event && !$0.hasTime) }
        if Calendar.autoupdatingCurrent.isDateInToday(date), store.overdueCount > 0 {
            Button {
                onShowOverdue()
            } label: {
                Label("\(store.overdueCount) overdue", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(OrgendaTheme.overdue, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agenda.showOverdue")
            .padding(.horizontal, 16)
            .padding(.bottom, 3)
        }

        ForEach(allDayEvents) { item in
            HStack(spacing: 2) {
                if item.canComplete {
                    Button { toggle(item) } label: {
                        Group {
                            if item.hasWorkflowState {
                                OrgWorkflowIcon(item.state)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(OrgendaTheme.accentText)
                            }
                        }
                            .font(.system(size: 21, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Complete this occurrence")
                    .accessibilityValue(item.hasWorkflowState ? "\(item.title), \(item.state.title)" : item.title)
                    .accessibilityHint("Record completion and advance to the next occurrence")
                    .accessibilityIdentifier("agenda.item.complete.\(item.id)")
                }
                Button { editorItem = store.item(withID: item.id) ?? item } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.hasWorkflowState ? item.workflowTitleColor : OrgendaTheme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(item.hasWorkflowState ? item.workflowTitleColor.opacity(0.12) : OrgendaTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.leading, item.canComplete ? -8 : 0)
            .buttonStyle(.plain)
            .contextMenu {
                if item.canComplete {
                    Button("Complete this occurrence", systemImage: "checkmark.circle") { toggle(item) }
                        .accessibilityIdentifier("agenda.item.completeOccurrence")
                }
                Button("Edit", systemImage: "pencil") {
                    editorItem = store.item(withID: item.id) ?? item
                }
                Button("Show in File", systemImage: "doc.text.magnifyingglass") { showInFile(item) }
                    .accessibilityIdentifier("agenda.item.showInFile")
            }
            .accessibilityAction(named: "Show in File") { showInFile(item) }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if dayItems.isEmpty {
            Text("No scheduled items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        } else {
            ForEach(regularItems) { item in
                configuredItem(item)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            let dateLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            dateLayout {
                Text(dayHeaderTitle(date))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isWeekend(date) ? OrgendaTheme.accent : .primary)
                Text(OrgendaDatePresentation.date(date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            let count = store.items(on: date).count
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("\(count) items")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground).opacity(0.96))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("orgenda.agenda.day.\(date.orgendaDayKey)")
    }

    private struct AgendaDay: Identifiable {
        let key: String
        let date: Date
        var id: String { key }

        static func days(around anchor: Date) -> [AgendaDay] {
            (-30...365).map { offset in
                let date = anchor.adding(days: offset)
                return AgendaDay(key: date.orgendaDayKey, date: date)
            }
        }
    }

    private var groupedTodos: [(String, [OrgItem])] {
        Dictionary(grouping: store.openTodos, by: { $0.source.file })
            .sorted { $0.key < $1.key }
    }

    private var groupedOverdue: [(Date, [OrgItem])] {
        Dictionary(grouping: store.overdueItems, by: { ($0.agendaDate ?? .distantPast).startOfDay })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private func dayHeaderTitle(_ date: Date) -> String {
        if let relative = OrgendaDatePresentation.relativeDayName(for: date) {
            return relative.uppercased()
        }
        return date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private func isWeekend(_ date: Date) -> Bool {
        Calendar.autoupdatingCurrent.isDateInWeekend(date)
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

private struct AgendaStartupSkeleton: View {
    let date: Date
    let showsCalendar: Bool
    @ScaledMetric(relativeTo: .body) private var titleHeight = 16.0
    @ScaledMetric(relativeTo: .footnote) private var detailHeight = 11.0

    var body: some View {
        VStack(spacing: 0) {
            if showsCalendar {
                OrgendaCalendar(
                    selectedDate: .constant(date),
                    density: .constant(.week),
                    markedDates: [],
                    controlsInHeader: true,
                    onCapture: {}
                )
            }
            ScrollView {
                VStack(alignment: .leading, spacing: showsCalendar ? 12 : 20) {
                    ForEach(0..<3) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                placeholder(width: section == 0 ? 148 : 112, height: titleHeight)
                                Spacer(minLength: 16)
                                placeholder(width: 18, height: detailHeight)
                            }
                            .padding(.vertical, 8)
                            ForEach(0..<(section == 0 ? 3 : 2), id: \.self) { row in
                                HStack(alignment: .top, spacing: 2) {
                                    Circle()
                                        .strokeBorder(Color(uiColor: .tertiaryLabel), lineWidth: 2)
                                        .frame(width: 21, height: 21)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 8) {
                                        placeholder(width: row.isMultiple(of: 2) ? 252 : 192, height: titleHeight)
                                        placeholder(width: row.isMultiple(of: 2) ? 120 : 88, height: detailHeight)
                                    }
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .padding(.leading, -8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, showsCalendar ? 0 : 12)
                .padding(.bottom, 24)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
        .disabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading workspace")
        .accessibilityValue(showsCalendar ? "Calendar" : "Dashboard")
        .accessibilityIdentifier("workspace.loading")
    }

    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(uiColor: .quaternaryLabel))
            .frame(maxWidth: width)
            .frame(height: height)
    }
}

private struct AgendaRescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: OrgItem
    let onSelect: (Date) -> Void
    @State private var date: Date

    init(item: OrgItem, onSelect: @escaping (Date) -> Void) {
        self.item = item
        self.onSelect = onSelect
        _date = State(initialValue: item.scheduled ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if item.hasWorkflowState { OrgWorkflowIcon(item.state) }
                        Text(item.title).foregroundStyle(item.workflowTitleColor)
                    }
                    .font(.headline)
                    Button("Today") { select(.now) }
                    Button("Tomorrow") { select(Date.now.adding(days: 1)) }
                        .accessibilityIdentifier("agenda.reschedule.tomorrow")
                }
                Section {
                    DatePicker("Scheduled date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("Changes the scheduled day. Existing times, deadlines and repeat rules are kept.")
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule", systemImage: "checkmark", role: .confirm) { select(date) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("agenda.reschedule.save")
                }
            }
        }
    }

    private func select(_ date: Date) { dismiss(); onSelect(date) }
}
