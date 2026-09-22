import SwiftUI

struct AgendaTodoList<Row: View>: View {
    let items: [OrgItem]
    @ViewBuilder let row: (OrgItem) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Unscheduled · \(items.count) open")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                if items.isEmpty {
                    ContentUnavailableView("No open tasks", systemImage: "checkmark.circle", description: Text("Tasks without a schedule appear here."))
                        .padding(.top, 80)
                } else {
                    ForEach(groupedTodos, id: \.0) { file, items in
                        VStack(alignment: .leading, spacing: 0) {
                            Label(file.replacingOccurrences(of: ".org", with: "").capitalized, systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                            ForEach(items) { item in
                                row(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("agenda.view.todos")
    }

    private var groupedTodos: [(String, [OrgItem])] {
        Dictionary(grouping: items, by: { $0.source.file })
            .sorted { $0.key < $1.key }
    }

}

struct AgendaOverdueList<Row: View>: View {
    let items: [OrgItem]
    @ViewBuilder let row: (OrgItem) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Overdue · \(items.count) open")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                if items.isEmpty {
                    ContentUnavailableView("Nothing overdue", systemImage: "checkmark.circle", description: Text("Open items past their scheduled or deadline date appear here."))
                        .padding(.top, 80)
                } else {
                    ForEach(groupedOverdue, id: \.0) { day, items in
                        VStack(alignment: .leading, spacing: 0) {
                            Label(OrgendaDatePresentation.relativeDate(day), systemImage: "calendar.badge.exclamationmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OrgendaTheme.overdue)
                                .padding(.vertical, 8)
                            ForEach(items) { item in
                                row(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .accessibilityIdentifier("agenda.view.overdue")
    }

    private var groupedOverdue: [(Date, [OrgItem])] {
        Dictionary(grouping: items, by: { ($0.agendaDate ?? .distantPast).startOfDay })
            .sorted { $0.key < $1.key }
    }

}
