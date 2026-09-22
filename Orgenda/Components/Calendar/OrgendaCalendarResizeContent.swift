import SwiftUI

struct OrgendaCalendarResizeContent<Month: View, Year: View, Weekdays: View, Days: View>: View {
    let position: CGFloat
    let visibleMonth: Date
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
            VStack(spacing: 6) {
                if !sizing.usesAccessibilityText {
                    weekdayHeader().frame(height: sizing.weekdayLineHeight)
                }
                if sizing.usesAccessibilityText {
                    accessibleDays(sizing.density(at: position) == .week)
                } else {
                    monthGrid()
                        .frame(height: OrgendaCalendarLayout.monthHeight, alignment: .top)
                        .offset(y: -selectedWeekOffset * (1 - progress))
                        .frame(height: height - sizing.weekdayLineHeight - 6, alignment: .top)
                        .clipped()
                }
            }
            .frame(height: height, alignment: .top)
            .clipped()
            .accessibilityHidden(true)
        } else {
            let progress = (position - monthPosition) / (sizing.dragPosition(for: .year) - monthPosition)
            GeometryReader { geometry in
                let width = geometry.size.width
                let monthIndex = Calendar.autoupdatingCurrent.component(.month, from: visibleMonth) - 1
                let columnWidth = (width - 24) / 3
                let targetX = CGFloat(monthIndex % 3) * (columnWidth + 12)
                let targetY = CGFloat(monthIndex / 3) * (sizing.yearRowHeight + 10) + sizing.monthLabelHeight + 6
                ZStack(alignment: .topLeading) {
                    yearGrid()
                        .frame(width: width, height: sizing.yearHeight, alignment: .top)
                        .opacity(progress)

                    if sizing.usesAccessibilityText {
                        monthGrid()
                            .opacity(1 - progress)
                    } else {
                        weekdayHeader()
                            .frame(width: width, height: sizing.weekdayLineHeight)
                            .opacity(max(0, 1 - progress * 3))
                        // The full month shrinks into its actual slot in the year.
                        // Keep dates undistorted until the final miniature takes over.
                        monthGrid()
                            .frame(width: width, height: OrgendaCalendarLayout.monthHeight, alignment: .top)
                            .scaleEffect(
                                x: 1 + (columnWidth / width - 1) * progress,
                                y: 1 + (72 / OrgendaCalendarLayout.monthHeight - 1) * progress,
                                anchor: .topLeading
                            )
                            .offset(x: targetX * progress,
                                    y: (sizing.weekdayLineHeight + 6) * (1 - progress) + targetY * progress)
                            .opacity(min(1, (1 - progress) * 3))
                    }
                }
            }
            .frame(height: height, alignment: .top)
            .clipped()
            .accessibilityHidden(true)
        }
    }

}
