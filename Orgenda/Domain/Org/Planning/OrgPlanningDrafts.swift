import Foundation

enum OrgPlanningKeyword: String, CaseIterable, Identifiable, Sendable {
    case scheduled = "SCHEDULED"
    case deadline = "DEADLINE"
    case closed = "CLOSED"

    var id: String { rawValue }
    var sourceToken: String { "\(rawValue):" }

    var title: String {
        switch self {
        case .scheduled: String(localized: "Scheduled")
        case .deadline: String(localized: "Deadline")
        case .closed: String(localized: "Closed")
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .deadline: "calendar.badge.exclamationmark"
        case .closed: "calendar.badge.checkmark"
        }
    }

}

struct OrgPlanningTimestampDraft: Hashable, Sendable {
    private static let sameDayTimeExpression = try? NSRegularExpression(pattern: #"^-\d{2}:\d{2}"#)
    private static let recurrenceTokenExpression = try? NSRegularExpression(
        pattern: #"(?<!\S)(?:\+\+|\.\+|\+)\d+[hdwmy](?:/\d+[hdwmy])?(?!\S)"#
    )

    /// Range of a leading `-HH:MM` same-day end time in the given suffix text.
    static func sameDayTimeRange(in text: String) -> Range<String.Index>? {
        sameDayTimeExpression?
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { Range($0.range, in: text) }
    }

    var date: Date
    var includesTime: Bool
    var recurrence: String?
    fileprivate let originalDate: Date
    fileprivate let weekdaySeparator: String?
    fileprivate let weekdayText: String?
    fileprivate let timeSeparator: String?
    fileprivate let originalTimeText: String?
    fileprivate let isActive: Bool
    fileprivate var suffix: String

    /// Read-only annotation source for presentation; editing still preserves every token.
    var trailingText: String { sourceSuffix }

    /// Only the repeater token changes; warning offsets and time ranges stay intact.
    mutating func setRecurrence(_ recurrence: String?) {
        self.recurrence = recurrence
    }

    fileprivate var sourceSuffix: String {
        var suffix = suffix
        if let range = Self.recurrenceRange(in: suffix) {
            if let recurrence {
                suffix.replaceSubrange(range, with: recurrence)
            } else {
                var lower = range.lowerBound
                if lower > suffix.startIndex {
                    let previous = suffix.index(before: lower)
                    if suffix[previous] == " " || suffix[previous] == "\t" { lower = previous }
                }
                suffix.removeSubrange(lower..<range.upperBound)
            }
        } else if let recurrence {
            // Org puts the repeater before any warning offset.
            // A same-day time range must remain adjacent to the start time.
            let timeRangeEnd = Self.sameDayTimeRange(in: suffix)?.upperBound ?? suffix.startIndex
            let remainder = suffix[timeRangeEnd...]
            if let nextToken = remainder.firstIndex(where: { !$0.isWhitespace }) {
                let separator = suffix[timeRangeEnd..<nextToken]
                suffix = String(suffix[..<timeRangeEnd]) + (separator.isEmpty ? " " : String(separator))
                    + recurrence + " " + suffix[nextToken...]
            } else {
                suffix = String(suffix[..<timeRangeEnd]) + " " + recurrence + remainder
            }
        }
        return suffix
    }

    fileprivate static func recurrenceRange(in suffix: String) -> Range<String.Index>? {
        recurrenceTokenExpression?
            .firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix))
            .flatMap { Range($0.range, in: suffix) }
    }

    mutating func move(to newDate: Date, includesTime: Bool, durationMinutes: Int? = nil) {
        if let range = Self.sameDayTimeRange(in: suffix) {
            if includesTime {
                let oldEnd = String(suffix[range].dropFirst()).split(separator: ":").compactMap { Int($0) }
                let calendar = Calendar.current
                let oldStartMinutes = calendar.component(.hour, from: date) * 60
                    + calendar.component(.minute, from: date)
                let oldDuration = oldEnd.count == 2 ? (oldEnd[0] * 60 + oldEnd[1] - oldStartMinutes + 1440) % 1440 : 0
                let end = newDate.addingTimeInterval(TimeInterval(durationMinutes ?? oldDuration) * 60)
                suffix.replaceSubrange(range, with: String(
                    format: "-%02d:%02d", calendar.component(.hour, from: end), calendar.component(.minute, from: end)
                ))
            } else {
                suffix.removeSubrange(range)
            }
        } else if includesTime, let durationMinutes, durationMinutes > 0, durationMinutes < 24 * 60 {
            let end = newDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
            suffix = String(format: "-%02d:%02d", Calendar.current.component(.hour, from: end),
                            Calendar.current.component(.minute, from: end)) + suffix
        }
        date = newDate
        self.includesTime = includesTime
    }
}

/// Editable semantic state for a planning entry or a plain timestamp/range.
///
/// Parsing records every source segment surrounding the keyword and timestamp
/// tokens. Rebuilding therefore changes only the selected semantic values while
/// preserving tabs, repeaters, warning offsets, ranges, and trailing whitespace.
struct OrgPlanningEntryDraft: Hashable, Sendable {
    private static let keywordExpression = try? NSRegularExpression(
        pattern: #"(SCHEDULED|DEADLINE|CLOSED):"#
    )
    private static let timestampTokenExpression = try? NSRegularExpression(
        pattern: #"<[^>\r\n]+>|\[[^\]\r\n]+\]"#
    )
    private static let timestampBodyExpression = try? NSRegularExpression(
        pattern: #"^((\d{4})-(\d{2})-(\d{2}))(?:(\s+)([[:alpha:]]+))?(?:(\s+)((\d{2}):(\d{2})))?(.*)$"#
    )

    var keyword: OrgPlanningKeyword?
    var timestamps: [OrgPlanningTimestampDraft]

    private let prefix: String
    private let timestampSegments: [String]

    init?(source: String) {
        self.init(source: source, isPlainTimestamp: false)
    }

    init?(timestampSource: String) {
        self.init(source: timestampSource, isPlainTimestamp: true)
    }

    private init?(source: String, isPlainTimestamp: Bool) {
        let keyword: OrgPlanningKeyword?
        let keywordStart: String.Index
        let timestampsStart: String.Index
        if isPlainTimestamp {
            keyword = nil
            keywordStart = source.startIndex
            timestampsStart = source.startIndex
        } else {
            guard
                let keywordExpression = Self.keywordExpression,
                let keywordMatch = keywordExpression.firstMatch(
                    in: source,
                    range: NSRange(source.startIndex..., in: source)
                ),
                let keywordTokenRange = Range(keywordMatch.range(at: 0), in: source),
                let keywordValueRange = Range(keywordMatch.range(at: 1), in: source),
                let parsedKeyword = OrgPlanningKeyword(rawValue: String(source[keywordValueRange]))
            else {
                return nil
            }
            keyword = parsedKeyword
            keywordStart = keywordTokenRange.lowerBound
            timestampsStart = keywordTokenRange.upperBound
        }
        guard let timestampExpression = Self.timestampTokenExpression else { return nil }

        let timestampMatches = timestampExpression.matches(
            in: source,
            range: NSRange(timestampsStart..<source.endIndex, in: source)
        )
        guard (1...2).contains(timestampMatches.count) else { return nil }

        var parsedTimestamps: [OrgPlanningTimestampDraft] = []
        var segments: [String] = []
        var cursor = timestampsStart

        for match in timestampMatches {
            guard let range = Range(match.range, in: source),
                  let timestamp = Self.parseTimestamp(String(source[range])) else {
                return nil
            }
            segments.append(String(source[cursor..<range.lowerBound]))
            parsedTimestamps.append(timestamp)
            cursor = range.upperBound
        }
        segments.append(String(source[cursor...]))
        if isPlainTimestamp {
            guard segments.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                  segments.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                  parsedTimestamps.count == 1 || segments[1] == "--" else { return nil }
        }

        self.keyword = keyword
        timestamps = parsedTimestamps
        prefix = String(source[..<keywordStart])
        timestampSegments = segments
    }

    var source: String {
        var result = prefix + (keyword?.sourceToken ?? "")
        for index in timestamps.indices {
            result += timestampSegments[index]
            result += Self.timestampSource(timestamps[index])
        }
        result += timestampSegments.last ?? ""
        return result
    }

    var isRange: Bool { timestamps.count == 2 }

    private static func parseTimestamp(_ source: String) -> OrgPlanningTimestampDraft? {
        guard source.count >= 2,
              let opening = source.first,
              let closing = source.last,
              (opening == "<" && closing == ">") || (opening == "[" && closing == "]")
        else {
            return nil
        }

        let inner = String(source.dropFirst().dropLast())
        guard
            let expression = timestampBodyExpression,
            let match = expression.firstMatch(
                in: inner,
                range: NSRange(inner.startIndex..., in: inner)
            )
        else {
            return nil
        }

        func integer(_ capture: Int) -> Int? {
            guard match.range(at: capture).location != NSNotFound,
                  let range = Range(match.range(at: capture), in: inner) else {
                return nil
            }
            return Int(inner[range])
        }

        guard let year = integer(2), let month = integer(3), let day = integer(4) else {
            return nil
        }

        let hour = integer(9)
        let minute = integer(10)
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .autoupdatingCurrent
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour ?? 0
        components.minute = minute ?? 0

        guard let date = components.date else { return nil }
        let suffix: String
        if match.range(at: 11).location != NSNotFound,
           let range = Range(match.range(at: 11), in: inner) {
            suffix = String(inner[range])
        } else {
            suffix = ""
        }

        func text(_ capture: Int) -> String? {
            guard match.range(at: capture).location != NSNotFound,
                  let range = Range(match.range(at: capture), in: inner) else {
                return nil
            }
            return String(inner[range])
        }

        return OrgPlanningTimestampDraft(
            date: date,
            includesTime: hour != nil && minute != nil,
            recurrence: OrgPlanningTimestampDraft.recurrenceRange(in: suffix).map { String(suffix[$0]) },
            originalDate: date,
            weekdaySeparator: text(5),
            weekdayText: text(6),
            timeSeparator: text(7),
            originalTimeText: text(8),
            isActive: opening == "<",
            suffix: suffix
        )
    }

    private static func timestampSource(_ timestamp: OrgPlanningTimestampDraft) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute],
            from: timestamp.date
        )
        let weekdayIndex = min(max((components.weekday ?? 1) - 1, 0), weekdays.count - 1)
        var inner = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )

        if let weekdayText = timestamp.weekdayText {
            let sameDay = calendar.isDate(
                timestamp.date,
                inSameDayAs: timestamp.originalDate
            )
            let updatedWeekday = sameDay
                ? weekdayText
                : weekdayName(at: weekdayIndex, styledLike: weekdayText)
            inner += (timestamp.weekdaySeparator ?? " ") + updatedWeekday
        }

        if timestamp.includesTime {
            let originalComponents = calendar.dateComponents(
                [.hour, .minute],
                from: timestamp.originalDate
            )
            let sameTime = timestamp.originalTimeText != nil
                && components.hour == originalComponents.hour
                && components.minute == originalComponents.minute
            let timeText = sameTime
                ? (timestamp.originalTimeText ?? "")
                : String(
                    format: "%02d:%02d",
                    components.hour ?? 0,
                    components.minute ?? 0
                )
            inner += (timestamp.timeSeparator ?? " ") + timeText
        }
        var suffix = timestamp.sourceSuffix
        if !timestamp.includesTime, let range = OrgPlanningTimestampDraft.sameDayTimeRange(in: suffix) {
            suffix.removeSubrange(range)
        }
        inner += suffix

        return timestamp.isActive ? "<\(inner)>" : "[\(inner)]"
    }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let fullWeekdays = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    private static func weekdayName(at index: Int, styledLike original: String) -> String {
        var replacement = original.count > 3 ? fullWeekdays[index] : weekdays[index]
        if original == original.uppercased() {
            replacement = replacement.uppercased()
        } else if original == original.lowercased() {
            replacement = replacement.lowercased()
        }
        return replacement
    }
}
