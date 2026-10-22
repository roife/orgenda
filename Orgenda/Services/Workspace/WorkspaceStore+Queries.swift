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
            let dates = [item.scheduled, item.deadline, item.eventDate].compactMap { $0 }
            if dates.contains(where: { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: date) }) { return item }
            if hasWorkspaceConfiguration, let base = item.agendaDate, let repeater = item.recurrence.flatMap(OrgRepeater.init),
               let occurrence = repeater.occurrences(on: date, from: base).first {
                var projected = item
                projected.updateAgendaDate(to: occurrence)
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
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                if $0.source.file != $1.source.file { return $0.source.file < $1.source.file }
                // Entries without a time, or saved in the same minute, retain
                // a deterministic newest-appended-first order after reindexing.
                return $0.source.startByte > $1.source.startByte
            }
    }
    func search(_ query: String, scope: SearchScope) async -> [SearchMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let items = scope == .calendar ? datedItems : (scope == .all || scope == .tasks ? items : [])
        let entries = scope == .all || scope == .journal ? journalEntries : []
        let documents = scope == .all || scope == .files ? documents : []
        let task = Task.detached(priority: .userInitiated) { () -> [SearchMatch] in
            func match(_ text: String) -> Range<String.Index>? {
                text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            }
            var results: [SearchMatch] = []
            for item in items {
                guard !Task.isCancelled else { return [] }
                if scope == .tasks, ![.task, .project, .habit].contains(item.kind) { continue }
                let tags = item.tags.filter { match($0) != nil }
                let bodyMatch = match(item.body)
                guard bodyMatch != nil || !tags.isEmpty || match(item.title) != nil else { continue }
                results.append(SearchMatch(
                    result: .item(item),
                    subtitle: tags.isEmpty ? searchExcerpt(item.body, around: bodyMatch)
                        : tags.map { "#\($0)" }.joined(separator: "  ")
                ))
            }
            for entry in entries {
                guard !Task.isCancelled else { return [] }
                let bodyMatch = match(entry.body)
                guard bodyMatch != nil || match(entry.title) != nil else { continue }
                results.append(SearchMatch(result: .journal(entry), subtitle: searchExcerpt(entry.body, around: bodyMatch)))
            }
            for document in documents where document.kind != .configuration {
                guard !Task.isCancelled else { return [] }
                let bodyMatch = match(document.contents)
                guard bodyMatch != nil || match(document.title) != nil else { continue }
                results.append(SearchMatch(result: .document(document), subtitle: searchExcerpt(document.contents, around: bodyMatch)))
            }
            if scope == .all || scope == .settings {
                for destination in SettingsDestination.allCases {
                    guard !Task.isCancelled else { return [] }
                    if destination.searchTerms.contains(where: { match($0) != nil }) {
                        results.append(SearchMatch(result: .setting(destination), subtitle: destination.subtitle))
                    }
                }
            }
            return results
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

extension WorkspaceStore {
    func saveStatus(for path: String) -> DocumentSaveStatus {
        guard documents.contains(where: { $0.path == path }) else { return .unavailable }
        guard isFolderConnected else { return .unavailable }
        if let error = fileSaveErrors[path] ?? pathSyncErrors[path] { return .failed(error) }
        if dirtyFilePaths.contains(path) { return .saving }
        if syncConflicts.contains(where: { $0.path == path }) { return .conflict }
        if pendingUploadPaths.contains(path) { return .pendingSync }
        return storageConnection?.provider.isRemote == true ? .savedOnDevice : .saved
    }
}
