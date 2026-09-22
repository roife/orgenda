import SwiftUI

struct OrgItemDetailsSection: View {
    @Binding var draft: OrgItem
    @Binding var tagsText: String
    @Binding var contextTag: String
    let focusedField: FocusState<OrgItemEditorField?>.Binding
    let usesCaptureTemplates: Bool
    let usesEmacsConfiguration: Bool

    var body: some View {
        Section {
            if draft.kind != .note && draft.kind != .event {
                OrgWorkflowPicker(selection: $draft.state)
                    .accessibilityIdentifier("item.editor.state")
            }

            if !usesCaptureTemplates {
                Picker("Type", selection: $draft.kind) {
                    ForEach(OrgItemKind.allCases) { kind in Label(kind.title, systemImage: kind.systemImage).tag(kind) }
                }
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
            if usesEmacsConfiguration {
                Picker("Context", selection: $contextTag) {
                    Text("None").tag("")
                    Text("@home").tag("@home")
                    Text("@work").tag("@work")
                }
            }
        } header: {
            Text("Details")
        } footer: {
            Text("Separate tags with commas, for example: work, focus")
                .font(.subheadline)
        }
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.subheadline.weight(.medium))
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
