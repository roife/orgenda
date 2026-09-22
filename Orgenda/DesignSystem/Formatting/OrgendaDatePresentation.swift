import Foundation

/// Context-aware date labels for browsing surfaces. The current year is
/// implied unless showing it is necessary to disambiguate another year.
enum OrgendaDatePresentation {
    static func relativeDayName(
        for date: Date,
        relativeTo reference: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: date)
        ).day
        guard let offset, (-1...1).contains(offset) else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: offset)).capitalized(with: locale)
    }

    static func date(
        _ date: Date,
        relativeTo reference: Date = .now,
        month: Date.FormatStyle.Symbol.Month = .abbreviated,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .locale(locale)
            .month(month)
            .day()
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: reference, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    static func weekdayDate(
        _ date: Date,
        relativeTo reference: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .locale(locale)
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: reference, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    static func relativeDate(
        _ date: Date,
        relativeTo reference: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        relativeDayName(for: date, relativeTo: reference, locale: locale, calendar: calendar)
            ?? weekdayDate(date, relativeTo: reference, locale: locale, calendar: calendar)
    }

    static func dateTime(
        _ date: Date,
        relativeTo reference: Date = .now,
        usesRelativeDay: Bool = true,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let day = usesRelativeDay
            ? relativeDate(date, relativeTo: reference, locale: locale, calendar: calendar)
            : self.date(date, relativeTo: reference, locale: locale, calendar: calendar)
        var timeStyle = Date.FormatStyle.dateTime.locale(locale).hour().minute()
        timeStyle.timeZone = calendar.timeZone
        let time = date.formatted(timeStyle)
        return "\(day) · \(time)"
    }

    static func monthHeading(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .locale(locale)
            .month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let month = date.formatted(style)
        let year = calendar.component(.year, from: date)
            .formatted(.number.locale(locale).grouping(.never))
        return "\(month) \(year)"
    }
}
