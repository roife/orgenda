import SwiftUI

enum OrgendaCalendarLayout {
    static let miniMonthSelectionDiameter: CGFloat = 14
    static let monthRowSpacing: CGFloat = 2
    static let monthRowCount = 6
    static let monthHeight = OrgendaDateLayout.dayCellHeight * CGFloat(monthRowCount)
        + monthRowSpacing * CGFloat(monthRowCount - 1)
}

/// Accepted Motion Lab settings; keep in sync with previews/calendar-motion.json.
enum OrgendaCalendarTransition {
    static let opacityMax = 1.0
    static let opacityMiddle = 0.66
    static let opacityBend = 6.0
    static let opacityEnd = 1.0
    static let blurMax = 5.0
    static let blurEnd = 1.0
    static let blurPower = 1.65
    static let morphPower = 1.0
    static let snapDuration = 0.32

    static func veilOpacity(at progress: CGFloat) -> Double {
        let value = clamped(Double(progress) / opacityEnd)
        let opacity = value <= 0.5
            ? opacityMiddle + (1 - opacityMiddle) * pow(1 - 2 * value, opacityBend)
            : opacityMiddle * (1 - pow(2 * value - 1, opacityBend))
        return opacityMax * opacity
    }

    static func blurRadius(at progress: CGFloat) -> CGFloat {
        let value = pow(clamped(Double(progress) / blurEnd), blurPower)
        return CGFloat(blurMax * (1 - smootherStep(value)))
    }

    static func morphProgress(at progress: CGFloat) -> CGFloat {
        CGFloat(pow(clamped(Double(progress)), morphPower))
    }

    private static func smootherStep(_ value: Double) -> Double {
        value * value * value * (value * (value * 6 - 15) + 10)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
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
