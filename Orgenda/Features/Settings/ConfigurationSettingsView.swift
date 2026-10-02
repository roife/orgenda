import SwiftUI

/// Local draft survives validation and storage failures. Every atomic control
/// edit submits a complete validated snapshot, never a partially edited file.
struct ConfigurationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: WorkspaceStore
    let destination: SettingsDestination
    @State private var draft = WorkspaceConfiguration.standard
    @State private var revision: UInt64 = 0
    @State private var error: String?
    @State private var ready = false
    @State private var changed = false
    @State private var saving = false
    @State private var editGeneration = 0
    @State private var sessionID = UUID()
    @State private var templateEditor: WorkspaceConfiguration.Template?
    @State private var pendingPreset: String?
    @State private var keywordEditor: OrgWorkflowState?
    @State private var showsAddKeyword = false
    @State private var addingToTerminal = false
    @State private var newKeyword = ""
    @FocusState private var addingKeywordFocused: Bool

    var body: some View {
        Group {
            switch destination {
            case .workflow: workflowPage
            case .capture: capturePage
            case .files: filesPage
            case .reminders: remindersPage
            default: configurationFilePage
            }
        }
        .listStyle(.insetGrouped)
        .tint(OrgendaTheme.accentText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(destination.title)
        .task {
            guard !ready else { return }
            draft = store.configuration
            revision = store.configurationRevision
            sessionID = store.workspaceFileSessionID
            ready = true
        }
        .onChange(of: store.configurationRevision) { _, value in
            if !changed {
                draft = store.configuration
                revision = value
            }
        }
        .onChange(of: store.workspaceFileSessionID) { _, _ in
            error = "The workspace changed. Reload settings before applying changes."
        }
        .sheet(item: $templateEditor) { template in
            ConfigurationTemplateEditor(template: template, store: store, configuration: draft) { value in
                var next = draft
                if let index = next.capture.templates.firstIndex(where: { $0.id == value.id }) { next.capture.templates[index] = value }
                else { next.capture.templates.append(value) }
                submit(next)
            }
        }
        .sheet(item: $keywordEditor) { state in
            NavigationStack {
                keywordPage(state.rawValue)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { keywordEditor = nil }
                                .labelStyle(.iconOnly)
                                .accessibilityIdentifier("configuration.keyword.done")
                        }
                    }
            }
        }
        .confirmationDialog("Replace workspace configuration?", isPresented: Binding(
            get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }
        )) {
            Button("Apply preset", role: .destructive) {
                submit(pendingPreset == "classic" ? .classic : .standard)
                pendingPreset = nil
            }
        } message: { Text("This changes configuration only. Existing Org files will not be rewritten.") }
    }

    private var status: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    configurationFileLabel
                    configurationSaveLabel
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        configurationFileLabel
                        Spacer(minLength: 12)
                        configurationSaveLabel.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        configurationFileLabel
                        configurationSaveLabel
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("configuration.status")
    }

    @ViewBuilder
    private var diagnostics: some View {
        if error != nil || store.configurationError != nil || !store.configurationDocument.warnings.isEmpty
            || revision != store.configurationRevision || changed || sessionID != store.workspaceFileSessionID {
            Section {
                if let message = error ?? store.configurationError {
                    Text(message).foregroundStyle(.red).textSelection(.enabled)
                }
                ForEach(store.configurationDocument.warnings, id: \.self) { warning in
                    Text(warning).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                }
                if revision != store.configurationRevision || changed || sessionID != store.workspaceFileSessionID {
                    Button("Reload settings") {
                        draft = store.configuration; revision = store.configurationRevision; changed = false; error = nil
                        sessionID = store.workspaceFileSessionID
                    }.disabled(saving)
                    if revision == store.configurationRevision {
                        Button("Retry changes") { submit(draft) }
                    }
                }
            }
        }
    }

    private var configurationFilePage: some View {
        List {
            Section {
                Button("Apply classic workflow preset") { pendingPreset = "classic" }
                Button("Restore generic defaults", role: .destructive) { pendingPreset = "standard" }
            } header: {
                status
            }
            diagnostics
            Section {
                ScrollView(.horizontal) {
                    Text(OrgCodeHighlighting.attributed(
                        (try? store.configurationDocument.encoded(draft)) ?? "",
                        language: "json",
                        colorScheme: colorScheme,
                        dynamicTypeSize: dynamicTypeSize
                    ))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityIdentifier("configuration.json")
                    .padding(16)
                }
                .listRowInsets(EdgeInsets())
            }
        }
        .contentMargins(.top, 16, for: .scrollContent)
        .listSectionSpacing(20)
        .navigationTitle("Configuration file")
    }

    private var configurationFileLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").accessibilityHidden(true)
            Text(verbatim: "config.json")
        }
        .fixedSize()
    }

    @ViewBuilder
    private var configurationSaveLabel: some View {
        if store.isSavingConfiguration {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).accessibilityHidden(true)
                Text("Saving on this device…")
            }
        } else if store.configurationSource == nil {
            Text("Using defaults")
                .accessibilityHint("config.json is created when you change a setting.")
        } else {
            HStack(spacing: 6) {
                Image(systemName: store.syncState.storageSymbol).accessibilityHidden(true)
                Text(store.syncState.title)
            }
            .foregroundStyle(store.syncState.needsAttention ? Color.red : Color.secondary)
        }
    }

    private var workflowPage: some View {
        List {
            diagnostics
            stateSection(terminal: false)
            stateSection(terminal: true)
            Section("Default actions") {
                defaultStatePicker("New tasks", keyPath: \.initial, terminal: false)
                defaultStatePicker("Mark complete", keyPath: \.complete, terminal: true)
                defaultStatePicker("Reopen", keyPath: \.reopen, terminal: false)
            }
            historySections
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Workflow")
    }

    private var defaultSequence: WorkspaceConfiguration.Sequence {
        draft.workflow.sequences.first ?? .init()
    }

    private func stateSection(terminal: Bool) -> some View {
        let tokens = terminal ? defaultSequence.terminal : defaultSequence.process
        return Section {
            ForEach(tokens, id: \.self) { token in
                Button { keywordEditor = draft.workflow.state(token) } label: {
                    let state = draft.workflow.state(token) ?? OrgWorkflowState(token: token, terminal: terminal)
                    HStack(spacing: 12) {
                        Image(systemName: state.symbol)
                            .foregroundStyle(OrgendaTheme.workflowColor(state))
                            .frame(width: 24)
                        Text(state.title).foregroundStyle(.primary)
                        Spacer()
                        if let key = draft.workflow.keywords[token]?.key, !key.isEmpty {
                            Text(verbatim: key).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("configuration.keyword.\(token)")
                .contextMenu {
                    Button(terminal ? "Move to In progress" : "Move to Terminal") {
                        editSequence { sequence in
                            if terminal {
                                sequence.terminal.removeAll { $0 == token }
                                sequence.process.append(token)
                            } else {
                                sequence.process.removeAll { $0 == token }
                                sequence.terminal.append(token)
                            }
                        }
                    }.disabled(tokens.count <= 1)
                    Button("Remove", role: .destructive) {
                        editSequence {
                            $0.process.removeAll { $0 == token }
                            $0.terminal.removeAll { $0 == token }
                        }
                    }.disabled(tokens.count <= 1)
                }
            }
            .onMove { offsets, destination in
                editSequence {
                    if terminal { $0.terminal.move(fromOffsets: offsets, toOffset: destination) }
                    else { $0.process.move(fromOffsets: offsets, toOffset: destination) }
                }
            }
            if showsAddKeyword && addingToTerminal == terminal {
                HStack {
                    TextField("Keyword", text: $newKeyword)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($addingKeywordFocused)
                        .onSubmit(addKeyword)
                        .accessibilityIdentifier("configuration.newKeyword")
                    Button("Cancel", systemImage: "xmark") {
                        showsAddKeyword = false
                        newKeyword = ""
                        addingKeywordFocused = false
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("configuration.cancelKeyword")
                    Button("Add", systemImage: "checkmark", action: addKeyword)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("configuration.addKeyword")
                }
            } else {
                Button("Add state", systemImage: "plus") {
                    addingToTerminal = terminal
                    newKeyword = ""
                    showsAddKeyword = true
                    addingKeywordFocused = true
                }
                .accessibilityIdentifier(terminal ? "configuration.addTerminal" : "configuration.addProcess")
            }
        } header: {
            Text(terminal ? "Terminal" : "In progress")
        }
    }

    private func defaultStatePicker(_ title: String, keyPath: WritableKeyPath<WorkspaceConfiguration.Sequence, String>,
                                    terminal: Bool) -> some View {
        Picker(title, selection: Binding(get: { defaultSequence[keyPath: keyPath] },
                                         set: { value in editSequence { $0[keyPath: keyPath] = value } })) {
            ForEach(terminal ? defaultSequence.terminal : defaultSequence.process, id: \.self) {
                Text(verbatim: $0).tag($0)
            }
        }
    }

    private func editSequence(_ edit: (inout WorkspaceConfiguration.Sequence) -> Void) {
        var next = draft
        var sequence = defaultSequence
        edit(&sequence)
        if !sequence.process.contains(sequence.initial) { sequence.initial = sequence.process.first ?? "" }
        if !sequence.process.contains(sequence.reopen) { sequence.reopen = sequence.process.first ?? "" }
        if !sequence.terminal.contains(sequence.complete) { sequence.complete = sequence.terminal.first ?? "" }
        next.workflow.sequences = [sequence]
        next.workflow.keywords = next.workflow.keywords.filter { next.workflow.tokens.contains($0.key) }
        submit(next)
    }

    private func addKeyword() {
        let token = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace || "()|:".contains($0) }) else {
            error = String(localized: "Use one keyword without spaces or brackets.")
            return
        }
        guard !draft.workflow.tokens.contains(token) else {
            error = String(localized: "That keyword already exists.")
            return
        }
        editSequence {
            if addingToTerminal { $0.terminal.append(token) }
            else { $0.process.append(token) }
        }
        newKeyword = ""
        showsAddKeyword = false
        addingKeywordFocused = false
    }

    private func keywordPage(_ token: String) -> some View {
        let resolved = draft.workflow.state(token)
        let value = draft.workflow.keywords[token] ?? .init()
        return List {
            diagnostics
            Section {
                if let resolved {
                    Label(resolved.title, systemImage: resolved.symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(OrgendaTheme.workflowColor(resolved))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("configuration.keyword.preview")
                }
            }
            Section("Identity") {
                ConfigurationTextField(title: "Display name", value: value.label, placeholder: token) { updateKeyword(token, change: { $0.label = $1 }, value: $0) }
                ConfigurationTextField(title: "Quick selection key", value: value.key, placeholder: String(localized: "None")) { updateKeyword(token, change: { $0.key = $1 }, value: $0) }
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                    ForEach(ConfigurationIcon.allCases) { icon in
                        Button {
                            updateKeyword(token, change: { $0.icon = $1 }, value: icon)
                        } label: {
                            Image(systemName: icon == .default ? resolved?.symbol ?? "circle" : icon.symbol).font(.title2)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(value.icon == icon ? OrgendaTheme.accentSoft : Color(uiColor: .tertiarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .bottomTrailing) {
                                    if value.icon == icon {
                                        Image(systemName: "checkmark.circle.fill").font(.caption2)
                                            .foregroundStyle(OrgendaTheme.accentText).padding(3)
                                    }
                                }
                        }.buttonStyle(.plain).accessibilityLabel(icon.rawValue)
                            .accessibilityAddTraits(value.icon == icon ? .isSelected : [])
                    }
                }
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                    ForEach(ConfigurationColor.allCases) { color in
                        Button {
                            updateKeyword(token, change: { $0.color = $1 }, value: color)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color.resolved(or: resolved.map(OrgendaTheme.defaultWorkflowColor) ?? .primary))
                                    .frame(width: 30, height: 30)
                                if value.color == color {
                                    Circle().strokeBorder(OrgendaTheme.accentText, lineWidth: 2)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "checkmark").font(.caption.bold())
                                        .foregroundStyle(.white).shadow(color: .black, radius: 1)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.rawValue.capitalized)
                        .accessibilityAddTraits(value.color == color ? .isSelected : [])
                    }
                }
            } header: {
                Text("Color")
            }
            Section {
                rulePicker("On entering", value: value.log.enter) { updateKeyword(token, change: { $0.log.enter = $1 }, value: $0) }
                rulePicker("On leaving", value: value.log.leave) { updateKeyword(token, change: { $0.log.leave = $1 }, value: $0) }
            } header: {
                Text("State history")
            }
        }.navigationTitle(token)
    }

    private var capturePage: some View {
        List {
            diagnostics
            Section {
                Picker("Default template", selection: binding(\.capture.defaultTemplate)) {
                    ForEach(draft.capture.templates) { Text($0.name).tag($0.id) }
                }
            }
            Section("Templates") {
                ForEach(draft.capture.templates) { template in
                    Button { templateEditor = template } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(OrgendaTheme.accentText)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name).foregroundStyle(.primary)
                                Text(template.target.path).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if !template.key.isEmpty {
                                Text(verbatim: template.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("configuration.template.\(template.id)")
                }
                .onMove { indices, offset in var next = draft; next.capture.templates.move(fromOffsets: indices, toOffset: offset); submit(next) }
                .onDelete { indices in
                    var next = draft
                    next.capture.templates.remove(atOffsets: indices)
                    guard let first = next.capture.templates.first else { return }
                    if !next.capture.templates.contains(where: { $0.id == next.capture.defaultTemplate }) {
                        next.capture.defaultTemplate = first.id
                    }
                    submit(next)
                }
                .deleteDisabled(draft.capture.templates.count == 1)
            }
            Section {
                Button("Add template", systemImage: "plus") {
                    templateEditor = .init(id: UUID().uuidString, name: "New template", key: "",
                                           target: .init(path: draft.files.inbox))
                }
            }
        }.navigationTitle("Capture templates").toolbar { EditButton() }
    }

    private var agendaSections: some View {
        Group {
            Section {
                ConfigurationTextField(title: "Included paths", value: draft.agenda.sources.joined(separator: "\n"),
                                       placeholder: String(localized: "All Org files")) {
                    var next = draft; next.agenda.sources = Self.lines($0); submit(next)
                }
            } header: {
                Text("Agenda sources")
            } footer: {
                Text("One file or directory per line. Leave empty to include all Org files.")
            }
            Section {
                ConfigurationTextField(title: "Excluded paths", value: draft.agenda.excluded.joined(separator: "\n"),
                                       placeholder: String(localized: "None")) {
                    var next = draft; next.agenda.excluded = Self.lines($0); submit(next)
                }
            }
        }
    }

    private var filesPage: some View {
        List {
            diagnostics
            agendaSections
            Section {
                text("Inbox file", \.files.inbox)
                text("Attachment directory", \.files.attachments)
                text("Journal directory", \.files.journal)
            } header: {
                Text("Default locations")
            }
            Section {
                text("Archive location", \.files.archive)
            } header: {
                Text("Archive")
            } footer: {
                Text("Use %s for the source filename and :: to specify the destination heading.")
            }
            Section("Refile") {
                ConfigurationTextField(title: "Target files", value: draft.files.refile.joined(separator: "\n"),
                                       placeholder: String(localized: "One file per line")) {
                    var next = draft; next.files.refile = Self.lines($0); submit(next)
                }
                Stepper("Maximum heading level: \(draft.files.refileMaxLevel)", value: binding(\.files.refileMaxLevel), in: 1...99)
            }
        }.navigationTitle("Files & agenda")
    }

    private var historySections: some View {
        Group {
            Section("History") {
                rulePicker("On completion", value: draft.logging.done) { var next = draft; next.logging.done = $0; submit(next) }
                rulePicker("Reschedule", value: draft.logging.reschedule) { var next = draft; next.logging.reschedule = $0; submit(next) }
                rulePicker("Change deadline", value: draft.logging.redeadline) { var next = draft; next.logging.redeadline = $0; submit(next) }
            }
            Section {
                text("Log drawer", \.logging.drawer)
            } footer: {
                Text("Leave empty to write history in the entry body.")
            }
        }
    }

    private var remindersPage: some View {
        List {
            diagnostics
            ReminderSettingsSections(store: store)
            Section {
                Stepper("Advance: \(draft.reminders.advanceMinutes) minutes", value: binding(\.reminders.advanceMinutes), in: 0...1440)
                Stepper("Repeat: \(draft.reminders.repeatMinutes) minutes", value: binding(\.reminders.repeatMinutes), in: 1...1440)
                Stepper("Deadline warning: \(draft.reminders.deadlineWarningDays) days", value: binding(\.reminders.deadlineWarningDays), in: 0...365)
            } header: {
                Text("Workspace timing")
            }
            .disabled(!store.isWorkspaceReady)
        }.navigationTitle("Reminders")
    }

    private func text(_ title: String, _ path: WritableKeyPath<WorkspaceConfiguration, String>) -> some View {
        ConfigurationTextField(title: title, value: draft[keyPath: path]) { value in
            var next = draft; next[keyPath: path] = value; submit(next)
        }
    }
    private func binding<Value>(_ path: WritableKeyPath<WorkspaceConfiguration, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: path] }, set: { value in var next = draft; next[keyPath: path] = value; submit(next) })
    }
    private func rulePicker(_ title: String, value: WorkspaceConfiguration.LogRule,
                            change: @escaping (WorkspaceConfiguration.LogRule) -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: change)) {
            Text("Don't log").tag(WorkspaceConfiguration.LogRule.none)
            Text("Timestamp").tag(WorkspaceConfiguration.LogRule.time)
            Text("Ask for a note").tag(WorkspaceConfiguration.LogRule.note)
        }
    }
    private func updateKeyword<Value>(_ token: String, change: (inout WorkspaceConfiguration.Keyword, Value) -> Void, value: Value) {
        var next = draft
        var keyword = next.workflow.keywords[token] ?? .init()
        change(&keyword, value)
        next.workflow.keywords[token] = keyword
        submit(next)
    }
    private func submit(_ value: WorkspaceConfiguration) {
        guard ready else { return }
        guard sessionID == store.workspaceFileSessionID else {
            error = "The workspace changed. Reload settings before applying changes."
            return
        }
        draft = value
        changed = true
        editGeneration += 1
        do { try value.validate() }
        catch { self.error = error.localizedDescription; return }
        error = nil
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            while changed {
                let submittedGeneration = editGeneration
                let submitted = draft
                do { try submitted.validate() }
                catch { self.error = error.localizedDescription; return }
                guard await store.saveConfiguration(submitted, expectedRevision: revision) else {
                    error = store.configurationError; return
                }
                revision = store.configurationRevision
                if submittedGeneration == editGeneration { changed = false }
            }
        }
    }
    static func lines(_ value: String) -> [String] {
        value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct ConfigurationTextField: View {
    let title: String
    let value: String
    var placeholder = ""
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.subheadline)
            TextField(placeholder.isEmpty ? title : placeholder, text: $text, axis: .vertical).lineLimit(1...8)
                .font(.body).foregroundStyle(.secondary)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                .onSubmit { save() }
                .accessibilityLabel(LocalizedStringKey(title))
        }
        .padding(.vertical, 3)
        .onAppear { text = value }
        .onChange(of: value) { _, value in if !focused { text = value } }
        .onChange(of: focused) { _, focused in if !focused { save() } }
        .onDisappear { save() }
    }
    private func save() { if text != value { commit(text) } }
}
