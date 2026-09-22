import Foundation

struct SearchSuggestions {
    let scope: SearchScope
    let items: [OrgItem]
    let journalEntries: [JournalEntry]
    let documents: [WorkspaceDocument]

    var isAvailable: Bool {
        switch scope {
        case .all:
            !tags.isEmpty || !journalEntries.isEmpty
                || documents.contains { $0.kind != .folder }
        case .tasks, .calendar:
            !tags.isEmpty
        case .journal:
            !journalEntries.isEmpty
        case .files:
            documents.contains { $0.kind != .folder }
        case .settings:
            true
        }
    }

    var tags: [String] {
        guard scope == .all || scope == .tasks || scope == .calendar else { return [] }
        let items = self.items.filter { item in
            switch scope {
            case .tasks: item.kind == .task || item.kind == .project || item.kind == .habit
            case .calendar: item.agendaDate != nil
            default: true
            }
        }
        let counts = items.flatMap(\.tags).reduce(into: [String: Int]()) { counts, tag in
            counts[tag, default: 0] += 1
        }
        return counts.sorted {
            $0.value == $1.value
                ? $0.key.localizedStandardCompare($1.key) == .orderedAscending
                : $0.value > $1.value
        }.prefix(8).map(\.key)
    }

}
