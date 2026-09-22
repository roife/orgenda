import SwiftUI

enum OrgendaCalendarLayout {
    static let monthRowSpacing: CGFloat = 2
    static let monthRowCount = 6
    static let monthHeight = OrgendaDateLayout.dayCellHeight * CGFloat(monthRowCount)
        + monthRowSpacing * CGFloat(monthRowCount - 1)
}

struct OrgendaCalendar: View {
    enum Density: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"

        var title: String {
            switch self {
            case .week: String(localized: "Week")
            case .month: String(localized: "Month")
            case .year: String(localized: "Year")
            }
        }
    }

    private enum PageDirection {
        case backward
        case forward
    }

    @Binding var selectedDate: Date
    @Binding var density: Density
    let markedDates: Set<String>
    let onReturnToday: () -> Void
    let showsNavigationControls: Bool
    let controlsInHeader: Bool
    let onCapture: (() -> Void)?
    let onScheduleTask: ((OrgTaskTransfer, Date) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var monthLabelHeight = 18.0
    @ScaledMetric(relativeTo: .subheadline) private var dayNumberSize = OrgendaDateLayout.dayNumberSize
    @ScaledMetric(relativeTo: .footnote) private var weekdayLineHeight = OrgendaDateLayout.weekdayLineHeight
    @Namespace private var selectionNamespace
    @State private var visibleMonth: Date
    @State private var monthScrollAnchor: Date
    @State private var monthScrollPosition: Int?
    @State private var preferredDayOfMonth: Int
    @State private var isUpdatingSelectionFromMonthScroll = false
    @State private var verticalDrag: CGFloat = 0
    @State private var pageDirection: PageDirection = .forward
    @State private var pageGeneration = 0
    @State private var dropDate: Date?

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let monthPageOffsets = -240...240

    init(selectedDate: Binding<Date>, density: Binding<Density>, markedDates: Set<String>, showsNavigationControls: Bool = true,
         controlsInHeader: Bool = false, onCapture: (() -> Void)? = nil,
         onScheduleTask: ((OrgTaskTransfer, Date) -> Void)? = nil,
         onReturnToday: @escaping () -> Void = {}) {
        _selectedDate = selectedDate
        _density = density
        self.markedDates = markedDates
        self.onReturnToday = onReturnToday
        self.showsNavigationControls = showsNavigationControls
        self.controlsInHeader = controlsInHeader
        self.onCapture = onCapture
        self.onScheduleTask = onScheduleTask
        let calendar = Calendar.autoupdatingCurrent
        let initialMonth = calendar.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start
            ?? selectedDate.wrappedValue
        _visibleMonth = State(initialValue: initialMonth)
        _monthScrollAnchor = State(initialValue: initialMonth)
        _monthScrollPosition = State(initialValue: 0)
        _preferredDayOfMonth = State(initialValue: calendar.component(.day, from: selectedDate.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 6) {
            if controlsInHeader {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    calendarTitle
                    headerActions
                }
            } else {
                calendarTitle
            }
            if density != .year && !dynamicTypeSize.isAccessibilitySize {
                weekdayHeader
            }
            calendarViewport
            if let dropDate {
                Text("Schedule for \(OrgendaDatePresentation.relativeDate(dropDate))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(OrgendaTheme.accentText)
                    .accessibilityIdentifier("agenda.drop.preview")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .toolbar {
            if showsNavigationControls && !controlsInHeader {
                ToolbarItemGroup(placement: .topBarLeading) {
                    calendarTodayButton
                    calendarDensityMenu
                }
            }
        }
        .sensoryFeedback(.selection, trigger: density)
        .onChange(of: selectedDate) { _, newValue in
            if !isUpdatingSelectionFromMonthScroll {
                preferredDayOfMonth = calendar.component(.day, from: newValue)
            }

            let granularity: Calendar.Component = density == .week ? .weekOfYear : .month
            guard !calendar.isDate(newValue, equalTo: visibleMonth, toGranularity: granularity) else {
                // A week can span two months; keep the heading current without
                // paging away from that week when its selected month changes.
                if density == .week {
                    visibleMonth = newValue
                }
                return
            }
            pageDirection = newValue < visibleMonth ? .backward : .forward

            if density == .month {
                scrollToMonth(containing: newValue, animated: true)
                return
            }

            withAnimation(pageAnimation) {
                visibleMonth = newValue
                pageGeneration &+= 1
            }
        }
    }

    private var headerActions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if !isShowingToday {
                    calendarTodayButton
                        .frame(width: 44, height: 44)
                }
                calendarDensityMenu
                    .frame(width: 44, height: 44)
                if let onCapture {
                    Button(action: onCapture) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .regular))
                            .frame(width: 30, height: 30)
                    }
                    .foregroundStyle(OrgendaTheme.accentText)
                    .accessibilityLabel("New task")
                    .accessibilityIdentifier("orgenda.capture")
                }
            }
            .font(.system(size: 18, weight: .medium))
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .fixedSize()
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
    }

    @ViewBuilder
    private var calendarTitle: some View {
        if density == .year {
            Text(visibleMonth.formatted(.dateTime.year()))
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .foregroundStyle(OrgendaTheme.ink)
                .contentTransition(reduceMotion ? .opacity : .numericText(
                    value: Double(calendar.component(.year, from: visibleMonth))
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        } else {
            OrgendaDateHeading(date: selectedDate, displayedMonth: visibleMonth)
                .accessibilityIdentifier("orgenda.calendar.date.heading")
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(rotatedWeekdays.enumerated()), id: \.offset) { index, symbol in
                let weekday = (calendar.firstWeekday - 1 + index) % 7 + 1
                Text(symbol.uppercased())
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(weekday == 1 || weekday == 7 ? OrgendaTheme.weekend : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var isShowingToday: Bool {
        guard calendar.isDateInToday(selectedDate) else { return false }
        // Week cells follow selectedDate; visibleMonth only supplies their heading.
        if density == .week { return true }
        return calendar.isDate(visibleMonth, equalTo: .now,
                               toGranularity: density == .year ? .year : .month)
    }

    // Keep this action here so returning Today also resets calendar paging.
    @ViewBuilder
    private var calendarTodayButton: some View {
        if !isShowingToday {
            Button {
                selectDay(.now)
                onReturnToday()
                // Year paging can leave the selected date unchanged.
                if density == .year {
                    withAnimation(OrgendaMotion.geometryAnimation(.content, reduceMotion: reduceMotion)) {
                        visibleMonth = .now
                        pageGeneration &+= 1
                    }
                }
            } label: {
                Label("Today", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
                    .frame(width: controlsInHeader ? 30 : nil, height: controlsInHeader ? 30 : nil)
            }
            .tint(OrgendaTheme.accentText)
            .accessibilityLabel("Today")
            .accessibilityIdentifier("orgenda.calendar.today")
        }
    }

    private var calendarDensityMenu: some View {
        Menu {
            Picker("Calendar view", selection: Binding(
                get: { density },
                set: { setDensity($0) }
            )) {
                ForEach(Density.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
        } label: {
            Label("Calendar view", systemImage: "calendar")
                .labelStyle(.iconOnly)
                .frame(width: controlsInHeader ? 30 : nil, height: controlsInHeader ? 30 : nil)
        }
        .tint(OrgendaTheme.accentText)
        .accessibilityLabel("Calendar view")
        .accessibilityValue(density.title)
        .accessibilityIdentifier("orgenda.calendar.density")
    }

    @ViewBuilder
    private var calendarViewport: some View {
        if density == .month {
            monthPager
                .frame(maxWidth: .infinity)
                .frame(height: calendarHeight, alignment: .top)
                .clipped()
                .transition(densityTransition)
        } else {
            ZStack(alignment: .top) {
                nonMonthCalendarBody
                    .frame(maxWidth: .infinity, alignment: .top)
                    .id(pageGeneration)
                    .transition(pageTransition)
                    .offset(y: reduceMotion ? 0 : verticalDrag)
            }
            .frame(maxWidth: .infinity)
            .frame(height: calendarHeight, alignment: .top)
            .contentShape(Rectangle())
            .simultaneousGesture(verticalPageSwipe)
            .clipped()
        }
    }

    private var monthPager: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(monthPageOffsets, id: \.self) { offset in
                    let pageMonth = month(at: offset)
                    monthGrid(
                        for: pageMonth,
                        exposesAccessibility: monthScrollPosition == offset
                    )
                    .id(pageMonth)
                    // Match the scroll viewport exactly, including pixel
                    // rounding at scaled text sizes, so page offsets stay aligned.
                    .containerRelativeFrame(.vertical, alignment: .top)
                    .clipped()
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(monthScrollPosition != offset)
                    .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $monthScrollPosition, anchor: .top)
        .accessibilityLabel("Calendar months")
        .accessibilityValue(visibleMonth.formatted(.dateTime.month(.wide).year()))
        .accessibilityHint("Swipe up or down to change months")
        .accessibilityScrollAction { edge in
            switch edge {
            case .top:
                moveVisiblePage(by: -1)
            case .bottom:
                moveVisiblePage(by: 1)
            default:
                break
            }
        }
        .accessibilityIdentifier("orgenda.calendar.months")
        .onChange(of: monthScrollPosition) { _, offset in
            if let offset {
                updateVisibleMonth(month(at: offset))
            }
        }
    }

    @ViewBuilder
    private func monthGrid(for month: Date, exposesAccessibility: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            dateStrip(
                dates: daysInMonth(for: month),
                displayedIn: month,
                exposesAccessibility: exposesAccessibility
            )
        } else {
            LazyVGrid(columns: columns, spacing: OrgendaCalendarLayout.monthRowSpacing) {
                ForEach(daysInMonthGrid(for: month), id: \.self) { date in
                    dayCell(
                        date,
                        displayedIn: month,
                        accessibilityHidden: !exposesAccessibility
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var nonMonthCalendarBody: some View {
        switch density {
        case .week:
            if dynamicTypeSize.isAccessibilitySize {
                dateStrip(dates: daysInSelectedWeek, displayedIn: visibleMonth, exposesAccessibility: true)
                    .transition(densityTransition)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(daysInSelectedWeek, id: \.self) {
                        dayCell(
                            $0,
                            displayedIn: visibleMonth,
                            accessibilityHidden: false
                        )
                    }
                }
                .frame(height: OrgendaDateLayout.dayCellHeight)
                .transition(densityTransition)
            }
        case .year:
            yearGrid
                .frame(height: yearHeight, alignment: .top)
                .transition(densityTransition)
        case .month:
            EmptyView()
        }
    }

    // At accessibility sizes, scrolling gives dates enough room to use the
    // requested font size. Vertical paging still changes the week or month.
    private func dateStrip(dates: [Date], displayedIn month: Date, exposesAccessibility: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(dates, id: \.self) { date in
                        dayCell(date, displayedIn: month, accessibilityHidden: !exposesAccessibility)
                            .frame(width: accessibleDayDiameter + 12)
                            .id(date.orgendaDayKey)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .accessibilityHidden(!exposesAccessibility)
            .accessibilityIdentifier(exposesAccessibility
                ? "orgenda.calendar.dates"
                : "orgenda.calendar.dates.offscreen.\(month.orgendaDayKey)")
            .onChange(of: selectedDate, initial: true) { _, date in
                guard dates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) else { return }
                proxy.scrollTo(date.orgendaDayKey, anchor: .center)
            }
        }
        .frame(height: accessibleDateStripHeight)
        .accessibilityHidden(!exposesAccessibility)
    }

    private var yearGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 10) {
            ForEach(0..<12, id: \.self) { offset in
                let month = monthInVisibleYear(offset + 1)
                let isSelectedMonth = calendar.isDate(month, equalTo: selectedDate, toGranularity: .month)
                Button {
                    selectMonth(month)
                } label: {
                    VStack(spacing: 6) {
                        Text(month.formatted(.dateTime.month(.abbreviated)))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !dynamicTypeSize.isAccessibilitySize {
                            MiniMonth(
                                month: month,
                                selectedDate: selectedDate,
                                selectionID: selectionGeometryID,
                                selectionNamespace: selectionNamespace,
                                reduceMotion: reduceMotion
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: yearRowHeight)
                    .background {
                        if dynamicTypeSize.isAccessibilitySize && isSelectedMonth {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(OrgendaTheme.accentSoft)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
                .accessibilityHint("Shows this month")
                .accessibilityAddTraits(isSelectedMonth ? .isSelected : [])
            }
        }
    }

    private func dayCell(
        _ date: Date,
        displayedIn month: Date,
        accessibilityHidden: Bool
    ) -> some View {
        let inVisibleMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let inSelectionScope = density == .week || inVisibleMonth
        let selected = inSelectionScope && calendar.isDate(date, inSameDayAs: selectedDate)
        let today = inSelectionScope && calendar.isDateInToday(date)
        let isMarked = markedDates.contains(date.orgendaDayKey)

        return OrgendaDateButton(
            date: date,
            isSelected: selected,
            isToday: today,
            isDimmed: !inVisibleMonth,
            showsWeekday: dynamicTypeSize.isAccessibilitySize,
            scalesForAccessibility: true,
            eventMarker: isMarked,
            selection: .init(id: selectionGeometryID(for: month), namespace: selectionNamespace)
        ) {
            selectDay(date)
        }
        .accessibilityValue(dayAccessibilityValue(for: date, isMarked: isMarked))
        .accessibilityHidden(accessibilityHidden)
        .accessibilityIdentifier("orgenda.calendar.day.\(date.orgendaDayKey)")
        .overlay {
            if dropDate == date {
                RoundedRectangle(cornerRadius: 10).stroke(OrgendaTheme.accent, lineWidth: 3)
                    .background(OrgendaTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: OrgTaskTransfer.self) { tasks, _ in
            dropDate = nil
            guard onScheduleTask != nil, !accessibilityHidden,
                  tasks.count == 1, let task = tasks.first else { return false }
            onScheduleTask?(task, date)
            return true
        } isTargeted: { targeted in
            guard onScheduleTask != nil, !accessibilityHidden else { return }
            if targeted { dropDate = date }
            else if dropDate == date { dropDate = nil }
        }
    }

    private func dayAccessibilityValue(for date: Date, isMarked: Bool) -> String {
        var values: [String] = []
        if calendar.isDateInToday(date) { values.append(String(localized: "Today")) }
        if isMarked { values.append(String(localized: "Has scheduled items")) }
        return values.joined(separator: ", ")
    }

    private var verticalPageSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !reduceMotion else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                var transaction = Transaction(animation: nil)
                transaction.isContinuous = true
                withTransaction(transaction) {
                    verticalDrag = min(max(value.translation.height * 0.18, -44), 44)
                }
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    withAnimation(pageAnimation) { verticalDrag = 0 }
                    return
                }

                let translation = value.translation.height
                let projected = value.predictedEndTranslation.height
                let directionValue = abs(projected) > abs(translation) ? projected : translation
                let shouldAdvance = abs(translation) > 36 || abs(projected) > 72

                guard shouldAdvance else {
                    withAnimation(pageAnimation) { verticalDrag = 0 }
                    return
                }

                moveVisiblePage(by: directionValue < 0 ? 1 : -1)
            }
    }

    private func setDensity(_ nextDensity: Density) {
        if nextDensity == .month {
            scrollToMonth(containing: visibleMonth, animated: false)
        }

        withAnimation(reduceMotion ? nil : densityAnimation) {
            density = nextDensity
        }
    }

    private func selectMonth(_ month: Date) {
        pageDirection = month < visibleMonth ? .backward : .forward
        scrollToMonth(containing: month, animated: false)
        withAnimation(reduceMotion ? nil : densityAnimation) {
            visibleMonth = month
            selectedDate = month
            density = .month
        }
    }

    private func selectDay(_ date: Date) {
        let date = date.startOfDay
        preferredDayOfMonth = calendar.component(.day, from: date)
        let granularity: Calendar.Component = density == .week ? .weekOfYear : .month
        let changesPage = !calendar.isDate(date, equalTo: visibleMonth, toGranularity: granularity)

        guard changesPage else {
            withAnimation(selectionAnimation) { selectedDate = date }
            return
        }

        pageDirection = date < visibleMonth ? .backward : .forward

        if density == .month {
            withAnimation(selectionAnimation) {
                selectedDate = date
            }
            return
        }

        withAnimation(pageAnimation) {
            visibleMonth = date
            selectedDate = date
            verticalDrag = 0
            pageGeneration &+= 1
        }
    }

    private func moveVisiblePage(by delta: Int) {
        pageDirection = delta < 0 ? .backward : .forward

        if density == .month {
            let currentOffset = monthScrollPosition ?? monthOffset(for: visibleMonth)
            let nextOffset = min(
                max(currentOffset + delta, monthPageOffsets.lowerBound),
                monthPageOffsets.upperBound - 1
            )
            // Month paging moves a scroll position; reduced-motion fades are
            // reserved for the week/year content transitions below.
            withAnimation(reduceMotion ? nil : pageAnimation) {
                monthScrollPosition = nextOffset
            }
            return
        }

        let component: Calendar.Component = density == .week ? .weekOfYear : .year
        let pageAnchor = density == .week ? selectedDate : visibleMonth
        let nextPage = calendar.date(byAdding: component, value: delta, to: pageAnchor) ?? pageAnchor

        withAnimation(pageAnimation) {
            visibleMonth = nextPage
            if density == .week {
                selectedDate = nextPage.startOfDay
            }
            verticalDrag = 0
            pageGeneration &+= 1
        }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .snappy(duration: 0.30)
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)
    }

    private var densityAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.22)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        let insertionEdge: Edge = pageDirection == .forward ? .bottom : .top
        let removalEdge: Edge = pageDirection == .forward ? .top : .bottom
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var densityTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    private var selectionGeometryID: String {
        "orgenda-calendar-selected-date-\(density.rawValue)-\(pageGeneration)"
    }

    private func selectionGeometryID(for month: Date) -> String {
        "\(selectionGeometryID)-\(month.orgendaDayKey)"
    }

    private var calendarHeight: CGFloat {
        switch density {
        case .week: dynamicTypeSize.isAccessibilitySize ? accessibleDateStripHeight : OrgendaDateLayout.dayCellHeight
        case .month: dynamicTypeSize.isAccessibilitySize ? accessibleDateStripHeight : OrgendaCalendarLayout.monthHeight
        case .year: yearHeight
        }
    }

    private var accessibleDayDiameter: CGFloat {
        OrgendaDateLayout.accessibleDayDiameter(numberSize: dayNumberSize)
    }

    private var accessibleDateStripHeight: CGFloat {
        accessibleDayDiameter + weekdayLineHeight + OrgendaDateLayout.eventMarkerDiameter + 14
    }

    private var yearRowHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(44, monthLabelHeight + 16) : monthLabelHeight + 78
    }

    private var yearHeight: CGFloat {
        yearRowHeight * 4 + 30
    }

    private func monthInVisibleYear(_ month: Int) -> Date {
        var components = calendar.dateComponents([.era, .year], from: visibleMonth)
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? visibleMonth
    }

    private var rotatedWeekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let index = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[index...] + symbols[..<index])
    }

    private var daysInSelectedWeek: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func daysInMonthGrid(for visibleMonth: Date) -> [Date] {
        guard
            let month = calendar.dateInterval(of: .month, for: visibleMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start)
        else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    private func daysInMonth(for month: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }

    private func month(at offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthScrollAnchor)!
    }

    private func monthOffset(for date: Date) -> Int {
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return calendar.dateComponents([.month], from: monthScrollAnchor, to: month).month ?? 0
    }

    private func scrollToMonth(containing date: Date, animated: Bool) {
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let offset = monthOffset(for: month)

        guard monthPageOffsets.contains(offset) else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                monthScrollAnchor = month
                monthScrollPosition = 0
                visibleMonth = month
            }
            return
        }

        let update = {
            monthScrollPosition = offset
            visibleMonth = month
        }

        if animated && !reduceMotion {
            withAnimation(pageAnimation, update)
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
    }

    private func updateVisibleMonth(_ month: Date) {
        guard !calendar.isDate(month, equalTo: visibleMonth, toGranularity: .month) else { return }
        pageDirection = month < visibleMonth ? .backward : .forward
        let nextSelectedDate = date(in: month, day: preferredDayOfMonth)
        isUpdatingSelectionFromMonthScroll = true

        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visibleMonth = month
                selectedDate = nextSelectedDate
            }
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                visibleMonth = month
                selectedDate = nextSelectedDate
            }
        }

        Task { @MainActor in
            await Task.yield()
            isUpdatingSelectionFromMonthScroll = false
        }
    }

    private func date(in month: Date, day preferredDay: Int) -> Date {
        guard let validDays = calendar.range(of: .day, in: .month, for: month) else {
            return month.startOfDay
        }

        var components = calendar.dateComponents([.era, .year, .month], from: month)
        components.day = min(max(preferredDay, validDays.lowerBound), validDays.upperBound - 1)
        return (calendar.date(from: components) ?? month).startOfDay
    }
}

private struct MiniMonth: View {
    let month: Date
    let selectedDate: Date
    let selectionID: String
    let selectionNamespace: Namespace.ID
    let reduceMotion: Bool

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(days, id: \.self) { date in
                let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                let selected = inMonth && calendar.isDate(date, inSameDayAs: selectedDate)

                ZStack {
                    if selected {
                        Circle()
                            .fill(Color.secondary.opacity(0.72))
                            .frame(width: 10, height: 10)
                            .modifier(
                                CalendarSelectionGeometry(
                                    id: selectionID,
                                    namespace: selectionNamespace,
                                    reduceMotion: reduceMotion
                                )
                            )
                    }

                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 9, weight: selected ? .bold : .regular))
                        .foregroundStyle(inMonth ? (selected ? Color.white : Color.primary) : Color.clear)
                }
                .frame(height: 11)
            }
        }
    }

    private var days: [Date] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)
        else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }
}

private struct CalendarSelectionGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.opacity)
        } else {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center
            )
        }
    }
}
