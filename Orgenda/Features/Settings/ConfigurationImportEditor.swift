import SwiftUI

struct ConfigurationImportEditor: View {
    @Environment(\.dismiss) private var dismiss
    let importConfiguration: (String) throws -> Void
    @State private var source = ""
    @State private var error: String?
    @State private var showsDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $source)
                        .font(.body.monospaced())
                        .frame(minHeight: 260)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Configuration JSON")
                        .accessibilityIdentifier("configuration.importSource")
                } header: { Text("Paste configuration JSON") }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("configuration.importError")
                    }
                }
            }
            .navigationTitle("Validate configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if source.isEmpty { dismiss() } else { showsDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import configuration") {
                        do { try importConfiguration(source); dismiss() }
                        catch {
                            self.error = ConfigurationImportFailure.message(for: error)
                        }
                    }
                    .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("configuration.reviewImport")
                }
            }
            .confirmationDialog("Discard pasted configuration?", isPresented: $showsDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            }
            .interactiveDismissDisabled(!source.isEmpty)
        }
    }
}
