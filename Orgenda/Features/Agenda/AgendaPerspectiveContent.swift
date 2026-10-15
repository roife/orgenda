import SwiftUI

struct AgendaPerspectiveContent<Row: View>: View {
    @Environment(\.workspaceConfiguration) private var configuration
    let option: OrgAgendaPerspective
    let groups: [OrgAgendaGroup]
    let deadlines: [OrgItem]
    let overdue: [OrgItem]
    @ViewBuilder let row: (OrgItem) -> Row

    private var isEmpty: Bool {
        groups.allSatisfy { $0.items.isEmpty } && deadlines.isEmpty && overdue.isEmpty
    }

    var body: some View {
        List {
            if !isEmpty {
                if option == .dashboard {
                    if !overdue.isEmpty {
                        configuredGroup(OrgAgendaGroup(title: String(localized: "Overdue"), items: overdue))
                    }
                    Text("Next 7 days")
                        .font(.headline)
                        .listRowSeparator(.hidden)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("agenda.dashboard.dateScope")
                    let dates = groups.filter { $0.isDateGroup && !$0.items.isEmpty }
                    if dates.isEmpty {
                        Text("Nothing scheduled in the next 7 days.")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(dates) { configuredGroup($0) }
                    if !deadlines.isEmpty {
                        configuredGroup(OrgAgendaGroup(title: String(localized: "Deadlines · next \(configuration.reminders.deadlineWarningDays) days"), items: deadlines))
                    }
                    ForEach(groups.filter { !$0.isDateGroup && !$0.items.isEmpty }) { configuredGroup($0) }
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items, content: row)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
            }
        }
        .agendaListSurface()
        .overlay {
            if isEmpty {
                ContentUnavailableView(
                    option == .dashboard ? "No items in Dashboard" : "No items",
                    systemImage: option.symbol,
                    description: Text(option == .dashboard
                        ? "Scheduled items and open tasks will appear here."
                        : "Items in this view will appear here.")
                )
                .orgendaEmptyState()
            }
        }
        .accessibilityIdentifier("agenda.view.\(option.controlID)")
    }

    private func configuredGroup(_ group: OrgAgendaGroup) -> some View {
        Section {
            ForEach(group.items) { item in
                row(item)
                    .id("\(group.id):\(item.id)")
            }
        } header: {
            if group.state == nil {
                LabeledContent(group.title, value: "\(group.items.count)")
                    .accessibilityElement(children: .combine)
            }
        }
        .listSectionSeparator(.hidden)
        .id(group.id)
    }
}
