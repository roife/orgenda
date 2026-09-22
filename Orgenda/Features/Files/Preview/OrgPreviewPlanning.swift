import SwiftUI

struct OrgPreviewPlanning: View {
    let node: ParsedOrgNode
    let pendingReplacements: [String: PendingSourceReplacement]
    let onEdit: (ParsedOrgNode, OrgPlanningEntryDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(entries) { entry in
                let source = pendingReplacements[entry.id]?.replacement ?? entry.text

                if let draft = OrgPlanningEntryDraft(source: source) {
                    OrgPreviewPlanningEntryControl(
                        entry: entry,
                        draft: draft,
                        isUpdating: rowIsUpdating,
                        onEdit: { onEdit(entry, draft) }
                    )
                } else {
                    Label(
                        source.trimmingCharacters(in: .whitespacesAndNewlines),
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(OrgendaTheme.event.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("org.preview.planning.\(node.startByte)")
    }

    private var entries: [ParsedOrgNode] {
        node.children.filter { $0.type == "planning_entry" }
    }

    private var rowIsUpdating: Bool {
        entries.contains { pendingReplacements[$0.id] != nil }
    }
}

struct OrgPreviewPlanningEntryControl: View {
    @Environment(\.locale) private var locale
    @State private var showsRawTimestamp = false
    let entry: ParsedOrgNode
    let draft: OrgPlanningEntryDraft
    let isUpdating: Bool
    let onEdit: () -> Void

    private var presentation: OrgPreviewDateText { OrgPreviewDateText(draft: draft, locale: locale) }

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if showsRawTimestamp {
                        Text(draft.source.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.caption.monospaced())
                    } else {
                        dateLine.font(.caption)
                    }
                }
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "calendar")
                    .font(.system(size: 17))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 11))
                            .background(.background, in: Circle())
                            .offset(x: 4, y: 3)
                    }
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .contextMenu {
            Button {
                showsRawTimestamp.toggle()
            } label: {
                Label(showsRawTimestamp
                    ? presentation.localized("Show readable date", "显示易读日期", "顯示易讀日期")
                    : presentation.localized("Show Org timestamp", "显示 Org 时间戳", "顯示 Org 時間戳"),
                      systemImage: showsRawTimestamp ? "calendar" : "chevron.left.forwardslash.chevron.right")
            }
        }
        .accessibilityLabel(draft.keyword.map { String(localized: "Edit \($0.title) planning") } ?? String(localized: "Edit timestamp"))
        .accessibilityValue(isUpdating
            ? String(localized: "\(showsRawTimestamp ? draft.source : presentation.accessibilityValue), Updating")
            : (showsRawTimestamp ? draft.source : presentation.accessibilityValue))
        .accessibilityHint("Edit the date and repeat rule. Touch and hold to show the Org timestamp.")
        .accessibilityIdentifier("org.preview.\(draft.keyword == nil ? "timestamp" : "planning").entry.\(entry.startByte)")
    }

    private var dateLine: Text {
        let prefix = presentation.keyword.map { "\($0): " } ?? ""
        let details = presentation.details.isEmpty ? "" : " · " + presentation.details.joined(separator: " · ")
        return Text("\(Text(prefix).foregroundStyle(OrgendaTheme.previewMetadata))\(Text(presentation.date).foregroundStyle(.primary))\(Text(details).foregroundStyle(OrgendaTheme.previewMetadata))")
    }

    private var tint: Color {
        switch draft.keyword {
        case .scheduled: OrgendaTheme.event
        case .deadline: OrgendaTheme.overdue
        case .closed: OrgendaTheme.habit
        case nil: OrgendaTheme.weekend
        }
    }
}
