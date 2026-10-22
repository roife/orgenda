import SwiftUI

struct OrgItemDetailsSection: View {
    @Binding var draft: OrgItem
    @Binding var tagsText: String
    let focusedField: FocusState<OrgItemEditorField?>.Binding
    let workflow: WorkspaceConfiguration.Workflow

    var body: some View {
        Section {
            if draft.kind != .note && draft.kind != .event {
                OrgWorkflowPicker(selection: $draft.state, states: workflow.states)
                    .accessibilityIdentifier("item.editor.state")
            }

            Picker("Type", selection: $draft.kind) {
                ForEach(OrgItemKind.allCases) { kind in Label(kind.title, systemImage: kind.systemImage).tag(kind) }
            }

            Picker("Priority", selection: $draft.priority) {
                Text("None").tag(OrgPriority.none)
                Text("High · A").tag(OrgPriority.high)
                Text("Medium · B").tag(OrgPriority.medium)
                Text("Low · C").tag(OrgPriority.low)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("item.editor.priority")

            tagsField
        } header: {
            Text("Details")
        } footer: {
            Text("Separate tags with commas, for example: work, focus")
                .font(.subheadline)
        }
    }

    private var tagsField: some View {
        LabeledContent("Tags") {
            TextField("work, focus", text: $tagsText, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: .tags)
                .submitLabel(.done)
                .onSubmit { focusedField.wrappedValue = nil }
                .accessibilityLabel("Tags")
                .accessibilityHint("Separate tags with commas")
                .accessibilityIdentifier("item.editor.tags")
        }
    }

}
