import SwiftUI

/// Surface failed saves without reserving a permanent status row above content.
struct DocumentSaveFailureFeedback: ViewModifier {
    let store: WorkspaceStore
    let path: String
    @State private var showsSaveError = false
    @State private var showsSettings = false

    func body(content: Content) -> some View {
        content
            .onChange(of: store.saveStatus(for: path), initial: true) { _, status in
                if case .failed = status { showsSaveError = true }
            }
            .alert("Changes haven’t been saved", isPresented: $showsSaveError) {
                Button("Retry save") { Task { await store.synchronizeFiles() } }
                Button("Workspace & Sync") { showsSettings = true }
                Button("Keep editing", role: .cancel) {}
            } message: {
                if case .failed(let message) = store.saveStatus(for: path) { Text(message) }
            }
            .sheet(isPresented: $showsSettings) { SettingsView(store: store, initialDestination: .workspace) }
    }
}

struct OrgInsertDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    let session: OrgEditorSession

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Insert date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", systemImage: "checkmark", role: .confirm) {
                        session.insertDate(date)
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("org.editor.date.insert")
                }
            }
        }
    }
}
