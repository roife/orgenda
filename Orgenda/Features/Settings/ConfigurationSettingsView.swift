import SwiftUI
import UniformTypeIdentifiers

/// Valid edits save automatically. Failed or invalid edits remain available to correct.
struct ConfigurationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: WorkspaceStore
    let destination: SettingsDestination
    var openWorkspace: () -> Void = {}
    @State private var draft = WorkspaceConfiguration.standard
    @State private var revision: UInt64 = 0
    @State private var error: String?
    @State private var ready = false
    @State private var baseline = WorkspaceConfiguration.standard
    @State private var saving = false
    @State private var leaving = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var saveTask: Task<Bool, Never>?
    @State private var sessionID = UUID()
    @State private var templateEditor: WorkspaceConfiguration.Template?
    @State private var pendingPreset: String?
    @State private var keywordEditor: KeywordEditorDestination?
    @State private var reminderEditor: ReminderTimingKind?
    @State private var pendingExit: ExitDestination?
    @State private var pendingSequence: WorkspaceConfiguration?
    @State private var showsSaveError = false
    @State private var showsImporter = false
    @State private var importedDocument: ConfigurationDocument?
    @State private var undoDocument: ConfigurationDocument?
    @State private var replacementID: UUID?
    @State private var showsJSON = false
    @State private var showsPastedImport = false

    private enum ExitDestination { case back, workspace, reload }
    private var changed: Bool { draft != baseline || importedDocument != nil }
    private var configurationWarnings: [String] { (importedDocument ?? store.configurationDocument).warnings }

    private struct KeywordEditorDestination: Identifiable {
        let token: String?
        let terminal: Bool
        var id: String { token ?? (terminal ? "add-terminal" : "add-process") }
    }

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
        .disabled(!ready || leaving)
        .listStyle(.insetGrouped)
        .tint(OrgendaTheme.accentText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(destination.title)
        .task {
            guard !ready else { return }
            draft = store.configuration
            baseline = draft
            revision = store.configurationRevision
            sessionID = store.workspaceFileSessionID
            ready = true
        }
        .onChange(of: store.configurationRevision) { _, value in
            if value != revision && !saving {
                undoDocument = nil
                error = String(localized: "The configuration changed. Reload before applying this edit.")
            }
        }
        .onChange(of: store.workspaceFileSessionID) { _, _ in
            undoDocument = nil
            error = String(localized: "The workspace changed. Reload settings before applying changes.")
        }
        .sheet(item: $templateEditor) { template in
            ConfigurationTemplateEditor(template: template, store: store, configuration: draft) { value in
                var next = draft
                if let index = next.capture.templates.firstIndex(where: { $0.id == value.id }) { next.capture.templates[index] = value }
                else { next.capture.templates.append(value) }
                try await persist(next)
            }
        }
        .sheet(item: $keywordEditor) { editor in
            ConfigurationKeywordEditor(token: editor.token, terminal: editor.terminal, configuration: draft) { token, keyword in
                var next = draft
                if editor.token == nil {
                    var sequence = defaultSequence
                    if editor.terminal { sequence.terminal.append(token) }
                    else { sequence.process.append(token) }
                    next.workflow.sequences = [sequence]
                }
                next.workflow.keywords[token] = keyword
                try await persist(next)
            }
        }
        .sheet(item: $reminderEditor) { kind in
            ReminderTimingEditor(kind: kind, value: binding(kind.configurationPath))
        }
        .navigationBarBackButtonHidden()
        .interactiveDismissDisabled(changed || saving || leaving)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") { requestExit(.back) }
                    .disabled(!ready || leaving)
                    .accessibilityIdentifier("configuration.back")
            }
        }
        .alert(LocalizedStringKey(pendingPreset == "classic" ? "Replace task states?" : "Replace workspace configuration?"),
                            isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
                            presenting: pendingPreset) { preset in
            Button("Apply", role: .destructive) {
                let value = preset == "classic" ? draft.applyingClassicWorkflowPreset() : .standard
                if value != draft {
                    replacementID = UUID()
                    submit(value)
                }
                pendingPreset = nil
            }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: { preset in
            if preset == "classic" {
                Text("Replace task states, their appearance, state history and default actions. Templates, file locations, global history rules and reminders stay as they are. Existing Org files keep their keywords. Changes save automatically.")
            } else {
                Text("Replace task states, templates, file locations, agenda sources, history and reminder rules with defaults. Existing Org files will not be rewritten. You can undo this replacement after saving.")
            }
        }
        .alert("Unsaved changes", isPresented: Binding(
            get: { pendingExit != nil }, set: { if !$0 { pendingExit = nil } }
        ), presenting: pendingExit) { target in
            if target != .reload {
                Button("Save and continue") {
                    pendingExit = nil
                    Task { if await saveDraft() { leave(target) } }
                }
            }
            Button("Discard changes", role: .destructive) {
                pendingExit = nil
                reload()
                leave(target)
            }
            Button("Keep editing", role: .cancel) { pendingExit = nil }
        } message: { _ in Text("Your changes have not been saved to the workspace.") }
        .alert("Update default task actions?", isPresented: Binding(
            get: { pendingSequence != nil }, set: { if !$0 { pendingSequence = nil } }
        ), presenting: pendingSequence) { next in
            Button("Update actions", role: .destructive) {
                submit(next)
                pendingSequence = nil
            }
            Button("Cancel", role: .cancel) { pendingSequence = nil }
        } message: { next in
            if let sequence = next.workflow.sequences.first {
                Text("New tasks: \(sequence.initial). Mark complete: \(sequence.complete). Reopen: \(sequence.reopen). Existing Org files will not be rewritten.")
            }
        }
        .alert("Could Not Save Settings", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) { }
        } message: { Text(error ?? String(localized: "Your changes are still available. Try saving again.")) }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try stageImport(String(contentsOf: url, encoding: .utf8))
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
                self.error = ConfigurationImportFailure.message(for: error)
                showsSaveError = true
            }
        }
        .sheet(isPresented: $showsPastedImport) {
            ConfigurationImportEditor { source in try stageImport(source) }
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        // A pending save is normal. Inserting recovery rows during a native
        // reorder shifts every section, then shifts them back when saving ends.
        let needsRecovery = !saving && revision != store.configurationRevision
            || sessionID != store.workspaceFileSessionID
        if error != nil || store.configurationError != nil || !configurationWarnings.isEmpty
            || needsRecovery {
            Section {
                if let message = error ?? store.configurationError {
                    Text(message).foregroundStyle(.red).textSelection(.enabled)
                }
                ForEach(configurationWarnings, id: \.self) { warning in
                    Text(warning).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                }
                if needsRecovery {
                    Button("Reload settings") {
                        if changed { pendingExit = .reload }
                        else { reload() }
                    }.disabled(saving)
                }
                if changed && !saving && !needsRecovery {
                    Button("Retry changes") { Task { await saveDraft() } }
                }
            }
        }
    }

    private var configurationFilePage: some View {
        List {
            diagnostics
            ConfigurationPromptSection(configuration: draft)
            Section {
                Button("Import configuration file", systemImage: "square.and.arrow.down") { showsImporter = true }
                    .accessibilityIdentifier("configuration.importFile")
                Button("Paste configuration JSON", systemImage: "doc.on.clipboard") { showsPastedImport = true }
                    .accessibilityIdentifier("configuration.pasteJSON")
            }
            Section("Presets") {
                Button("Apply classic workflow preset") { pendingPreset = "classic" }
                    .accessibilityIdentifier("configuration.classicPreset")
            }
            Section {
                DisclosureGroup("View configuration JSON", isExpanded: $showsJSON) {
                    ScrollView(.horizontal) {
                        Text(OrgCodeHighlighting.attributed(
                            (try? (importedDocument ?? store.configurationDocument).encoded(draft)) ?? "",
                            language: "json", colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize
                        ))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityIdentifier("configuration.json")
                    }
                }
                .accessibilityIdentifier("configuration.showJSON")
            }
            Section {
                Button("Restore generic defaults", role: .destructive) { pendingPreset = "standard" }
                    .accessibilityIdentifier("configuration.reset")
                if let undoDocument, revision == store.configurationRevision, sessionID == store.workspaceFileSessionID {
                    Button("Undo last replacement", systemImage: "arrow.uturn.backward") {
                        importedDocument = undoDocument
                        draft = undoDocument.configuration
                        replacementID = nil
                        Task { if await saveDraft() { self.undoDocument = nil } }
                    }
                    .disabled(changed || saving)
                    .accessibilityIdentifier("configuration.undoReplacement")
                }
            } header: {
                Text("Reset configuration")
            }
        }
        .navigationTitle("Configuration file")
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
                Button { keywordEditor = .init(token: token, terminal: terminal) } label: {
                    let state = draft.workflow.state(token) ?? OrgWorkflowState(token: token, terminal: terminal)
                    HStack(spacing: 12) {
                        Image(systemName: state.symbol)
                            .foregroundStyle(OrgendaTheme.workflowColor(state))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.title).foregroundStyle(.primary)
                            if state.title != token { Text(verbatim: token).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if let key = draft.workflow.keywords[token]?.key, !key.isEmpty {
                            Text(verbatim: key).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("configuration.keyword.\(token)")
                .contextMenu {
                    if tokens.count > 1 {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            editSequence {
                                $0.process.removeAll { $0 == token }
                                $0.terminal.removeAll { $0 == token }
                            }
                        }
                        .accessibilityIdentifier("configuration.keyword.remove.\(token)")
                        Button(LocalizedStringKey(terminal ? "Move to In progress" : "Move to Terminal"), systemImage: "arrow.up.arrow.down") {
                            editSequence { sequence in
                                if terminal {
                                    sequence.terminal.removeAll { $0 == token }
                                    sequence.process.append(token)
                                } else {
                                    sequence.process.removeAll { $0 == token }
                                    sequence.terminal.append(token)
                                }
                            }
                        }
                        .tint(.blue)
                        .accessibilityIdentifier("configuration.keyword.move.\(token)")
                    }
                }
            }
            .onMove { offsets, destination in
                editSequence {
                    if terminal { $0.terminal.move(fromOffsets: offsets, toOffset: destination) }
                    else { $0.process.move(fromOffsets: offsets, toOffset: destination) }
                }
            }
            Button("Add state", systemImage: "plus") {
                keywordEditor = .init(token: nil, terminal: terminal)
            }
            .accessibilityIdentifier(terminal ? "configuration.addTerminal" : "configuration.addProcess")
        } header: {
            Text(LocalizedStringKey(terminal ? "Terminal" : "In progress"))
        }
    }

    private func defaultStatePicker(_ title: String, keyPath: WritableKeyPath<WorkspaceConfiguration.Sequence, String>,
                                    terminal: Bool) -> some View {
        let token = defaultSequence[keyPath: keyPath]
        let state = draft.workflow.state(token) ?? OrgWorkflowState(token: token, terminal: terminal)
        // A menu label keeps explicit spacing; Picker compacts its selected-value label.
        return Menu {
            Picker(LocalizedStringKey(title), selection: Binding(get: { defaultSequence[keyPath: keyPath] },
                                         set: { value in editSequence { $0[keyPath: keyPath] = value } })) {
                ForEach(terminal ? defaultSequence.terminal : defaultSequence.process, id: \.self) { token in
                    let state = draft.workflow.state(token) ?? OrgWorkflowState(token: token, terminal: terminal)
                    Label {
                        Text(stateLabel(token))
                    } icon: {
                        Image(systemName: state.symbol)
                            .foregroundStyle(OrgendaTheme.workflowColor(state))
                    }
                    .tag(token)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(Color.primary)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: state.symbol)
                        .accessibilityHidden(true)
                    Text(stateLabel(token))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(LocalizedStringKey(title))
        .accessibilityValue(stateLabel(token))
    }

    private func editSequence(_ edit: (inout WorkspaceConfiguration.Sequence) -> Void) {
        var next = draft
        var sequence = defaultSequence
        edit(&sequence)
        let repairsDefaults = !sequence.process.contains(sequence.initial)
            || !sequence.process.contains(sequence.reopen) || !sequence.terminal.contains(sequence.complete)
        if !sequence.process.contains(sequence.initial) { sequence.initial = sequence.process.first ?? "" }
        if !sequence.process.contains(sequence.reopen) { sequence.reopen = sequence.process.first ?? "" }
        if !sequence.terminal.contains(sequence.complete) { sequence.complete = sequence.terminal.first ?? "" }
        next.workflow.sequences = [sequence]
        next.workflow.keywords = next.workflow.keywords.filter { next.workflow.tokens.contains($0.key) }
        if repairsDefaults {
            pendingSequence = next
        } else { submit(next) }
    }

    private func stateLabel(_ token: String) -> String {
        let title = draft.workflow.state(token)?.title ?? token
        return title == token ? token : "\(title) (\(token))"
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
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("configuration.template.\(template.id)")
                }
                .onMove { indices, offset in
                    var next = draft
                    next.capture.templates.move(fromOffsets: indices, toOffset: offset)
                    submit(next)
                }
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
                    templateEditor = .init(id: UUID().uuidString, name: String(localized: "New template"), key: "",
                                           target: .init(path: draft.files.inbox))
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Capture templates")
    }

    private var filesPage: some View {
        List {
            diagnostics
            ConfigurationFilesSections(store: store, draft: Binding(get: { draft }, set: submit))
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
            }
        }
    }

    private var remindersPage: some View {
        List {
            diagnostics
            ReminderSettingsSections(store: store, openWorkspace: { requestExit(.workspace) })
            WorkspaceReminderTimingSections(advance: binding(\.reminders.advanceMinutes),
                                            repeatInterval: binding(\.reminders.repeatMinutes),
                                            deadline: binding(\.reminders.deadlineWarningDays)) { reminderEditor = $0 }
                .disabled(!store.isWorkspaceReady)
        }.navigationTitle("Reminders")
    }

    private func text(_ title: String, _ path: WritableKeyPath<WorkspaceConfiguration, String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.subheadline)
            TextField(LocalizedStringKey(title), text: binding(path), axis: .vertical)
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(LocalizedStringKey(title))
            if path == \.logging.drawer && !draft.logging.drawer.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                Text("Use letters, numbers or underscores for the history drawer.")
                    .font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<WorkspaceConfiguration, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: path] }, set: { value in var next = draft; next[keyPath: path] = value; submit(next) })
    }
    private func rulePicker(_ title: String, value: WorkspaceConfiguration.LogRule,
                            change: @escaping (WorkspaceConfiguration.LogRule) -> Void) -> some View {
        Picker(LocalizedStringKey(title), selection: Binding(get: { value }, set: change)) {
            Text("Don't log").tag(WorkspaceConfiguration.LogRule.none)
            Text("Timestamp").tag(WorkspaceConfiguration.LogRule.time)
            Text("Ask for a note").tag(WorkspaceConfiguration.LogRule.note)
        }
    }
    private func submit(_ value: WorkspaceConfiguration) {
        draft = value
        error = nil
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard ready, changed else { return }
        autosaveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard !Task.isCancelled else { return }
            autosaveTask = nil
            await saveDraft(reportErrors: false)
        }
    }

    @MainActor
    private func persist(_ value: WorkspaceConfiguration) async throws {
        let previousDraft = draft
        submit(value)
        guard await saveDraft(reportErrors: false) else {
            // The modal owns its failed edit so it can be retried or canceled.
            if draft == value { draft = previousDraft }
            throw ConfigurationFailure(message: error ?? String(localized: "Your changes are still available. Try saving again."))
        }
    }

    @MainActor
    private func persistSnapshot(_ value: WorkspaceConfiguration) async throws {
        guard ready else { throw ConfigurationFailure(message: String(localized: "Wait for the current save to finish.")) }
        guard sessionID == store.workspaceFileSessionID else {
            throw ConfigurationFailure(message: String(localized: "The workspace changed. Reload settings before applying changes."))
        }
        if let message = ConfigurationSettingsFieldValidation.message(for: value) {
            throw ConfigurationFailure(message: message)
        }
        do { try value.validate() }
        catch { throw ConfigurationFailure(message: String(localized: "Check the highlighted fields and task defaults before saving.")) }
        let previous = store.configurationDocument
        let document = importedDocument
        let replacement = replacementID
        let replacing = replacement != nil || document != nil
        guard await store.saveConfiguration(value, expectedRevision: revision, document: document) else {
            throw ConfigurationFailure(message: store.configurationError.map { String(localized: String.LocalizationValue($0)) }
                ?? String(localized: "Your changes are still available. Try saving again."))
        }
        guard sessionID == store.workspaceFileSessionID else {
            throw ConfigurationFailure(message: String(localized: "The workspace changed. Reload settings before applying changes."))
        }
        guard store.configuration == value else {
            throw ConfigurationFailure(message: String(localized: "The configuration changed. Reload before applying this edit."))
        }
        undoDocument = replacing ? previous : nil
        // The visible draft may have advanced while this snapshot was written.
        baseline = value
        revision = store.configurationRevision
        if replacementID == replacement {
            importedDocument = nil
            replacementID = nil
        }
        error = nil
    }

    @MainActor @discardableResult
    private func saveDraft(reportErrors: Bool = true) async -> Bool {
        autosaveTask?.cancel()
        autosaveTask = nil
        if let saveTask { return await saveTask.value }
        let task = Task { @MainActor in
            saving = true
            defer { saving = false; saveTask = nil }
            do {
                while changed { try await persistSnapshot(draft) }
                return true
            } catch {
                self.error = error.localizedDescription
                if reportErrors { showsSaveError = true }
                return false
            }
        }
        saveTask = task
        return await task.value
    }

    private func reload() {
        autosaveTask?.cancel()
        autosaveTask = nil
        draft = store.configuration
        baseline = draft
        revision = store.configurationRevision
        sessionID = store.workspaceFileSessionID
        importedDocument = nil
        replacementID = nil
        undoDocument = nil
        error = nil
    }

    private func requestExit(_ destination: ExitDestination) {
        guard !leaving else { return }
        guard changed || saving else { leave(destination); return }
        leaving = true
        Task {
            defer { leaving = false }
            while changed || saving {
                guard await saveDraft(reportErrors: false) else {
                    pendingExit = destination
                    return
                }
            }
            leave(destination)
        }
    }

    private func leave(_ destination: ExitDestination) {
        switch destination {
        case .back: dismiss()
        case .workspace: openWorkspace()
        case .reload: reload()
        }
    }

    private func stageImport(_ source: String) throws {
        let document = try ConfigurationDocument(source)
        if let message = ConfigurationSettingsFieldValidation.message(for: document.configuration) {
            throw ConfigurationFailure(message: message)
        }
        importedDocument = document
        draft = document.configuration
        replacementID = UUID()
        showsJSON = true
        error = nil
        scheduleAutosave()
    }

    static func lines(_ value: String) -> [String] {
        value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
