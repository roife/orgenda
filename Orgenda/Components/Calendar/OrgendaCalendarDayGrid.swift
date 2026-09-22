import SwiftUI

struct OrgendaCalendarDayGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let dates: [Date]
    let month: Date
    let selectedDate: Date
    let isWeekLayout: Bool
    let allowsAdjacentMonthSelection: Bool
    let markedDates: Set<String>
    let selectionID: String
    let selectionNamespace: Namespace.ID
    let exposesAccessibility: Bool
    let accessibleDayDiameter: CGFloat
    let accessibleDateStripHeight: CGFloat
    @Binding var dropDate: Date?
    let onSelectDay: (Date) -> Void
    let onScheduleTask: ((OrgTaskTransfer, Date) -> Void)?

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            dateStrip
        } else {
            LazyVGrid(columns: columns, spacing: isWeekLayout ? 6 : OrgendaCalendarLayout.monthRowSpacing) {
                ForEach(dates, id: \.self) { date in
                    dayCell(date)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isWeekLayout ? nil : .infinity, alignment: .top)
            .frame(height: isWeekLayout ? OrgendaDateLayout.dayCellHeight : nil)
        }
    }

    // At accessibility sizes, scrolling gives dates enough room to use the
    // requested font size. Vertical paging still changes the week or month.
    private var dateStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(dates, id: \.self) { date in
                        dayCell(date)
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
                proxy.scrollTo(date.orgendaDayKey, anchor: .center)
            }
        }
        .frame(height: accessibleDateStripHeight)
        .accessibilityHidden(!exposesAccessibility)
    }

    private func dayCell(_ date: Date) -> some View {
        let inVisibleMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let inSelectionScope = allowsAdjacentMonthSelection || inVisibleMonth
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
            selection: .init(id: selectionID, namespace: selectionNamespace)
        ) {
            onSelectDay(date)
        }
        .accessibilityValue(dayAccessibilityValue(for: date, isMarked: isMarked))
        .accessibilityHidden(!exposesAccessibility)
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
            guard let onScheduleTask, exposesAccessibility, tasks.count == 1 else { return false }
            onScheduleTask(tasks[0], date)
            return true
        } isTargeted: { targeted in
            guard onScheduleTask != nil, exposesAccessibility else { return }
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

}
