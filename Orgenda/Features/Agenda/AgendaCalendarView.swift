import SwiftUI

struct AgendaCalendarView<Row: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var store: WorkspaceStore
    let isActive: Bool
    let onCapture: (Date?) -> Void
    let onReschedule: (OrgItem, Date) -> Void
    let onToggle: (OrgItem) -> Void
    let onOpen: (OrgItem) -> Void
    let onShowInFile: (OrgItem) -> Void
    let onShowOverdue: () -> Void
    let onPageChange: () -> Void
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
        VStack(spacing: 0) {
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

            TabView(selection: $calendarPage) {
                agendaTimeline
                    .tag(CalendarPage.agenda)
                    .accessibilityHidden(calendarPage != .agenda)

                ScrollView {
                    JournalDayContent(entries: store.journal(on: store.selectedDate)) {
                        journalCapture = JournalCapture(date: store.selectedDate)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
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
                onPageChange()
                isScrollingTimeline = false
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

    private var agendaTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(timelineDays) { day in
                        Section {
                            AgendaDayContent(
                                date: day.date, dayItems: store.items(on: day.date),
                                overdueCount: store.overdueCount,
                                onToggle: onToggle, onOpen: onOpen,
                                onShowInFile: onShowInFile, onShowOverdue: onShowOverdue,
                                row: row
                            )
                        } header: {
                            AgendaDayHeader(date: day.date, count: store.items(on: day.date).count)
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
