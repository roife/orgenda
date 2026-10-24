import SwiftUI

struct OrgendaCalendarResizeContent<Month: View, Year: View, Weekdays: View, Days: View>: View {
    let position: CGFloat
    let snapshot: OrgendaCalendarResizeSnapshot
    let selectedWeekOffset: CGFloat
    let sizing: OrgendaCalendarSizing
    @ViewBuilder let monthGrid: () -> Month
    @ViewBuilder let yearGrid: () -> Year
    @ViewBuilder let weekdayHeader: () -> Weekdays
    @ViewBuilder let accessibleDays: (Bool) -> Days

    @ViewBuilder
    var body: some View {
        let monthPosition = sizing.dragPosition(for: .month)
        let height = sizing.selectionHeight(at: position)
        if position <= monthPosition {
            let progress = position / monthPosition
            VStack(spacing: OrgendaSpacing.inlineGap) {
                if !sizing.usesAccessibilityText {
                    weekdayHeader().frame(height: sizing.weekdayLineHeight)
                }
                if sizing.usesAccessibilityText {
                    accessibleDays(sizing.density(at: position) == .week)
                } else {
                    OrgendaCalendarMorphingMonth(snapshot: snapshot, progress: 0)
                        .equatable()
                        .frame(height: OrgendaCalendarLayout.monthHeight, alignment: .top)
                        .offset(y: -selectedWeekOffset * (1 - progress))
                        .frame(height: height - sizing.weekdayLineHeight - OrgendaSpacing.inlineGap, alignment: .top)
                        .clipped()
                }
            }
            .frame(height: height, alignment: .top)
            .clipped()
            .accessibilityHidden(true)
        } else {
            let dragProgress = (position - monthPosition) / (sizing.dragPosition(for: .year) - monthPosition)
            let progress = OrgendaCalendarTransition.morphProgress(at: dragProgress)
            let veilOpacity = OrgendaCalendarTransition.veilOpacity(at: dragProgress)
            let blurRadius = OrgendaCalendarTransition.blurRadius(at: dragProgress)
            GeometryReader { geometry in
                let width = geometry.size.width
                let monthIndex = snapshot.monthIndex
                let columnWidth = (width - OrgendaSpacing.contentInset * 2) / 3
                let targetX = CGFloat(monthIndex % 3) * (columnWidth + OrgendaSpacing.contentInset)
                // Match the centered label and miniature in the static year grid.
                let targetY = CGFloat(monthIndex / 3) * (sizing.yearRowHeight + OrgendaCalendarLayout.yearRowSpacing)
                    + (sizing.yearRowHeight - sizing.monthLabelHeight - OrgendaSpacing.inlineGap - OrgendaCalendarLayout.miniMonthHeight) / 2
                    + sizing.monthLabelHeight + OrgendaSpacing.inlineGap
                ZStack(alignment: .topLeading) {
                    Group {
                        if sizing.usesAccessibilityText {
                            yearGrid()
                        } else {
                            OrgendaCalendarYearCanvas(snapshot: snapshot, rowHeight: sizing.yearRowHeight,
                                                      labelHeight: sizing.monthLabelHeight)
                                .equatable()
                        }
                    }
                        .frame(width: width, height: sizing.yearHeight, alignment: .top)
                        .blur(radius: blurRadius)
                        .overlay {
                            OrgendaTheme.background
                                .opacity(veilOpacity)
                                .allowsHitTesting(false)
                        }

                    if sizing.usesAccessibilityText {
                        monthGrid()
                            .opacity(1 - progress)
                    } else {
                        weekdayHeader()
                            .frame(width: width, height: sizing.weekdayLineHeight)
                            .opacity(max(0, 1 - progress * 3))
                        // One date grid owns the entire path; the year's copy is
                        // hidden until this grid reaches its exact final geometry.
                        OrgendaCalendarMorphingMonth(snapshot: snapshot, progress: progress)
                            .frame(
                                width: width + (columnWidth - width) * progress,
                                height: OrgendaCalendarLayout.monthHeight + (OrgendaCalendarLayout.miniMonthHeight - OrgendaCalendarLayout.monthHeight) * progress,
                                alignment: .top
                            )
                            .offset(x: targetX * progress,
                                    y: (sizing.weekdayLineHeight + OrgendaSpacing.inlineGap) * (1 - progress) + targetY * progress)
                    }
                }
            }
            .frame(height: height, alignment: .top)
            .clipped()
            .accessibilityHidden(true)
        }
    }

}

/// Interpolate cell layout and typography instead of crossfading two calendars
/// whose dates occupy different positions near the year stop.
private struct OrgendaCalendarMorphingMonth: View, Equatable {
    let snapshot: OrgendaCalendarResizeSnapshot
    let progress: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .subheadline) private var monthFontSize = 17.0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot === rhs.snapshot && lhs.progress == rhs.progress
    }

    var body: some View {
        Canvas { context, size in
            let columnSpacing = interpolate(OrgendaSpacing.compactInset, OrgendaCalendarLayout.miniMonthSpacing)
            let cellWidth = (size.width - columnSpacing * 6) / 7
            let rowHeight = interpolate(OrgendaDateLayout.dayCellHeight, OrgendaCalendarLayout.miniMonthDayHeight)
            let rowSpacing = interpolate(OrgendaCalendarLayout.monthRowSpacing, OrgendaCalendarLayout.miniMonthSpacing)
            let diameter = interpolate(OrgendaDateLayout.dayDiameter, OrgendaCalendarLayout.miniMonthSelectionDiameter)
            let fontSize = interpolate(monthFontSize, OrgendaCalendarLayout.miniMonthDayNumberSize)
            for (index, day) in snapshot.monthData.days.enumerated() {
                let cellCenter = CGPoint(x: CGFloat(index % 7) * (cellWidth + columnSpacing) + cellWidth / 2,
                                         y: CGFloat(index / 7) * (rowHeight + rowSpacing) + rowHeight / 2)
                let center = CGPoint(x: cellCenter.x, y: cellCenter.y - 2.5 * (1 - progress))
                let circle = Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                   width: diameter, height: diameter))
                if day.isSelected {
                    context.fill(circle, with: .color(OrgendaTheme.accent))
                } else if day.isToday {
                    context.stroke(circle, with: .color(OrgendaTheme.todayOutline.opacity(1 - progress)), lineWidth: 1.5)
                }
                let monthColor = day.isSelected ? OrgendaTheme.onAccent
                    : OrgendaTheme.calendarDayColor(isWeekend: day.isWeekend, isDimmed: !day.inMonth, contrast: contrast)
                let yearColor = day.inMonth ? (day.isSelected ? OrgendaTheme.onAccent : OrgendaTheme.ink) : .clear
                let text = Text(day.number)
                    .font(.system(size: fontSize, weight: day.isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(monthColor.mix(with: yearColor, by: progress))
                context.draw(text, at: center)

                if day.isMarked {
                    let dotDiameter = OrgendaDateLayout.eventMarkerDiameter * (1 - progress)
                    let dot = CGRect(x: cellCenter.x - dotDiameter / 2,
                                     y: cellCenter.y + 18 * (1 - progress) - dotDiameter / 2,
                                     width: dotDiameter, height: dotDiameter)
                    context.fill(Path(ellipseIn: dot), with: .color(OrgendaTheme.accent))
                }
            }
        }
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

/// Immutable presentation data, reused until a date, calendar or event marker changes.
final class OrgendaCalendarResizeSnapshot {
    struct Day {
        let number: String
        let inMonth: Bool
        let isSelected: Bool
        let isToday: Bool
        let isWeekend: Bool
        let isMarked: Bool
    }
    struct Month {
        let label: String
        let days: [Day]
    }
    let monthIndex: Int
    let monthData: Month
    let months: [Month]
    private let sourceMonth: Date
    private let selectedDate: Date
    private let markedDates: Set<String>
    private let calendar: Calendar
    private let today: Date

    init(month: Date, selectedDate: Date, markedDates: Set<String>, calendar: Calendar) {
        sourceMonth = month
        self.selectedDate = selectedDate
        self.markedDates = markedDates
        self.calendar = calendar
        today = calendar.startOfDay(for: .now)
        monthIndex = calendar.component(.month, from: month) - 1
        let dates = OrgCalendarDates(calendar: calendar)
        func makeMonth(_ pageMonth: Date) -> Month {
            return Month(label: pageMonth.formatted(.dateTime.month(.abbreviated)),
                         days: dates.daysInMonthGrid(for: pageMonth).map { date in
                let inMonth = calendar.isDate(date, equalTo: pageMonth, toGranularity: .month)
                return Day(number: String(calendar.component(.day, from: date)), inMonth: inMonth,
                           isSelected: inMonth && calendar.isDate(date, inSameDayAs: selectedDate),
                           isToday: inMonth && calendar.isDateInToday(date),
                           isWeekend: calendar.isDateInWeekend(date),
                           isMarked: markedDates.contains(date.orgendaDayKey))
            })
        }
        months = (1...12).map { makeMonth(dates.monthInYear($0, year: month)) }
        monthData = months.indices.contains(monthIndex) ? months[monthIndex] : makeMonth(month)
    }

    func matches(month: Date, selectedDate: Date, markedDates: Set<String>, calendar: Calendar) -> Bool {
        self.calendar == calendar && self.selectedDate == selectedDate && self.markedDates == markedDates
            && calendar.isDate(sourceMonth, equalTo: month, toGranularity: .month)
            && calendar.isDateInToday(today)
    }
}

private struct OrgendaCalendarYearCanvas: View, Equatable {
    let snapshot: OrgendaCalendarResizeSnapshot
    let rowHeight: CGFloat
    let labelHeight: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot === rhs.snapshot && lhs.rowHeight == rhs.rowHeight && lhs.labelHeight == rhs.labelHeight
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let monthWidth = (size.width - OrgendaSpacing.contentInset * 2) / 3
            let cellWidth = (monthWidth - OrgendaCalendarLayout.miniMonthSpacing * 6) / 7
            let topInset = (rowHeight - labelHeight - OrgendaSpacing.inlineGap - OrgendaCalendarLayout.miniMonthHeight) / 2
            for (monthIndex, month) in snapshot.months.enumerated() {
                let origin = CGPoint(x: CGFloat(monthIndex % 3) * (monthWidth + OrgendaSpacing.contentInset),
                                     y: CGFloat(monthIndex / 3) * (rowHeight + OrgendaCalendarLayout.yearRowSpacing) + topInset)
                let label = Text(month.label).font(.subheadline.weight(.semibold)).foregroundStyle(OrgendaTheme.ink)
                context.draw(label, at: CGPoint(x: origin.x + monthWidth / 2, y: origin.y + labelHeight / 2))
                guard monthIndex != snapshot.monthIndex else { continue }
                for (index, day) in month.days.enumerated() where day.inMonth {
                    let center = CGPoint(x: origin.x + CGFloat(index % 7) * (cellWidth + OrgendaCalendarLayout.miniMonthSpacing) + cellWidth / 2,
                                         y: origin.y + labelHeight + OrgendaSpacing.inlineGap
                                            + CGFloat(index / 7) * (OrgendaCalendarLayout.miniMonthDayHeight + OrgendaCalendarLayout.miniMonthSpacing)
                                            + OrgendaCalendarLayout.miniMonthDayHeight / 2)
                    if day.isSelected {
                        let diameter = OrgendaCalendarLayout.miniMonthSelectionDiameter
                        context.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                            width: diameter, height: diameter)), with: .color(OrgendaTheme.accent))
                    }
                    context.draw(Text(day.number)
                        .font(.system(size: OrgendaCalendarLayout.miniMonthDayNumberSize, weight: day.isSelected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(day.isSelected ? OrgendaTheme.onAccent : OrgendaTheme.ink), at: center)
                }
            }
        }
    }
}
