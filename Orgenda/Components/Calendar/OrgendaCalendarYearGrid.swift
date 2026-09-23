import SwiftUI

struct OrgendaCalendarYearGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let year: Date
    let selectedDate: Date
    let selectionID: String
    let selectionNamespace: Namespace.ID
    let reduceMotion: Bool
    let yearRowHeight: CGFloat
    let monthLabelHeight: CGFloat
    let exposesAccessibility: Bool
    var hiddenMonth: Date? = nil
    let onSelectMonth: (Date) -> Void
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { column in
                        yearMonthButton(
                            for: OrgCalendarDates(calendar: calendar).monthInYear(row * 3 + column + 1, year: year)
                        )
                    }
                }
            }
        }
    }

    private func yearMonthButton(for month: Date) -> some View {
        let isSelectedMonth = calendar.isDate(month, equalTo: selectedDate, toGranularity: .month)
        return Button {
            onSelectMonth(month)
        } label: {
            VStack(spacing: 6) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: monthLabelHeight)
                if !dynamicTypeSize.isAccessibilitySize {
                    MiniMonth(
                        month: month,
                        selectedDate: selectedDate,
                        selectionID: "year-\(selectionID)-\(month.orgendaDayKey)",
                        selectionNamespace: selectionNamespace,
                        reduceMotion: reduceMotion
                    )
                    .opacity(hiddenMonth.map { calendar.isDate($0, equalTo: month, toGranularity: .month) } == true ? 0 : 1)
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
        .accessibilityHidden(!exposesAccessibility)
        .accessibilityIdentifier("orgenda.calendar.month.\(month.orgendaDayKey)")
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
            ForEach(OrgCalendarDates(calendar: calendar).daysInMonthGrid(for: month), id: \.self) { date in
                let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                let selected = inMonth && calendar.isDate(date, inSameDayAs: selectedDate)

                ZStack {
                    if selected {
                        Circle()
                            .fill(OrgendaTheme.accent)
                            .frame(width: OrgendaCalendarLayout.miniMonthSelectionDiameter,
                                   height: OrgendaCalendarLayout.miniMonthSelectionDiameter)
                            .modifier(
                                CalendarSelectionGeometry(
                                    id: selectionID,
                                    namespace: selectionNamespace,
                                    reduceMotion: reduceMotion
                                )
                            )
                    }

                    Text(String(calendar.component(.day, from: date)))
                        .font(.system(size: 9, weight: selected ? .semibold : .regular, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .foregroundStyle(inMonth ? (selected ? Color.white : Color.primary) : Color.clear)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 11)
            }
        }
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
