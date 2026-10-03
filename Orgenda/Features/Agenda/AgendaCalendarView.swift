import SwiftUI

struct AgendaCalendarView<Row: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orgendaCalendarMinimumDensity) private var minimumDensity
    @Bindable var store: WorkspaceStore
    let isActive: Bool
    let onCapture: (Date?) -> Void
    let onReschedule: (OrgItem, Date) -> Void
    let onToggle: (OrgItem) -> Void
    let onOpen: (OrgItem) -> Void
    let onShowInFile: (OrgItem) -> Void
    let onShowOverdue: () -> Void
    @ViewBuilder let row: (OrgItem) -> Row
    @State private var density: OrgendaCalendar.Density = .week
    @State private var timelineAnchor = Date.now.startOfDay
    /// Precomputed (key, date) pairs: rebuilding 396 calendar dates and day
    /// keys on every body evaluation was the agenda's main scroll cost.
    @State private var timelineDays: [AgendaDay] = AgendaDay.days(around: Date.now.startOfDay)
    @State private var timelineScrollRequest = 0
    @State private var timelineTopVisibleDayKey: String?
    @State private var timelineScrollSelection: Date?
    @State private var isScrollingTimeline = false
    @State private var calendarPage: CalendarPage = .agenda
    @State private var journalCapture: JournalCapture?
    @State private var journalScrollPosition = ScrollPosition(y: 0)

    private enum CalendarPage: Hashable {
        case agenda, journal
    }

    private struct JournalCapture: Identifiable {
        let date: Date
        var id: Date { date }
    }


    var body: some View {
        GeometryReader { geometry in
            let usesColumns = UIDevice.current.userInterfaceIdiom == .pad
                && minimumDensity == .month
                && geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
            calendarLayout(usesColumns: usesColumns, availableSize: geometry.size)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.layout")
            .accessibilityValue(usesColumns ? "Columns" : "Stacked")
            .onChange(of: usesColumns) { _, _ in
                // AnyLayout keeps the pages alive while resizing. Re-anchor
                // the timeline to the selected day after its width changes.
                timelineScrollSelection = nil
                timelineScrollRequest &+= 1
            }
        }
        .sheet(item: $journalCapture) { capture in
            JournalComposer(store: store, date: capture.date)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: dynamicTypeSize.isAccessibilitySize) { _, usesAccessibilityText in
            // Reserve room for the agenda on entry to larger text sizes.
            // Subsequent manual Month/Year choices remain under user control.
            if usesAccessibilityText {
                density = minimumDensity
            }
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            // Larger section headers change timeline geometry; keep the selected
            // day in view instead of leaving the same obsolete pixel offset.
            timelineScrollSelection = nil
            timelineScrollRequest &+= 1
        }
    }

    @ViewBuilder
    private func calendarLayout(usesColumns: Bool, availableSize: CGSize) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            AgendaCalendarTabletLayout(usesColumns: usesColumns, availableSize: availableSize) {
                calendarPanel
            } detail: {
                contentPanel(usesColumns: usesColumns)
            }
        } else {
            VStack(spacing: 0) {
                calendarPanel
                contentPanel(usesColumns: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var calendarPanel: some View {
        calendar
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.datePanel")
    }

    private func contentPanel(usesColumns: Bool) -> some View {
        VStack(spacing: 0) {
            if usesColumns {
                Picker("Calendar", selection: $calendarPage) {
                    Text("Agenda").tag(CalendarPage.agenda)
                    Text("Journal").tag(CalendarPage.journal)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("calendar.content.picker")
            }
            calendarPages
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.contentPanel")
    }

    private var calendar: some View {
        OrgendaCalendar(
            selectedDate: $store.selectedDate,
            density: $density,
            markedDates: store.markedAgendaDays,
            showsNavigationControls: isActive,
            controlsInHeader: true,
            onCapture: {
                if calendarPage == .journal {
                    journalCapture = JournalCapture(date: store.selectedDate)
                } else {
                    onCapture(store.selectedDate)
                }
            },
            captureLabel: calendarPage == .journal ? "New journal entry" : "New task",
            onScheduleTask: { transfer, date in onReschedule(transfer.item, date) },
            onReturnToday: {
                timelineScrollSelection = nil
                timelineScrollRequest &+= 1
            }
        )
    }

    private var calendarPages: some View {
        let journalEntries = store.journal(on: store.selectedDate)
        return TabView(selection: $calendarPage) {
            agendaTimeline
                .tag(CalendarPage.agenda)
                .accessibilityHidden(calendarPage != .agenda)

            ScrollView {
                JournalDayContent(entries: journalEntries) {
                    journalCapture = JournalCapture(date: store.selectedDate)
                }
                .padding(.horizontal, 20)
                .padding(.top, journalEntries.isEmpty ? 0 : 16)
                .padding(.bottom, journalEntries.isEmpty ? 0 : 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(journalEntries.isEmpty ? .center : .top, for: .alignment)
            // Keep page identity stable as agenda scrolling selects dates.
            // Replacing a page here rebuilds the pager during deceleration.
            .scrollPosition($journalScrollPosition)
            .onChange(of: store.selectedDate) { _, _ in
                journalScrollPosition.scrollTo(y: 0)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .accessibilityIdentifier("calendar.journal.timeline")
            .accessibilityValue(OrgendaDatePresentation.relativeDate(store.selectedDate))
            .tag(CalendarPage.journal)
            .accessibilityHidden(calendarPage != .journal)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityAction(named: Text("Agenda")) { calendarPage = .agenda }
        .accessibilityAction(named: Text("Journal")) { calendarPage = .journal }
        .onChange(of: calendarPage) { _, _ in
            isScrollingTimeline = false
        }
    }

    private var agendaTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(timelineDays) { day in
                        Section {
                            // A recurring item keeps its source ID across days.
                            // Give each day a layout boundary so LazyVStack does
                            // not flatten those occurrences into duplicate rows.
                            VStack(alignment: .leading, spacing: 4) {
                                AgendaDayContent(
                                    date: day.date, dayItems: store.items(on: day.date),
                                    overdueCount: store.overdueCount,
                                    onToggle: onToggle, onOpen: onOpen,
                                    onShowInFile: onShowInFile, onShowOverdue: onShowOverdue,
                                    row: row
                                )
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        } header: {
                            AgendaDayHeader(date: day.date, count: store.items(on: day.date).count)
                        }
                        .id(day.key)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .swipeActionsContainer()
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
            .task(id: "\(store.selectedDate.timeIntervalSince1970)-\(timelineScrollRequest)-\(calendarPage)") {
                guard calendarPage == .agenda else { return }
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
                guard !Task.isCancelled, !isScrollingTimeline, calendarPage == .agenda else { return }
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

    private func updateTopVisibleTimelineDay(from visibleDayKeys: [String]) {
        let visibleDayKeys = Set(visibleDayKeys)
        timelineTopVisibleDayKey = timelineDays.first(where: { visibleDayKeys.contains($0.key) })?.key
        selectTopTimelineDay()
    }

    private func selectTopTimelineDay() {
        guard isActive, calendarPage == .agenda, isScrollingTimeline,
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

}

/// Keep the calendar's intrinsic height intact. A short tablet window scrolls
/// the whole layout instead of cutting the month off above a pinned timeline.
private struct AgendaCalendarTabletLayout<CalendarPanel: View, Detail: View>: View {
    let usesColumns: Bool
    let availableSize: CGSize
    @ViewBuilder let calendar: () -> CalendarPanel
    @ViewBuilder let detail: () -> Detail
    @State private var calendarHeight: CGFloat = 0

    var body: some View {
        // The density handle extends its touch target beyond its visible grip.
        // Keep that area clear of the agenda when the panels are stacked.
        let spacing: CGFloat = usesColumns ? 0 : 16
        let layout = usesColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: spacing))
        let detailHeight = usesColumns
            ? max(availableSize.height, calendarHeight)
            : max(240, availableSize.height - calendarHeight - spacing)
        ScrollView {
            layout {
                calendar()
                    .frame(width: usesColumns ? min(max(availableSize.width * 0.38, 364), 400) : nil)
                    // The resize grip's hit target extends 14 points beyond its
                    // layout. Include that space in the outer scroll extent.
                    .padding(.bottom, 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        calendarHeight = $0
                    }
                    .overlay(alignment: .trailing) {
                        if usesColumns {
                            Rectangle()
                                .fill(Color(uiColor: .separator))
                                .frame(width: 0.5)
                                .accessibilityHidden(true)
                        }
                    }

                // A page-style TabView needs a finite proposal inside a scroll
                // view. Leave a usable agenda viewport below the full calendar.
                detail()
                    .frame(maxWidth: .infinity)
                    .frame(height: detailHeight)
            }
            .frame(minHeight: availableSize.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
