import SwiftUI

struct AgendaPerspectiveContent<Row: View>: View {
    let option: OrgAgendaPerspective
    let groups: [OrgAgendaGroup]
    let deadlines: [OrgItem]
    let overdue: [OrgItem]
    @ViewBuilder let row: (OrgItem) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if groups.allSatisfy({ $0.items.isEmpty }) && deadlines.isEmpty && overdue.isEmpty {
                    ContentUnavailableView(
                        option == .dashboard ? "No items in Dashboard" : "No items",
                        systemImage: option.symbol,
                        description: Text(option == .dashboard
                            ? "Scheduled items and open tasks will appear here."
                            : "Items in this view will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else if option == .dashboard {
                    if !overdue.isEmpty {
                        configuredGroup(OrgAgendaGroup(title: String(localized: "Overdue"), items: overdue))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "Next 7 days"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("agenda.dashboard.dateScope")
                        let dates = groups.filter { $0.isDateGroup && !$0.items.isEmpty }
                        if dates.isEmpty {
                            Text(String(localized: "Nothing scheduled in the next 7 days."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(dates) { configuredGroup($0) }
                    }
                    if !deadlines.isEmpty {
                        configuredGroup(OrgAgendaGroup(title: String(localized: "Deadlines · next 3 days"), items: deadlines))
                    }
                    ForEach(groups.filter { !$0.isDateGroup && !$0.items.isEmpty }) { group in
                        configuredGroup(group)
                    }
                } else {
                    ForEach(groups) { group in
                        Text("\(group.items.count) open")
                            .font(.subheadline).foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(group.items) { item in
                                row(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground))
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("agenda.view.\(option.controlID)")
    }

    private func configuredGroup(_ group: OrgAgendaGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if group.state == nil {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title).font(.headline)
                    Spacer(minLength: 8)
                    Text("\(group.items.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(group.items) { item in
                    row(item)
                }
            }
        }
    }

}
