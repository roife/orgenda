import SwiftUI

enum OrgendaCalendarLayout {
    static let monthRowSpacing: CGFloat = 2
    static let monthRowCount = 6
    static let monthHeight = OrgendaDateLayout.dayCellHeight * CGFloat(monthRowCount)
        + monthRowSpacing * CGFloat(monthRowCount - 1)
}

/// Geometry for week, month, year, and the resize transition between them.
struct OrgendaCalendarSizing {
    typealias Density = OrgendaCalendar.Density

    let usesAccessibilityText: Bool
    let dayNumberSize: CGFloat
    let weekdayLineHeight: CGFloat
    let monthLabelHeight: CGFloat

    func calendarHeight(for density: Density) -> CGFloat {
        switch density {
        case .week: usesAccessibilityText ? accessibleDateStripHeight : OrgendaDateLayout.dayCellHeight
        case .month: usesAccessibilityText ? accessibleDateStripHeight : OrgendaCalendarLayout.monthHeight
        case .year: yearHeight
        }
    }

    func selectionHeight(for density: Density) -> CGFloat {
        calendarHeight(for: density)
            + (density != .year && !usesAccessibilityText ? weekdayLineHeight + 6 : 0)
    }

    func dragPosition(for density: Density) -> CGFloat {
        // Week and Month share a date strip at accessibility sizes, but still
        // need distinct drag stops so both remain reachable.
        let month = max(96, selectionHeight(for: .month) - selectionHeight(for: .week))
        switch density {
        case .week: return 0
        case .month: return month
        case .year: return month + max(96, selectionHeight(for: .year) - selectionHeight(for: .month))
        }
    }

    func density(at position: CGFloat) -> Density {
        if position < dragPosition(for: .month) / 2 { return .week }
        if position < (dragPosition(for: .month) + dragPosition(for: .year)) / 2 { return .month }
        return .year
    }

    func selectionHeight(at position: CGFloat) -> CGFloat {
        let lower: Density = position < dragPosition(for: .month) ? .week : .month
        let upper: Density = lower == .week ? .month : .year
        let progress = (position - dragPosition(for: lower)) / (dragPosition(for: upper) - dragPosition(for: lower))
        return selectionHeight(for: lower) + (selectionHeight(for: upper) - selectionHeight(for: lower)) * progress
    }

    var accessibleDayDiameter: CGFloat {
        OrgendaDateLayout.accessibleDayDiameter(numberSize: dayNumberSize)
    }

    var accessibleDateStripHeight: CGFloat {
        accessibleDayDiameter + weekdayLineHeight + OrgendaDateLayout.eventMarkerDiameter + 14
    }

    var yearRowHeight: CGFloat {
        usesAccessibilityText ? max(44, monthLabelHeight + 16) : monthLabelHeight + 78
    }

    var yearHeight: CGFloat {
        yearRowHeight * 4 + 30
    }

}
