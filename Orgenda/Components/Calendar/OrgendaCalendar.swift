import SwiftUI

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
    let captureLabel: LocalizedStringKey
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
    @State private var yearScrollAnchor: Date
    @State private var yearScrollPosition: Int?
    @State private var preferredDayOfMonth: Int
    @State private var isUpdatingSelectionFromMonthScroll = false
    @State private var verticalDrag: CGFloat = 0
    @State private var pageDirection: PageDirection = .forward
    @State private var pageGeneration = 0
    @State private var dropDate: Date?
    @State private var densityDragOrigin: CGFloat?
    @State private var densityDragPosition: CGFloat?
    @GestureState private var isDraggingDensity = false

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let monthPageOffsets = -240...240
    private let yearPageOffsets = -200...200

    init(selectedDate: Binding<Date>, density: Binding<Density>, markedDates: Set<String>, showsNavigationControls: Bool = true,
         controlsInHeader: Bool = false, onCapture: (() -> Void)? = nil,
         captureLabel: LocalizedStringKey = "New task",
         onScheduleTask: ((OrgTaskTransfer, Date) -> Void)? = nil,
         onReturnToday: @escaping () -> Void = {}) {
        _selectedDate = selectedDate
        _density = density
        self.markedDates = markedDates
        self.onReturnToday = onReturnToday
        self.showsNavigationControls = showsNavigationControls
        self.controlsInHeader = controlsInHeader
        self.onCapture = onCapture
        self.captureLabel = captureLabel
        self.onScheduleTask = onScheduleTask
        let calendar = Calendar.autoupdatingCurrent
        let initialMonth = calendar.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start
            ?? selectedDate.wrappedValue
        _visibleMonth = State(initialValue: initialMonth)
        _monthScrollAnchor = State(initialValue: initialMonth)
        _monthScrollPosition = State(initialValue: 0)
        _yearScrollAnchor = State(initialValue: calendar.dateInterval(of: .year, for: initialMonth)?.start ?? initialMonth)
        _yearScrollPosition = State(initialValue: 0)
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
            Group {
                if let position = densityDragPosition {
                    OrgendaCalendarResizePreview(position: position, content: calendarDragPreview)
                } else {
                    VStack(spacing: 6) {
                        if density != .year && !dynamicTypeSize.isAccessibilitySize {
                            weekdayHeader
                                .frame(height: weekdayLineHeight)
                        }
                        calendarViewport
                    }
                }
            }
            .frame(height: calendarSelectionHeight, alignment: .top)
            .clipped()
            .allowsHitTesting(densityDragPosition == nil)
            calendarDensityHandle
                .padding(.top, -4)
            if let dropDate {
                Text("Schedule for \(OrgendaDatePresentation.relativeDate(dropDate))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(OrgendaTheme.accentText)
                    .accessibilityIdentifier("agenda.drop.preview")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .toolbar {
            if showsNavigationControls && !controlsInHeader {
                ToolbarItemGroup(placement: .topBarLeading) {
                    calendarTodayButton
                }
            }
        }
        .sensoryFeedback(.selection, trigger: displayedDensity)
        .onChange(of: isDraggingDensity) { _, isDragging in
            // GestureState also resets when the system cancels a drag.
            if !isDragging { finishDensityDrag() }
        }
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
            if density == .year {
                scrollToYear(containing: newValue, animated: true)
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
                if let onCapture {
                    Button(action: onCapture) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .regular))
                            .frame(width: 30, height: 30)
                    }
                    .foregroundStyle(OrgendaTheme.accentText)
                    .accessibilityLabel(captureLabel)
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

    private var calendarTitle: some View {
        // Keep the heading's height stable as the handle crosses into Year.
        ZStack(alignment: .leading) {
            OrgendaDateHeading(date: selectedDate, displayedMonth: visibleMonth)
                .opacity(1 - yearTitleProgress)
                .offset(y: reduceMotion ? 0 : -6 * yearTitleProgress)
                .accessibilityHidden(displayedDensity == .year)
                .accessibilityIdentifier("orgenda.calendar.date.heading")
            Text(visibleMonth.formatted(.dateTime.year()))
                .font(dynamicTypeSize.isAccessibilitySize ? .subheadline.bold() : .largeTitle.bold())
                .fontDesign(.rounded)
                .foregroundStyle(OrgendaTheme.ink)
                .contentTransition(reduceMotion ? .opacity : .numericText(
                    value: Double(calendar.component(.year, from: visibleMonth))
                ))
                .opacity(yearTitleProgress)
                .offset(y: reduceMotion ? 0 : 6 * (1 - yearTitleProgress))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(displayedDensity != .year)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var yearTitleProgress: CGFloat {
        guard let position = densityDragPosition else { return density == .year ? 1 : 0 }
        let month = sizing.dragPosition(for: .month)
        return min(max((position - month) / (sizing.dragPosition(for: .year) - month), 0), 1)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(dates.rotatedWeekdays.enumerated()), id: \.offset) { index, symbol in
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
                    scrollToYear(containing: .now, animated: true)
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

    private var calendarDensityHandle: some View {
        Capsule()
            .fill(densityDragPosition == nil ? Color.secondary.opacity(0.35) : OrgendaTheme.accent)
            .frame(width: 36, height: 5)
            .padding(.top, 2)
            .padding(.bottom, 9)
            .frame(width: 96)
            .contentShape(.interaction, Rectangle().inset(by: -14))
            .gesture(densityResizeGesture)
            .accessibilityElement()
            .accessibilityLabel("Calendar view")
            .accessibilityValue(displayedDensity.title)
            .accessibilityHint("Drag up or down to switch between week, month, and year")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    setDensity(density == .week ? .month : .year)
                case .decrement:
                    setDensity(density == .year ? .month : .week)
                @unknown default:
                    break
                }
            }
            .accessibilityIdentifier("orgenda.calendar.density.handle")
            .frame(maxWidth: .infinity)
    }

    private var densityResizeGesture: some Gesture {
        // Global translation stays stable while the handle moves with the calendar.
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($isDraggingDensity) { _, state, _ in state = true }
            .onChanged { value in
                guard densityDragOrigin != nil || abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                let origin = densityDragOrigin ?? densityDragPosition ?? sizing.dragPosition(for: density)
                let position = min(max(origin + value.translation.height, 0), sizing.dragPosition(for: .year))
                var transaction = Transaction(animation: nil)
                transaction.isContinuous = true
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    densityDragOrigin = origin
                    densityDragPosition = position
                }
            }
            .onEnded { _ in finishDensityDrag() }
    }

    private func finishDensityDrag() {
        guard densityDragOrigin != nil, let position = densityDragPosition else { return }
        densityDragOrigin = nil
        let target = sizing.density(at: position)
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) {
            densityDragPosition = sizing.dragPosition(for: target)
        } completion: {
            guard densityDragOrigin == nil, !isDraggingDensity,
                  densityDragPosition == sizing.dragPosition(for: target) else { return }
            setDensity(target, animated: false)
            densityDragPosition = nil
        }
    }

    private var displayedDensity: Density {
        densityDragPosition.map { sizing.density(at: $0) } ?? density
    }

    private func calendarDragPreview(at position: CGFloat) -> some View {
        OrgendaCalendarResizeContent(
            position: position, visibleMonth: visibleMonth,
            selectedWeekOffset: selectedWeekOffset, sizing: sizing,
            monthGrid: { monthGrid(for: visibleMonth, exposesAccessibility: false) },
            yearGrid: { yearGrid(for: visibleMonth, exposesAccessibility: false) },
            weekdayHeader: { weekdayHeader },
            accessibleDays: { isWeek in
                dayGrid(
                    dates: isWeek ? dates.daysInWeek(containing: selectedDate) : dates.daysInMonth(for: visibleMonth),
                    displayedIn: visibleMonth, exposesAccessibility: false
                )
            }
        )
    }

    private var selectedWeekOffset: CGFloat {
        guard let monthStart = calendar.dateInterval(of: .month, for: visibleMonth)?.start,
              let firstDate = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start,
              let selectedWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return 0 }
        let days = calendar.dateComponents([.day], from: firstDate, to: selectedWeek).day ?? 0
        return CGFloat(min(max(days / 7, 0), OrgendaCalendarLayout.monthRowCount - 1))
            * (OrgendaDateLayout.dayCellHeight + OrgendaCalendarLayout.monthRowSpacing)
    }

    @ViewBuilder
    private var calendarViewport: some View {
        if density == .month {
            monthPager
                .frame(maxWidth: .infinity)
                .frame(height: sizing.calendarHeight(for: .month), alignment: .top)
                .clipped()
                .transition(densityTransition)
        } else if density == .year {
            yearPager
                .frame(maxWidth: .infinity)
                .frame(height: sizing.yearHeight, alignment: .top)
                .clipped()
                .transition(densityTransition)
        } else {
            ZStack(alignment: .top) {
                dayGrid(dates: dates.daysInWeek(containing: selectedDate), displayedIn: visibleMonth,
                        exposesAccessibility: true, isWeekLayout: true)
                    .transition(densityTransition)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .id(pageGeneration)
                    .transition(pageTransition)
                    .offset(y: reduceMotion ? 0 : verticalDrag)
            }
            .frame(maxWidth: .infinity)
            .frame(height: sizing.calendarHeight(for: .week), alignment: .top)
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

    private var yearPager: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(yearPageOffsets, id: \.self) { offset in
                    let pageYear = year(at: offset)
                    yearGrid(for: pageYear, exposesAccessibility: yearScrollPosition == offset)
                        .id(pageYear)
                        .containerRelativeFrame(.vertical, alignment: .top)
                        .clipped()
                        .accessibilityElement(children: .contain)
                        .accessibilityHidden(yearScrollPosition != offset)
                        .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $yearScrollPosition, anchor: .top)
        .accessibilityLabel("Calendar years")
        .accessibilityValue(visibleMonth.formatted(.dateTime.year()))
        .accessibilityHint("Swipe up or down to change years")
        .accessibilityScrollAction { edge in
            switch edge {
            case .top: moveVisiblePage(by: -1)
            case .bottom: moveVisiblePage(by: 1)
            default: break
            }
        }
        .accessibilityIdentifier("orgenda.calendar.years")
        .onChange(of: yearScrollPosition) { _, offset in
            guard let offset else { return }
            let nextYear = year(at: offset)
            let delta = calendar.component(.year, from: nextYear) - calendar.component(.year, from: visibleMonth)
            guard delta != 0 else { return }
            // Browsing years keeps the selected day and the month to return to.
            withAnimation(selectionAnimation) {
                visibleMonth = calendar.date(byAdding: .year, value: delta, to: visibleMonth) ?? nextYear
            }
        }
    }

    private func monthGrid(for month: Date, exposesAccessibility: Bool) -> some View {
        dayGrid(
            dates: dynamicTypeSize.isAccessibilitySize
                ? dates.daysInMonth(for: month) : dates.daysInMonthGrid(for: month),
            displayedIn: month, exposesAccessibility: exposesAccessibility
        )
    }

    private func dayGrid(dates: [Date], displayedIn month: Date, exposesAccessibility: Bool,
                         isWeekLayout: Bool = false) -> some View {
        OrgendaCalendarDayGrid(
            dates: dates, month: month, selectedDate: selectedDate, isWeekLayout: isWeekLayout,
            allowsAdjacentMonthSelection: density == .week,
            markedDates: markedDates, selectionID: "\(selectionGeometryID)-\(month.orgendaDayKey)",
            selectionNamespace: selectionNamespace, exposesAccessibility: exposesAccessibility,
            accessibleDayDiameter: sizing.accessibleDayDiameter,
            accessibleDateStripHeight: sizing.accessibleDateStripHeight,
            dropDate: $dropDate, onSelectDay: selectDay, onScheduleTask: onScheduleTask
        )
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

    private func setDensity(_ nextDensity: Density, animated: Bool = true) {
        guard nextDensity != density else { return }
        if nextDensity == .month {
            scrollToMonth(containing: visibleMonth, animated: false)
        } else if nextDensity == .year {
            scrollToYear(containing: visibleMonth, animated: false)
        }

        withAnimation(animated && !reduceMotion ? densityAnimation : nil) {
            if nextDensity == .week { visibleMonth = selectedDate }
            verticalDrag = 0
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

        if density == .year {
            let currentOffset = yearScrollPosition ?? yearOffset(for: visibleMonth)
            withAnimation(reduceMotion ? nil : pageAnimation) {
                yearScrollPosition = min(max(currentOffset + delta, yearPageOffsets.lowerBound), yearPageOffsets.upperBound - 1)
            }
            return
        }

        if density == .month {
            let currentOffset = monthScrollPosition ?? monthOffset(for: visibleMonth)
            let nextOffset = min(
                max(currentOffset + delta, monthPageOffsets.lowerBound),
                monthPageOffsets.upperBound - 1
            )
            // Month paging moves a scroll position; reduced-motion fades are
            // reserved for the week content transitions below.
            withAnimation(reduceMotion ? nil : pageAnimation) {
                monthScrollPosition = nextOffset
            }
            return
        }

        let nextPage = calendar.date(byAdding: .weekOfYear, value: delta, to: selectedDate) ?? selectedDate

        withAnimation(pageAnimation) {
            visibleMonth = nextPage
            selectedDate = nextPage.startOfDay
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

    private var sizing: OrgendaCalendarSizing {
        OrgendaCalendarSizing(
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize,
            dayNumberSize: dayNumberSize, weekdayLineHeight: weekdayLineHeight,
            monthLabelHeight: monthLabelHeight
        )
    }

    private var calendarSelectionHeight: CGFloat {
        guard let position = densityDragPosition else { return sizing.selectionHeight(for: density) }
        return sizing.selectionHeight(at: position)
    }

    private var dates: OrgCalendarDates { OrgCalendarDates(calendar: calendar) }

    private func yearGrid(for year: Date, exposesAccessibility: Bool) -> some View {
        OrgendaCalendarYearGrid(
            year: year, selectedDate: selectedDate, selectionID: selectionGeometryID,
            selectionNamespace: selectionNamespace, reduceMotion: reduceMotion,
            yearRowHeight: sizing.yearRowHeight, exposesAccessibility: exposesAccessibility,
            onSelectMonth: selectMonth
        )
    }

    private func year(at offset: Int) -> Date {
        calendar.date(byAdding: .year, value: offset, to: yearScrollAnchor)!
    }

    private func yearOffset(for date: Date) -> Int {
        let year = calendar.dateInterval(of: .year, for: date)?.start ?? date
        return calendar.dateComponents([.year], from: yearScrollAnchor, to: year).year ?? 0
    }

    private func scrollToYear(containing date: Date, animated: Bool) {
        let offset = yearOffset(for: date)
        if !yearPageOffsets.dropLast().contains(offset) {
            yearScrollAnchor = calendar.dateInterval(of: .year, for: date)?.start ?? date
            yearScrollPosition = 0
            visibleMonth = date
            return
        }
        withAnimation(animated && !reduceMotion ? pageAnimation : nil) {
            yearScrollPosition = offset
            visibleMonth = date
        }
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
        let nextSelectedDate = dates.date(in: month, day: preferredDayOfMonth)
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


}
