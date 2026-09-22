import SwiftUI

struct JournalComposer: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let date: Date
    @State private var title = ""
    @State private var entryBody = ""
    @State private var showsDiscardConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, body
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                        .font(.headline)
                        .accessibilityIdentifier("journal.composer.title")
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .body }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $entryBody)
                            .frame(minHeight: 220)
                            .focused($focusedField, equals: .body)
                            .accessibilityLabel("Journal entry")
                            .accessibilityIdentifier("journal.composer.body")
                        if entryBody.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                } header: {
                    Text("Entry")
                }
                Section("Destination") {
                    LabeledContent("Date", value: OrgendaDatePresentation.relativeDate(date))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        if hasContent {
                            showsDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        saveEntry()
                    }
                    .disabled(entryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("journal.composer.save")
                }
            }
            .task { focusedField = .body }
            .alert("Discard this entry?", isPresented: $showsDiscardConfirmation) {
                Button("Keep Writing", role: .cancel) {}
                Button("Discard Entry", role: .destructive) { dismiss() }
            } message: {
                Text("Your entry hasn't been saved.")
            }
        }
        .tint(OrgendaTheme.accent)
        .interactiveDismissDisabled(hasContent)
    }

    private var hasContent: Bool {
        !title.isEmpty || !entryBody.isEmpty
    }

    private func saveEntry() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let entryDate = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: calendar.component(.minute, from: now),
            second: calendar.component(.second, from: now),
            of: date
        ) ?? date
        focusedField = nil
        store.addJournalEntry(
            title: trimmedTitle.isEmpty ? String(localized: "Journal entry") : trimmedTitle,
            body: entryBody,
            date: entryDate
        )
        dismiss()
    }
}
