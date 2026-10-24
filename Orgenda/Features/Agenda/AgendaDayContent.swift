import SwiftUI

struct AgendaDayContent<Row: View>: View {
    let date: Date
    let dayItems: [OrgItem]
    let journalEntries: [JournalEntry]
    let overdueCount: Int
    let onToggle: (OrgItem) -> Void
    let onOpen: (OrgItem) -> Void
    let onShowInFile: (OrgItem) -> Void
    let onShowOverdue: () -> Void
    @ViewBuilder let row: (OrgItem) -> Row

    @ViewBuilder
    var body: some View {
        let allDayEvents = dayItems.filter { $0.kind == .event && !$0.hasTime }
        let regularItems = dayItems.filter { !($0.kind == .event && !$0.hasTime) }
        if Calendar.autoupdatingCurrent.isDateInToday(date), overdueCount > 0 {
            Button(action: onShowOverdue) {
                Text("\(overdueCount) overdue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OrgendaTheme.overdue)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, OrgendaSpacing.rowInset)
                    .padding(.vertical, OrgendaSpacing.compactInset)
                    .background(OrgendaTheme.tintedBackground(OrgendaTheme.overdue),
                                in: OrgendaCorners.standard)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agenda.showOverdue")
            .padding(.horizontal, OrgendaSpacing.pageMargin)
        }

        ForEach(allDayEvents) { item in
            HStack(spacing: OrgendaSpacing.textGap) {
                if item.canComplete {
                    Button { onToggle(item) } label: {
                        Group {
                            if item.hasWorkflowState {
                                OrgWorkflowIcon(item.state)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(OrgendaTheme.accentText)
                            }
                        }
                            .font(.system(size: 21, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Complete this occurrence")
                    .accessibilityValue(item.hasWorkflowState ? "\(item.title), \(item.state.title)" : item.title)
                    .accessibilityHint("Record completion and advance to the next occurrence")
                    .accessibilityIdentifier("agenda.item.complete.\(item.id)")
                }
                Button { onOpen(item) } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.hasWorkflowState ? item.workflowTitleColor : OrgendaTheme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, OrgendaSpacing.rowInset)
                        .padding(.vertical, OrgendaSpacing.compactInset)
                        .background(item.hasWorkflowState ? OrgendaTheme.tintedBackground(item.workflowTitleColor) : OrgendaTheme.accentSoft,
                                    in: OrgendaCorners.standard)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.leading, item.canComplete ? -OrgendaSpacing.rowInset : 0)
            .buttonStyle(.plain)
            .contextMenu {
                if item.canComplete {
                    Button("Complete this occurrence", systemImage: "checkmark.circle") { onToggle(item) }
                        .accessibilityIdentifier("agenda.item.completeOccurrence")
                }
                Button("Edit", systemImage: "pencil") {
                    onOpen(item)
                }
                Button("Show in File", systemImage: "doc.text.magnifyingglass") { onShowInFile(item) }
                    .accessibilityIdentifier("agenda.item.showInFile")
            } preview: {
                OrgItemContextPreview(item: item)
            }
            .accessibilityAction(named: "Show in File") { onShowInFile(item) }
            .padding(.horizontal, OrgendaSpacing.pageMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if dayItems.isEmpty && journalEntries.isEmpty {
            Text("No scheduled items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, OrgendaSpacing.pageMargin)
                .padding(.vertical, OrgendaSpacing.rowInset)
        } else {
            ForEach(regularItems) { item in
                row(item)
                    .padding(.horizontal, OrgendaSpacing.pageMargin)
            }
        }

        if !journalEntries.isEmpty {
            JournalDayContent(entries: journalEntries)
                .padding(.horizontal, OrgendaSpacing.pageMargin)
                .padding(.top, dayItems.isEmpty ? 0 : OrgendaSpacing.rowInset)
        }
    }

}
