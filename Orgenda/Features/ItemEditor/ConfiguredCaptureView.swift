import SwiftUI

struct ConfiguredCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let initialTemplate: WorkspaceConfiguration.Template?
    let previewOnly: Bool
    @State private var input: CaptureInput
    @State private var preview: CapturePreview?
    @State private var error: String?
    @State private var createMissing = false

    private struct CaptureInput: Equatable {
        var templateID: String
        var answers: [Int: String] = [:]
        var text = ""
        var link = ""
        var selection = ""
        var clipboard = ""
        var date = Date.now
    }

    private struct CapturePreview {
        let contents: String
        let baseline: String?
        let configurationRevision: UInt64
        let workspaceID: UUID
    }

    private var templates: [WorkspaceConfiguration.Template] {
        initialTemplate.map { [$0] } ?? store.configuration.capture.templates
    }
    private var template: WorkspaceConfiguration.Template { templates.first { $0.id == input.templateID } ?? templates[0] }
    private var prompts: [ConfiguredCapture.Expansion] { (try? ConfiguredCapture.expansions(in: template.template)) ?? [] }

    init(store: WorkspaceStore, initialTemplate: WorkspaceConfiguration.Template? = nil, previewOnly: Bool = false) {
        self.store = store
        self.initialTemplate = initialTemplate
        self.previewOnly = previewOnly
        _input = State(initialValue: CaptureInput(templateID: initialTemplate?.id ?? store.configuration.capture.defaultTemplate))
    }

    var body: some View {
        NavigationStack {
            Form {
                if templates.count > 1 {
                    Picker("Template", selection: $input.templateID) {
                        ForEach(Array(Set(templates.map(\.group))).sorted(), id: \.self) { group in
                            Section(group.isEmpty ? "Templates" : group) {
                                ForEach(templates.filter { $0.group == group }) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    Menu("Quick template selection") {
                        ForEach(templates) { candidate in
                            Button(candidate.name) { input.templateID = candidate.id }
                                .keyboardShortcut(candidate.key.count == 1 ? candidate.key.first.map {
                                    KeyboardShortcut(KeyEquivalent($0), modifiers: [])
                                } : nil)
                        }
                    }
                }
                Text(template.target.path).font(.caption).foregroundStyle(.secondary)
                DatePicker("Capture date", selection: $input.date)
                ForEach(prompts.filter { $0.prompt != nil }) { prompt in
                    let binding = Binding(get: { input.answers[prompt.id] ?? prompt.choices.first ?? "" },
                                          set: { input.answers[prompt.id] = $0 })
                    if let suffix = prompt.token.last, "tTuU".contains(suffix) {
                        ConfigurationCaptureDateField(title: prompt.prompt ?? "", active: suffix == "t" || suffix == "T",
                                                      includesTime: suffix == "T" || suffix == "U", value: binding)
                    } else {
                        TextField(prompt.prompt ?? "", text: binding, axis: .vertical)
                        if !prompt.choices.isEmpty {
                            Menu("Suggestions") {
                                ForEach(prompt.choices, id: \.self) { choice in Button(choice) { binding.wrappedValue = choice } }
                            }
                        }
                    }
                }
                if template.template.contains("%?") { TextField("Text at cursor", text: $input.text, axis: .vertical) }
                if template.template.contains("%a") { TextField("Context link", text: $input.link) }
                if template.template.contains("%i") { TextField("Selected text", text: $input.selection, axis: .vertical) }
                if template.template.contains("%x") { TextField("Paste clipboard content here", text: $input.clipboard, axis: .vertical) }
                if !template.target.outline.isEmpty || template.target.type == .datetree {
                    Toggle("Create missing target headings", isOn: $createMissing)
                }
                Button("Preview", action: render)
                if let preview {
                    Section("Generated Org") {
                        Text(preview.contents).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let error { Text(error).foregroundStyle(OrgendaTheme.error).textSelection(.enabled) }
            }
            .navigationTitle(previewOnly ? "Template preview" : "Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !previewOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Capture", action: capture)
                            .disabled(preview == nil)
                    }
                }
            }
        }
        .onChange(of: input.templateID) { _, _ in input.answers = [:] }
        .onChange(of: input) { _, _ in preview = nil }
    }

    private func render() {
        do {
            let contents = try ConfiguredCapture.render(
                template.template, answers: input.answers, cursorText: input.text, date: input.date,
                link: input.link, selection: input.selection, clipboard: input.clipboard
            )
            preview = CapturePreview(
                contents: contents,
                baseline: store.documents.first { $0.path == template.target.path }?.contents,
                configurationRevision: store.configurationRevision,
                workspaceID: store.workspaceFileSessionID
            )
            error = nil
        } catch {
            preview = nil
            self.error = error.localizedDescription
        }
    }

    private func capture() {
        guard let preview else { return }
        guard preview.configurationRevision == store.configurationRevision,
              preview.workspaceID == store.workspaceFileSessionID else {
            self.preview = nil
            error = "Configuration changed. Preview again before capturing."
            return
        }
        if store.capture(template, rendered: preview.contents, date: input.date,
                         createMissing: createMissing, expectedContents: preview.baseline) {
            dismiss()
        } else {
            error = store.operationError
        }
    }
}

private struct ConfigurationCaptureDateField: View {
    let title: String
    let active: Bool
    let includesTime: Bool
    @Binding var value: String
    @State private var date = Date.now
    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
            .onChange(of: date, initial: true) { _, date in
                value = date.orgTimestamp(active: active, includesTime: includesTime)
            }
    }
}
