import Foundation

/// A display-only projection. The draft retains the exact Org source for edits.
struct OrgPreviewDateText {
    let draft: OrgPlanningEntryDraft
    var locale: Locale = .autoupdatingCurrent
    var now: Date = .now

    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private var traditional: Bool {
        locale.language.script?.identifier == "Hant" || ["TW", "HK", "MO"].contains(locale.region?.identifier ?? "")
    }

    func localized(_ english: String, _ simplified: String, _ traditional: String) -> String {
        chinese ? (self.traditional ? traditional : simplified) : english
    }

    var keyword: String? {
        switch draft.keyword {
        case .scheduled: localized("Scheduled", "计划", "計畫")
        case .deadline: localized("Deadline", "截止", "截止")
        case .closed: localized("Closed", "完成", "完成")
        case nil: nil
        }
    }

    var date: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let timeStyle = style.hour().minute()
        return draft.timestamps.map { timestamp in
            let sameYear = calendar.component(.year, from: timestamp.date)
                == calendar.component(.year, from: now)
            let dateStyle = style.month(.abbreviated).day().weekday(.abbreviated)
            var result = timestamp.date.formatted(sameYear ? dateStyle : dateStyle.year())
            if timestamp.includesTime {
                result += " " + timestamp.date.formatted(timeStyle)
                if let range = OrgPlanningTimestampDraft.sameDayTimeRange(in: timestamp.trailingText) {
                    let parts = timestamp.trailingText[range].dropFirst().split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2, let end = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: timestamp.date) {
                        result += "–" + end.formatted(timeStyle)
                    }
                }
            }
            return result
        }.joined(separator: " → ")
    }

    var details: [String] {
        draft.timestamps.flatMap { timestamp -> [String] in
            var result: [String] = []
            var remainder = timestamp.trailingText
            if let range = OrgPlanningTimestampDraft.sameDayTimeRange(in: remainder) {
                remainder.removeSubrange(range)
            }
            if let token = timestamp.recurrence, let repeater = OrgRepeater(token) {
                result.append(recurrence(repeater))
                if let range = remainder.range(of: token) { remainder.removeSubrange(range) }
            }
            // Keep warnings, delays and unfamiliar extensions visible instead of
            // silently dropping source semantics while formatting the date.
            let annotation = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !annotation.isEmpty { result.append(annotation) }
            return result
        }
    }

    var accessibilityValue: String { ([date] + details).joined(separator: ", ") }

    private func recurrence(_ repeater: OrgRepeater) -> String {
        let unit: String
        let english: String
        switch repeater.unit {
        case .hour: unit = localized("", "小时", "小時"); english = "hour"
        case .day: unit = "天"; english = "day"
        case .week: unit = localized("", "周", "週"); english = "week"
        case .month: unit = "月"; english = "month"
        case .year: unit = "年"; english = "year"
        }
        var value = chinese
            ? "每\(repeater.interval == 1 ? "" : "\(repeater.interval) ")\(unit)\(localized("", "重复", "重複"))"
            : "Every \(repeater.interval == 1 ? english : "\(repeater.interval) \(english)s")"
        switch repeater.mode {
        case .cumulative: break
        case .catchUp: value += localized(" · skip missed dates", " · 跳过已错过的日期", " · 跳過已錯過的日期")
        case .restart: value += localized(" after completion", "（从完成时算起）", "（從完成時算起）")
        }
        if let maximum = repeater.maximumInterval, let maximumUnit = repeater.maximumUnit {
            let names: [OrgRepeater.Unit: String] = chinese
                ? [.hour: localized("", "小时", "小時"), .day: "天", .week: localized("", "周", "週"), .month: "月", .year: "年"]
                : [.hour: "hour", .day: "day", .week: "week", .month: "month", .year: "year"]
            let name = names[maximumUnit] ?? maximumUnit.rawValue
            value += localized(" · maximum ", " · 最长间隔 ", " · 最長間隔 ")
                + "\(maximum) \(name)" + (!chinese && maximum != 1 ? "s" : "")
        }
        return value
    }
}
