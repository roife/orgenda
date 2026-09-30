import SwiftUI

struct ConfigurationTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: WorkspaceConfiguration.Template
    let store: WorkspaceStore
    let configuration: WorkspaceConfiguration
    let save: (WorkspaceConfiguration.Template) -> Void
    @State private var outline = ""
    @State private var preview = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Template details") {
                    labeledField("Name", text: $template.name)
                    labeledField("Group", text: $template.group)
                    labeledField("Quick selection key", text: $template.key)
                    Picker("Type", selection: $template.type) {
                        Text("Heading").tag(WorkspaceConfiguration.CaptureType.entry)
                        Text("List item").tag(WorkspaceConfiguration.CaptureType.item)
                        Text("Checkbox").tag(WorkspaceConfiguration.CaptureType.checkitem)
                        Text("Plain text").tag(WorkspaceConfiguration.CaptureType.plain)
                    }
                }
                Section("Destination") {
                    Picker("Target", selection: $template.target.type) {
                        Text("File").tag(WorkspaceConfiguration.TargetType.file)
                        Text("Heading").tag(WorkspaceConfiguration.TargetType.headline)
                        Text("Heading path").tag(WorkspaceConfiguration.TargetType.outline)
                        Text("Date tree").tag(WorkspaceConfiguration.TargetType.datetree)
                    }
                    labeledField("File path", text: $template.target.path)
                    if store.documents.contains(where: { $0.kind == .org }) {
                        Menu("Choose existing file") {
                            ForEach(store.documents.filter { $0.kind == .org }) { document in
                                Button(document.path) { template.target.path = document.path }
                            }
                        }
                    }
                    if template.target.type != .file {
                        labeledField("Heading path", text: $outline)
                    }
                }
                Section("Org source") {
                    TextEditor(text: $template.template)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .accessibilityLabel("Template source")
                    DisclosureGroup("Template syntax") {
                        Text("%? — Cursor text\n%^{Title} — Ask for input\n%U — Date and time\n%t — Active date")
                            .font(.body.monospaced()).textSelection(.enabled)
                    }
                    Button("Try template without saving", systemImage: "play") {
                        template.target.outline = ConfigurationSettingsView.lines(outline)
                        preview = true
                    }
                }
                Section("Insertion") {
                    Toggle("Prepend", isOn: $template.prepend)
                    Stepper("Empty lines: \(template.emptyLines)", value: $template.emptyLines, in: 0...10)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(OrgendaTheme.accentText)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle("Capture template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        template.target.outline = ConfigurationSettingsView.lines(outline)
                        var candidate = configuration
                        if let index = candidate.capture.templates.firstIndex(where: { $0.id == template.id }) {
                            candidate.capture.templates[index] = template
                        } else {
                            candidate.capture.templates.append(template)
                        }
                        do { try candidate.validate(); save(template); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("configuration.template.done")
                }
            }
            .sheet(isPresented: $preview) { ConfiguredCaptureView(store: store, initialTemplate: template, previewOnly: true) }
        }.onAppear { outline = template.target.outline.joined(separator: "\n") }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.subheadline)
            TextField(title, text: text, axis: .vertical)
                .foregroundStyle(.secondary)
                .accessibilityLabel(LocalizedStringKey(title))
        }.padding(.vertical, 3)
    }
}
