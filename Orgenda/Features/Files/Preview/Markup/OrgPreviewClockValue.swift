import Foundation

struct OrgPreviewClockValue {
    private let startDraft: OrgPlanningEntryDraft?
    private let endDraft: OrgPlanningEntryDraft?
    let minutes: Int?

    init(_ node: ParsedOrgNode) {
        let timestamps = node.children.filter { $0.type == "inactive_timestamp" }
        startDraft = timestamps.first.flatMap { OrgPlanningEntryDraft(timestampSource: $0.text) }
        endDraft = timestamps.dropFirst().first.flatMap { OrgPlanningEntryDraft(timestampSource: $0.text) }
        let duration = node.children.first { $0.type == "clock_duration" }?.text
            .replacingOccurrences(of: "=>", with: "").trimmingCharacters(in: .whitespaces)
        let parts = duration?.split(separator: ":").compactMap { Int($0) } ?? []
        if parts.count == 2, parts[0] <= (Int.max - parts[1]) / 60 {
            minutes = parts[0] * 60 + parts[1]
        } else {
            minutes = nil
        }
    }

    var duration: String { minutes.map(Self.duration) ?? "Running" }

    func interval(
        locale: Locale = .autoupdatingCurrent,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard let startDraft else { return nil }
        let startDate = startDraft.timestamps[0].date
        let start = OrgPreviewDateText(draft: startDraft, locale: locale, now: now).date
        guard let endDraft else { return start }
        let endDate = endDraft.timestamps[0].date

        if calendar.isDate(startDate, inSameDayAs: endDate) {
            var timeStyle = Date.FormatStyle.dateTime.locale(locale).hour().minute()
            timeStyle.timeZone = calendar.timeZone
            let day = OrgendaDatePresentation.date(
                startDate,
                relativeTo: now,
                locale: locale,
                calendar: calendar
            )
            return "\(day) · \(startDate.formatted(timeStyle))–\(endDate.formatted(timeStyle))"
        }

        let end = OrgPreviewDateText(draft: endDraft, locale: locale, now: now).date
        return "\(start) → \(end)"
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours == 0 ? "\(remainder)m" : remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
