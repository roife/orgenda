import Foundation

/// Org's three repeater modes. This value performs date arithmetic only; source
/// mutation and completion logging remain the workspace's responsibility.
struct OrgRepeater: Hashable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case cumulative = "+"
        case catchUp = "++"
        case restart = ".+"
    }

    enum Unit: String, CaseIterable, Sendable {
        case hour = "h"
        case day = "d"
        case week = "w"
        case month = "m"
        case year = "y"

        fileprivate var component: Calendar.Component {
            switch self {
            case .hour: .hour
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    var mode: Mode
    var interval: Int
    var unit: Unit
    /// A habit's optional maximum interval is retained, while its minimum
    /// interval determines the next scheduled occurrence.
    var maximumInterval: Int?
    var maximumUnit: Unit?

    var token: String {
        let maximum = maximumInterval.flatMap { count in maximumUnit.map { "/\(count)\($0.rawValue)" } } ?? ""
        return "\(mode.rawValue)\(interval)\(unit.rawValue)\(maximum)"
    }

    static func isValid(_ token: String?) -> Bool {
        token == nil || token.flatMap(Self.init) != nil
    }

    var summary: String {
        let frequency: String
        switch unit {
        case .hour: frequency = interval == 1 ? String(localized: "Every hour") : String(localized: "Every \(interval) hours")
        case .day: frequency = interval == 1 ? String(localized: "Every day") : String(localized: "Every \(interval) days")
        case .week: frequency = interval == 1 ? String(localized: "Every week") : String(localized: "Every \(interval) weeks")
        case .month: frequency = interval == 1 ? String(localized: "Every month") : String(localized: "Every \(interval) months")
        case .year: frequency = interval == 1 ? String(localized: "Every year") : String(localized: "Every \(interval) years")
        }
        switch mode {
        case .cumulative: return frequency
        case .catchUp: return String(localized: "\(frequency), skip missed dates")
        case .restart: return String(localized: "\(frequency) after completion")
        }
    }

    private static let tokenExpression = try? NSRegularExpression(
        pattern: #"\A(\+\+|\.\+|\+)([1-9]\d*)([hdwmy])(?:/([1-9]\d*)([hdwmy]))?\z"#
    )

    init?(_ token: String) {
        guard let expression = Self.tokenExpression,
              let match = expression.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) else {
            return nil
        }
        func text(_ capture: Int) -> String? {
            Range(match.range(at: capture), in: token).map { String(token[$0]) }
        }
        guard let prefix = text(1), let mode = Mode(rawValue: prefix),
              let count = text(2), let interval = Int(count),
              let unitText = text(3), let unit = Unit(rawValue: unitText) else { return nil }
        let maximumInterval = text(4).flatMap(Int.init)
        if text(4) != nil, maximumInterval == nil { return nil }
        self.mode = mode
        self.interval = interval
        self.unit = unit
        self.maximumInterval = maximumInterval
        maximumUnit = text(5).flatMap(Unit.init(rawValue:))
    }

    /// `+` advances once, `++` keeps the original cadence until it is in the
    /// future, and `.+` starts again from the completion day. Hourly `.+`
    /// repeaters start from the actual completion time.
    func nextDate(
        afterCompletion completion: Date,
        from base: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        switch mode {
        case .cumulative:
            return occurrence(at: 1, from: base, calendar: calendar)
        case .catchUp:
            guard var index = firstIndex(onOrAfter: completion, from: base, calendar: calendar) else { return nil }
            index = max(1, index)
            guard let candidate = occurrence(at: index, from: base, calendar: calendar) else { return nil }
            if candidate > completion { return candidate }
            let (next, overflow) = index.addingReportingOverflow(1)
            return overflow ? nil : occurrence(at: next, from: base, calendar: calendar)
        case .restart:
            if unit == .hour {
                let anchor = calendar.dateInterval(of: .minute, for: completion)?.start ?? completion
                return occurrence(at: 1, from: anchor, calendar: calendar)
            }
            let clock = calendar.dateComponents([.hour, .minute], from: base)
            guard let day = occurrence(at: 1, from: calendar.startOfDay(for: completion), calendar: calendar) else {
                return nil
            }
            return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day,
                                 matchingPolicy: .nextTimePreservingSmallerComponents)
        }
    }

    /// Generates only occurrences in the requested local day, including the
    /// stored base occurrence. It does not create a growing historical cache.
    func occurrences(
        on day: Date,
        from base: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        guard let interval = calendar.dateInterval(of: .day, for: day),
              var index = firstIndex(onOrAfter: interval.start, from: base, calendar: calendar) else { return [] }
        var dates: [Date] = []
        // Even a one-hour repeater has at most 25 occurrences on a DST day.
        // This bound also protects against anomalous calendar results.
        while dates.count < 48, let date = occurrence(at: index, from: base, calendar: calendar), date < interval.end {
            guard date >= interval.start, dates.last.map({ date > $0 }) ?? true else { break }
            dates.append(date)
            let (next, overflow) = index.addingReportingOverflow(1)
            guard !overflow else { break }
            index = next
        }
        return dates
    }

    private func occurrence(at index: Int, from base: Date, calendar: Calendar) -> Date? {
        guard index >= 0 else { return nil }
        let (value, overflow) = interval.multipliedReportingOverflow(by: index)
        guard !overflow, let date = calendar.date(byAdding: unit.component, value: value, to: base),
              date.timeIntervalSinceReferenceDate.isFinite,
              index == 0 || date > base else { return nil }
        return date
    }

    /// Exponential bounds followed by binary search avoid stepping through
    /// decades of old hourly or daily occurrences on the main thread.
    private func firstIndex(onOrAfter target: Date, from base: Date, calendar: Calendar) -> Int? {
        guard base < target else { return 0 }
        var lower = 0
        var upper = 1
        while let date = occurrence(at: upper, from: base, calendar: calendar), date < target {
            lower = upper
            let (doubled, overflow) = upper.multipliedReportingOverflow(by: 2)
            if overflow { return nil }
            upper = doubled
        }
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            if let date = occurrence(at: middle, from: base, calendar: calendar), date < target {
                lower = middle
            } else {
                upper = middle
            }
        }
        return occurrence(at: upper, from: base, calendar: calendar) == nil ? nil : upper
    }
}
