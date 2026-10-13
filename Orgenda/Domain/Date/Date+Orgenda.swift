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

    /// New timestamps share one Gregorian, English representation. Edits to
    /// existing timestamps use their drafts to retain the original spelling.
    func orgTimestamp(active: Bool = true, includesTime: Bool, recurrence: String? = nil) -> String {
        let body = orgDateText(includesTime: includesTime) + (recurrence.map { " " + $0 } ?? "")
        return active ? "<\(body)>" : "[\(body)]"
    }

    func orgDateText(includesTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = includesTime ? "yyyy-MM-dd EEE HH:mm" : "yyyy-MM-dd EEE"
        return formatter.string(from: self)
    }

    /// Org timestamps use the Gregorian calendar and must not roll invalid
    /// dates or times into a different day when Foundation constructs them.
    static func orgTimestamp(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date) == components
        else { return nil }
        return date
    }
}
