import SwiftUI

struct OrgSourceView: View {
    let item: OrgItem
    let originalSource: String?

    var body: some View {
        HighlightedOrgEditor(text: .constant(originalSource ?? Self.source(for: item)), isEditable: false)
            .navigationTitle("Org Preview")
            .navigationBarTitleDisplayMode(.inline)
    }

    static func source(for item: OrgItem, stateNote: String? = nil) -> String {
        let state = item.hasWorkflowState ? "\(item.state.rawValue) " : ""
        let priority = item.priority == .none ? "" : "[#\(item.priority.rawValue)] "
        let tags = item.tags.isEmpty ? "" : " :\(item.tags.joined(separator: ":")):"
        var lines = ["* \(state)\(priority)\(item.title)\(tags)"]

        func timestamp(_ date: Date, isPrimary: Bool) -> String {
            let formatter = item.hasTime ? WorkspaceStore.orgDateFormatter : WorkspaceStore.orgDayFormatter
            let repeater = isPrimary ? item.recurrence.map { " \($0)" } ?? "" : ""
            let start = "<\(formatter.string(from: date))\(repeater)>"
            guard isPrimary, item.durationMinutes >= 0 else { return start }
            let end = date.addingTimeInterval(TimeInterval(item.durationMinutes) * 60)
            // Explicit end dates preserve overnight and multi-day durations;
            // time-only suffixes cannot represent all of these ranges.
            guard item.hasTime || !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: end) else {
                return start
            }
            return start + "--<\(formatter.string(from: end))>"
        }

        if let scheduled = item.scheduled {
            lines.append("SCHEDULED: \(timestamp(scheduled, isPrimary: true))")
        }
        if let deadline = item.deadline {
            lines.append("DEADLINE: \(timestamp(deadline, isPrimary: item.scheduled == nil))")
        }
        if let closed = item.closed {
            lines.append(OrgSourceMutation.planningSource(keyword: .closed, date: closed, hasTime: true, recurrence: nil))
        }
        if !item.properties.isEmpty {
            lines.append(":PROPERTIES:")
            lines += item.properties.keys.sorted().map { ":\($0): \(item.properties[$0] ?? "")" }
            lines.append(":END:")
        }
        if let eventDate = item.eventDate {
            lines.append(timestamp(eventDate, isPrimary: item.scheduled == nil && item.deadline == nil))
            // Keep the timestamp out of the editable notes paragraph when the
            // recovered Org text is indexed again.
            if !item.body.isEmpty { lines.append("") }
        }
        if !item.body.isEmpty { lines.append(item.body) }
        if let stateNote, !stateNote.isEmpty {
            lines.append("")
            lines.append("# Draft status note (not yet saved):")
            lines += stateNote.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { "# \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}
