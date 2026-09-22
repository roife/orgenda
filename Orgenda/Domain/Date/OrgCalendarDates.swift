import Foundation

/// Calendar-aware date arithmetic shared by the full calendar and miniature months.
struct OrgCalendarDates {
    var calendar: Calendar = .autoupdatingCurrent

    var rotatedWeekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let index = calendar.firstWeekday - 1
        return Array(symbols[index...] + symbols[..<index])
    }

    func daysInWeek(containing date: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    func daysInMonthGrid(for visibleMonth: Date) -> [Date] {
        guard
            let month = calendar.dateInterval(of: .month, for: visibleMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start)
        else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    func daysInMonth(for month: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }

    func monthInYear(_ month: Int, year: Date) -> Date {
        var components = calendar.dateComponents([.era, .year], from: year)
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? year
    }

    func date(in month: Date, day preferredDay: Int) -> Date {
        guard let validDays = calendar.range(of: .day, in: .month, for: month) else {
            return calendar.startOfDay(for: month)
        }

        var components = calendar.dateComponents([.era, .year, .month], from: month)
        components.day = min(max(preferredDay, validDays.lowerBound), validDays.upperBound - 1)
        return calendar.startOfDay(for: calendar.date(from: components) ?? month)
    }
}
