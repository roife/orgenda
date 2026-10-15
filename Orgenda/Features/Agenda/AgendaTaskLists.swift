import SwiftUI

struct AgendaTodoList<Row: View>: View {
    let items: [OrgItem]
    @ViewBuilder let row: (OrgItem) -> Row

    var body: some View {
        List {
            if !items.isEmpty {
                ForEach(groupedTodos, id: \.0) { file, items in
                    Section {
                        ForEach(items, content: row)
                    } header: {
                        Label(file.replacingOccurrences(of: ".org", with: "").capitalized, systemImage: "doc.text")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.primary.opacity(0.7))
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        }
        .agendaListSurface()
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No open tasks", systemImage: "checkmark.circle", description: Text("Tasks without a schedule appear here."))
                    .orgendaEmptyState()
            }
        }
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
        List {
            if !items.isEmpty {
                ForEach(groupedOverdue, id: \.0) { day, items in
                    Section {
                        ForEach(items, content: row)
                    } header: {
                        Label(OrgendaDatePresentation.relativeDate(day), systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(OrgendaTheme.overdue)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        }
        .agendaListSurface()
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing overdue", systemImage: "checkmark.circle", description: Text("Open items past their scheduled or deadline date appear here."))
                    .orgendaEmptyState()
            }
        }
        .accessibilityIdentifier("agenda.view.overdue")
    }

    private var groupedOverdue: [(Date, [OrgItem])] {
        Dictionary(grouping: items, by: { ($0.agendaDate ?? .distantPast).startOfDay })
            .sorted { $0.key < $1.key }
    }
}

extension View {
    func agendaListSurface() -> some View {
        listStyle(.plain)
            .listSectionSpacing(8)
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
    }
}
