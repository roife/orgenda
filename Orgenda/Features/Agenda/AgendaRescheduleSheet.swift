import SwiftUI

struct AgendaRescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: OrgItem
    let onSelect: (Date) -> Void
    @State private var date: Date

    init(item: OrgItem, onSelect: @escaping (Date) -> Void) {
        self.item = item
        self.onSelect = onSelect
        _date = State(initialValue: item.scheduled ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if item.hasWorkflowState { OrgWorkflowIcon(item.state) }
                        Text(item.title).foregroundStyle(item.workflowTitleColor)
                    }
                    .font(.headline)
                    Button("Today") { select(.now) }
                    Button("Tomorrow") { select(Date.now.adding(days: 1)) }
                        .accessibilityIdentifier("agenda.reschedule.tomorrow")
                }
                Section {
                    DatePicker("Scheduled date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("Changes the scheduled day. Existing times, deadlines and repeat rules are kept.")
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule", systemImage: "checkmark", role: .confirm) { select(date) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("agenda.reschedule.save")
                }
            }
        }
    }

    private func select(_ date: Date) { dismiss(); onSelect(date) }
}
