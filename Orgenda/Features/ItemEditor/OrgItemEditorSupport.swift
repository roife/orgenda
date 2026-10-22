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
            let start = date.orgTimestamp(includesTime: item.hasTime, recurrence: isPrimary ? item.recurrence : nil)
            guard isPrimary, item.durationMinutes >= 0 else { return start }
            let end = date.addingTimeInterval(TimeInterval(item.durationMinutes) * 60)
            // Explicit end dates preserve overnight and multi-day durations;
            // time-only suffixes cannot represent all of these ranges.
            guard item.hasTime || !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: end) else {
                return start
            }
            return start + "--" + end.orgTimestamp(includesTime: item.hasTime)
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
            lines += item.properties.sorted { $0.key < $1.key }.map { ":\($0.key): \($0.value)" }
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

struct OrgItemCaptureSheet: View {
    let store: WorkspaceStore
    let date: Date?

    var body: some View {
        if date == nil {
            ConfiguredCaptureView(store: store)
        } else {
            OrgItemEditor(store: store, draft: newItem)
        }
    }

    private var newItem: OrgItem {
        OrgItem(
            id: UUID(), title: "",
            state: store.configuration.workflow.initial,
            kind: .task, priority: .none, tags: [], scheduled: date, deadline: nil,
            hasTime: false, durationMinutes: 30, recurrence: nil, body: "",
            source: SourceLocation(file: store.configuration.files.inbox, startByte: 0, endByte: 0, startLine: 1),
            habitHistory: []
        )
    }
}

struct OrgItemRefileDestinations: View {
    let targets: [OrgRefileTarget]
    let items: [OrgItem]
    let isMoving: Bool
    let onMove: (OrgRefileTarget) -> Void

    var body: some View {
        List(targets) { target in
            let item = items.first {
                $0.source.file == target.path && $0.source.startByte == target.headingStartByte
            }
            Button { onMove(target) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let item, item.hasWorkflowState { OrgWorkflowIcon(item.state) }
                        Text(target.outline.isEmpty ? target.title : target.outline)
                            .foregroundStyle(item?.workflowTitleColor ?? .primary)
                    }
                    Text(target.path).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .disabled(isMoving)
        }
        .overlay {
            if targets.isEmpty {
                ContentUnavailableView("No destinations yet", systemImage: "folder", description:
                    Text("Create a heading in Actions, Projects, Routines, or Someday to use it as a destination."))
                    .orgendaEmptyState()
            }
        }
        .navigationTitle("Move to")
        .navigationBarTitleDisplayMode(.inline)
    }
}
