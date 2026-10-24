import SwiftUI

struct ConfigurationKeywordEditor: View {
    @Environment(\.dismiss) private var dismiss
    let token: String?
    let terminal: Bool
    let configuration: WorkspaceConfiguration
    let save: (String, WorkspaceConfiguration.Keyword) async throws -> Void
    @State private var keyword: WorkspaceConfiguration.Keyword
    @State private var newToken: String
    @State private var error: String?
    @State private var isSaving = false
    private let originalKeyword: WorkspaceConfiguration.Keyword

    init(token: String?, terminal: Bool, configuration: WorkspaceConfiguration,
         save: @escaping (String, WorkspaceConfiguration.Keyword) async throws -> Void) {
        self.token = token
        self.terminal = terminal
        self.configuration = configuration
        self.save = save
        originalKeyword = token.flatMap { configuration.workflow.keywords[$0] } ?? .init()
        _keyword = State(initialValue: originalKeyword)
        _newToken = State(initialValue: token ?? "")
    }

    var body: some View {
        ConfigurationEditorForm(
            title: token ?? String(localized: "Add state"),
            cancelIdentifier: "configuration.cancelKeyword", saveIdentifier: "configuration.keyword.done",
            hasChanges: hasChanges, isSaving: isSaving, canSave: !resolvedToken.isEmpty,
            error: $error, save: confirm
        ) {
            Form {
                if let error { ConfigurationEditorErrorSection(message: error) }
                Section {
                    Label(preview.title, systemImage: preview.symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(OrgendaTheme.workflowColor(preview))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OrgendaSpacing.contentInset)
                        .accessibilityIdentifier("configuration.keyword.preview")
                }
                Section("Identity") {
                    if let token {
                        LabeledContent("Keyword", value: token)
                    } else {
                        TextField("Keyword", text: $newToken)
                            .textInputAutocapitalization(.characters)
                            .accessibilityIdentifier("configuration.newKeyword")
                    }
                    LabeledContent("Display name") {
                        TextField("Display name", text: $keyword.label, prompt: Text(displayToken))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("configuration.keyword.label")
                    }
                    LabeledContent("Quick selection key") {
                        TextField("Quick selection key", text: $keyword.key, prompt: Text("None"))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("configuration.keyword.key")
                    }
                }
                Section {
                    Picker("Icon", selection: $keyword.icon) {
                        ForEach(ConfigurationIcon.allCases) { icon in
                            Label {
                                Text(LocalizedStringKey(icon.rawValue.capitalized))
                            } icon: {
                                Image(systemName: icon == .default ? defaultIcon.symbol : icon.symbol)
                            }
                            .tag(icon)
                            .accessibilityIdentifier("configuration.keyword.icon.\(icon.rawValue)")
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("configuration.keyword.icon")
                    Picker("Color", selection: $keyword.color) {
                        ForEach(ConfigurationColor.allCases) { color in
                            Label {
                                Text(LocalizedStringKey(color.rawValue.capitalized))
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(color.resolved(or: OrgendaTheme.defaultWorkflowColor(preview)))
                            }
                            .tag(color)
                            .accessibilityIdentifier("configuration.keyword.color.\(color.rawValue)")
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("configuration.keyword.color")
                } header: {
                    Text("Appearance")
                }
                Section("State history") {
                    ConfigurationLogRulePicker(title: "On entering", selection: $keyword.log.enter)
                    ConfigurationLogRulePicker(title: "On leaving", selection: $keyword.log.leave)
                }
                .pickerStyle(.navigationLink)
            }
        }
    }

    private var hasChanges: Bool {
        keyword != originalKeyword || newToken != (token ?? "")
    }

    private var resolvedToken: String {
        token ?? newToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayToken: String {
        resolvedToken.isEmpty ? String(localized: "Keyword") : resolvedToken
    }

    private var defaultIcon: ConfigurationIcon {
        OrgWorkflowState.defaultIcon(for: resolvedToken, terminal: terminal)
    }

    private var preview: OrgWorkflowState {
        OrgWorkflowState(token: displayToken, terminal: terminal, label: keyword.label,
                         icon: keyword.icon, color: keyword.color,
                         enter: keyword.log.enter, leave: keyword.log.leave)
    }

    private func confirm() async {
        guard !isSaving else { return }
        error = nil
        var candidate = configuration
        if token == nil, !candidate.workflow.sequences.isEmpty {
            if terminal { candidate.workflow.sequences[0].terminal.append(resolvedToken) }
            else { candidate.workflow.sequences[0].process.append(resolvedToken) }
        }
        candidate.workflow.keywords[resolvedToken] = keyword
        do {
            try candidate.validate()
        } catch {
            self.error = error.localizedDescription
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await save(resolvedToken, keyword)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ConfigurationTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template: WorkspaceConfiguration.Template
    let store: WorkspaceStore
    let configuration: WorkspaceConfiguration
    let save: (WorkspaceConfiguration.Template) async throws -> Void
    private let originalTemplate: WorkspaceConfiguration.Template
    @State private var outline: String
    @State private var previewTemplate: WorkspaceConfiguration.Template?
    @State private var error: String?
    @State private var isSaving = false
    @State private var showsAdvancedOptions = false

    init(template: WorkspaceConfiguration.Template, store: WorkspaceStore,
         configuration: WorkspaceConfiguration,
         save: @escaping (WorkspaceConfiguration.Template) async throws -> Void) {
        _template = State(initialValue: template)
        _outline = State(initialValue: template.target.outline.joined(separator: "\n"))
        originalTemplate = template
        self.store = store
        self.configuration = configuration
        self.save = save
    }

    var body: some View {
        ConfigurationEditorForm(
            title: String(localized: "Capture template"),
            cancelIdentifier: "configuration.cancelTemplate", saveIdentifier: "configuration.template.done",
            hasChanges: hasChanges, isSaving: isSaving, error: $error, save: confirm
        ) {
            Form {
                if let error { ConfigurationEditorErrorSection(message: error) }
                Section("Template details") {
                    labeledField("Name", text: $template.name, placeholder: "e.g. Inbox task")
                    Picker("Type", selection: $template.type) {
                        Text("Heading").tag(WorkspaceConfiguration.CaptureType.entry)
                        Text("List item").tag(WorkspaceConfiguration.CaptureType.item)
                        Text("Checkbox").tag(WorkspaceConfiguration.CaptureType.checkitem)
                        Text("Plain text").tag(WorkspaceConfiguration.CaptureType.plain)
                    }
                }
                destinationSection
                Section("Org source") {
                    TextEditor(text: $template.template)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Template source")
                        .accessibilityIdentifier("configuration.template.source")
                    DisclosureGroup("Template syntax") {
                        Text("%? — Cursor text\n%^{Title} — Ask for input\n%U — Date and time\n%t — Active date")
                            .font(.body.monospaced()).textSelection(.enabled)
                    }
                    Button("Try template without saving", systemImage: "play") {
                        guard validateFields() else { return }
                        previewTemplate = resolvedTemplate
                    }
                    .accessibilityIdentifier("configuration.template.preview")
                }
                Section {
                    DisclosureGroup("Advanced options", isExpanded: $showsAdvancedOptions) {
                        labeledField("Group", text: $template.group, placeholder: "None")
                        labeledField("Quick selection key", text: $template.key, placeholder: "None")
                        Toggle("Insert before existing entries", isOn: $template.prepend)
                        Stepper("Empty lines: \(template.emptyLines)", value: $template.emptyLines, in: ConfigurationValidation.templateEmptyLines)
                    }
                }
            }
        }
        .sheet(item: $previewTemplate) { candidate in
            ConfiguredCaptureView(store: store, initialTemplate: candidate, previewOnly: true)
        }
    }

    private var destinationSection: some View {
        Section {
            Picker("Target", selection: $template.target.type) {
                Text("File").tag(WorkspaceConfiguration.TargetType.file)
                Text("Heading").tag(WorkspaceConfiguration.TargetType.headline)
                Text("Heading path").tag(WorkspaceConfiguration.TargetType.outline)
                Text("Date tree").tag(WorkspaceConfiguration.TargetType.datetree)
            }
            labeledField("File path", text: $template.target.path, placeholder: "e.g. inbox.org")
            NavigationLink {
                ConfigurationTemplateFilePicker(documents: store.documents.filter { $0.kind == .org },
                                                selection: $template.target.path)
            } label: {
                Label("Choose workspace file", systemImage: "doc")
            }
            .accessibilityIdentifier("configuration.template.chooseFile")
            if template.target.type != .file {
                labeledField("Heading path", text: $outline,
                             placeholder: template.target.type == .datetree ? "Optional parent heading" : "One heading per line")
            }
        } header: {
            Text("Destination")
        }
    }

    private var resolvedTemplate: WorkspaceConfiguration.Template {
        var result = template
        result.target.outline = template.target.type == .file ? [] : ConfigurationSettingsView.lines(outline)
        return result
    }

    private var hasChanges: Bool {
        template != originalTemplate || outline != originalTemplate.target.outline.joined(separator: "\n")
    }

    private func validateFields() -> Bool {
        error = nil
        do {
            try configuration.updating(template: resolvedTemplate).validate()
            return true
        } catch {
            self.error = error.localizedDescription
            showsAdvancedOptions = true
            return false
        }
    }

    private func confirm() async {
        guard !isSaving, validateFields() else { return }
        let value = resolvedTemplate
        isSaving = true
        defer { isSaving = false }
        do {
            try await save(value)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func labeledField(_ title: LocalizedStringKey, text: Binding<String>,
                              placeholder: LocalizedStringKey) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(placeholder), axis: .vertical)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ConfigurationEditorForm<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let cancelIdentifier: String
    let saveIdentifier: String
    let hasChanges: Bool
    let isSaving: Bool
    var canSave = true
    @Binding var error: String?
    let save: () async -> Void
    @ViewBuilder let content: () -> Content
    @State private var showsDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            content()
                .disabled(isSaving)
                .tint(OrgendaTheme.accentText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            if hasChanges { showsDiscardConfirmation = true }
                            else { dismiss() }
                        }
                        .disabled(isSaving)
                        .accessibilityIdentifier(cancelIdentifier)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? String(localized: "Saving…") : String(localized: "Save"), role: .confirm) {
                            Task { await save() }
                        }
                        .disabled(isSaving || !canSave)
                        .accessibilityIdentifier(saveIdentifier)
                    }
                }
                .alert("Discard changes?", isPresented: $showsDiscardConfirmation) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) { }
                } message: {
                    Text("Your changes have not been saved.")
                }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .alert("Unable to save", item: $error) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { message in
            Text(message)
            Text("Your changes are still here. Correct the problem and try saving again.")
        }
    }
}

private struct ConfigurationEditorErrorSection: View {
    let message: String

    var body: some View {
        Section {
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(OrgendaTheme.error)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("configuration.editor.error")
        }
    }
}

private struct ConfigurationTemplateFilePicker: View {
    @Environment(\.dismiss) private var dismiss
    let documents: [WorkspaceDocument]
    @Binding var selection: String
    @State private var search = ""

    private var filteredDocuments: [WorkspaceDocument] {
        documents.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private var selectedPath: Binding<String?> {
        Binding(get: { selection }, set: { path in
            guard let path else { return }
            selection = path
            dismiss()
        })
    }

    var body: some View {
        List(selection: selectedPath) {
            ForEach(filteredDocuments) { document in
                Label(document.path, systemImage: "doc.text")
                    .foregroundStyle(.primary)
                    .tag(document.path)
                    .accessibilityIdentifier("configuration.template.file." + document.path)
            }
        }
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView("No Org files", systemImage: "doc.text", description:
                    Text("No Org files in this workspace yet. Go back and enter a new file path."))
                    .orgendaEmptyState()
            } else if filteredDocuments.isEmpty {
                ContentUnavailableView.search(text: search)
                    .orgendaEmptyState()
            }
        }
        .navigationTitle("Choose workspace file")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search file paths")
    }
}
