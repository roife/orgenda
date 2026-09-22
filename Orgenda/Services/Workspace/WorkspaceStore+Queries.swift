import Foundation

extension WorkspaceStore {
    var overdueCount: Int { overdueItems.count }

    /// O(1) lookup backed by the index rebuilt on every `items` change.
    func item(withID id: UUID) -> OrgItem? {
        itemIndicesByID[id].map { items[$0] }
    }

    func items(on date: Date) -> [OrgItem] {
        // Results are day-granular, so one computation per day is enough; the
        // cache is cleared whenever `items` is rebuilt.
        let key = date.orgendaDayKey
        if let cached = itemsByDayCache[key] { return cached }
        let result = datedItems.compactMap { item in
            let primary = item.scheduled ?? item.deadline ?? item.eventDate
            let dates = [item.scheduled, item.deadline, item.eventDate].compactMap { $0 }
            if dates.contains(where: { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: date) }) { return item }
            if usesEmacsConfiguration, let base = primary, let repeater = item.recurrence.flatMap(OrgRepeater.init),
               let occurrence = repeater.occurrences(on: date, from: base).first {
                var projected = item
                if item.scheduled != nil { projected.scheduled = occurrence }
                else if item.deadline != nil { projected.deadline = occurrence }
                else { projected.eventDate = occurrence }
                return projected
            }
            if let event = item.eventDate, item.durationMinutes >= 24 * 60 {
                let end = event.addingTimeInterval(Double(item.durationMinutes) * 60)
                if date.startOfDay >= event.startOfDay && date.startOfDay <= end.startOfDay { return item }
            }
            return nil
        }
        itemsByDayCache[key] = result
        return result
    }

    func journal(on date: Date) -> [JournalEntry] {
        journalEntries
            .filter { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }
    func search(_ query: String, scope: SearchScope) -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var results: [SearchResult] = []

        if scope == .all || scope == .tasks || scope == .calendar {
            let searchableItems: [OrgItem]
            switch scope {
            case .calendar: searchableItems = datedItems
            case .tasks: searchableItems = items.filter { [.task, .project, .habit].contains($0.kind) }
            default: searchableItems = items
            }
            results += searchableItems
                .filter { $0.title.range(of: needle, options: options) != nil || $0.body.range(of: needle, options: options) != nil || $0.tags.contains(where: { $0.range(of: needle, options: options) != nil }) }
                .map(SearchResult.item)
        }
        if scope == .all || scope == .journal {
            results += journalEntries
                .filter { $0.title.range(of: needle, options: options) != nil || $0.body.range(of: needle, options: options) != nil }
                .map(SearchResult.journal)
        }
        if scope == .all || scope == .files {
            results += documents
                .filter { $0.title.range(of: needle, options: options) != nil || $0.contents.range(of: needle, options: options) != nil }
                .map(SearchResult.document)
        }
        if scope == .all || scope == .settings {
            results += SettingsDestination.allCases
                .filter { $0.title.range(of: needle, options: options) != nil || $0.subtitle.range(of: needle, options: options) != nil }
                .map(SearchResult.setting)
        }
        return results
    }
}

extension WorkspaceStore {
    func saveStatus(for path: String) -> DocumentSaveStatus {
        guard documents.contains(where: { $0.path == path }) else { return .unavailable }
        guard isFolderConnected else { return .unavailable }
        if let error = fileSaveErrors[path] { return .failed(error) }
        return dirtyFilePaths.contains(path) ? .saving : .saved
    }
}
