import Foundation

extension Date {
    private static let orgendaDayKeyFormat = Date.VerbatimFormatStyle(
        format: "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .autoupdatingCurrent,
        calendar: .autoupdatingCurrent
    )

    var startOfDay: Date { Calendar.autoupdatingCurrent.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: days, to: self) ?? self
    }

    var orgendaDayKey: String {
        formatted(Self.orgendaDayKeyFormat)
    }

    func orgendaDayKey(in calendar: Calendar) -> String {
        String(format: "%04d-%02d-%02d", calendar.component(.year, from: self),
               calendar.component(.month, from: self), calendar.component(.day, from: self))
    }
}
