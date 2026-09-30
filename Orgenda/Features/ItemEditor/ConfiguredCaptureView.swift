import SwiftUI

struct ConfiguredCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    var initialTemplate: WorkspaceConfiguration.Template?
    var previewOnly = false
    @State private var selectedID = ""
    @State private var answers: [Int: String] = [:]
    @State private var text = ""
    @State private var link = ""
    @State private var selection = ""
    @State private var clipboard = ""
    @State private var date = Date.now
    @State private var output: String?
    @State private var baseline: String?
    @State private var configRevision: UInt64 = 0
    @State private var workspaceID: UUID?
    @State private var error: String?
    @State private var createMissing = false
    private var templates: [WorkspaceConfiguration.Template] {
        initialTemplate.map { [$0] } ?? store.configuration.capture.templates
    }
    private var template: WorkspaceConfiguration.Template { templates.first { $0.id == selectedID } ?? templates[0] }
    private var prompts: [ConfiguredCapture.Expansion] { (try? ConfiguredCapture.expansions(in: template.template)) ?? [] }
    var body: some View {
        NavigationStack {
            Form {
                if templates.count > 1 {
                    Picker("Template", selection: $selectedID) {
                        ForEach(Array(Set(templates.map(\.group))).sorted(), id: \.self) { group in
                            Section(group.isEmpty ? "Templates" : group) {
                                ForEach(templates.filter { $0.group == group }) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    Menu("Quick template selection") {
                        ForEach(templates) { candidate in
                            Button(candidate.name) { selectedID = candidate.id }
                                .keyboardShortcut(candidate.key.count == 1 ? candidate.key.first.map {
                                    KeyboardShortcut(KeyEquivalent($0), modifiers: [])
                                } : nil)
                        }
                    }
                }
                Text(template.target.path).font(.caption).foregroundStyle(.secondary)
                DatePicker("Capture date", selection: $date)
                ForEach(prompts.filter { $0.prompt != nil }) { prompt in
                    let binding = Binding(get: { answers[prompt.id] ?? prompt.choices.first ?? "" },
                                          set: { answers[prompt.id] = $0; output = nil })
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
                if template.template.contains("%?") { TextField("Text at cursor", text: $text, axis: .vertical) }
                if template.template.contains("%a") { TextField("Context link", text: $link) }
                if template.template.contains("%i") { TextField("Selected text", text: $selection, axis: .vertical) }
                if template.template.contains("%x") { TextField("Paste clipboard content here", text: $clipboard, axis: .vertical) }
                if !template.target.outline.isEmpty || template.target.type == .datetree {
                    Toggle("Create missing target headings", isOn: $createMissing)
                }
                Button("Preview") { render() }
                if let output {
                    Section("Generated Org") {
                        Text(output).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            .navigationTitle(previewOnly ? "Template preview" : "Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !previewOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Capture") {
                            guard configRevision == store.configurationRevision, workspaceID == store.workspaceFileSessionID else {
                                output = nil; error = "Configuration changed. Preview again before capturing."; return
                            }
                            guard let output else { return }
                            if store.capture(template, rendered: output, date: date, createMissing: createMissing, expectedContents: baseline) { dismiss() }
                            else { error = store.operationError }
                        }.disabled(output == nil)
                    }
                }
            }
        }
        .onAppear { selectedID = initialTemplate?.id ?? store.configuration.capture.defaultTemplate }
        .onChange(of: selectedID) { _, _ in answers = [:]; output = nil }
        .onChange(of: text) { _, _ in output = nil }
        .onChange(of: date) { _, _ in output = nil }
        .onChange(of: link) { _, _ in output = nil }
        .onChange(of: selection) { _, _ in output = nil }
        .onChange(of: clipboard) { _, _ in output = nil }
    }
    private func render() {
        do {
            let rendered = try ConfiguredCapture.render(template.template, answers: answers, cursorText: text, date: date,
                                                       link: link, selection: selection, clipboard: clipboard)
            output = rendered
            baseline = store.documents.first { $0.path == template.target.path }?.contents
            configRevision = store.configurationRevision
            workspaceID = store.workspaceFileSessionID
            error = nil
        } catch { output = nil; self.error = error.localizedDescription }
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
            .onAppear { update() }
            .onChange(of: date) { _, _ in update() }
    }
    private func update() { value = ConfiguredCapture.timestamp(date, active: active, time: includesTime) }
}
