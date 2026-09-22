import SwiftUI
import UIKit

struct OrgItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let store: WorkspaceStore
    private let isNew: Bool
    @State private var originalDraft: OrgItem
    private let captureDate: Date
    private let createdAt = Date.now
    @State private var draft: OrgItem
    @State private var tagsText: String
    @State private var showsSource = false
    @State private var showsDiscardConfirmation = false
    @State private var showsSaveFailure = false
    @State private var hasConfiguredTime: Bool
    @State private var captureTemplate: OrgCaptureTemplate = .inboxTask
    @State private var firstAction = ""
    @State private var sourceLink = ""
    @State private var stateNote = ""
    @State private var showsArchiveConfirmation = false
    @State private var showsMoveFailure = false
    @State private var isMoving = false
    @State private var isArchiving = false
    @State private var latestItem: OrgItem?
    @State private var showsDraftCopied = false
    @FocusState private var focusedField: OrgItemEditorField?
    @ScaledMetric(relativeTo: .body) private var notesMinimumHeight = 120.0

    init(store: WorkspaceStore, draft: OrgItem) {
        self.store = store
        let newItem = store.item(withID: draft.id) == nil
        isNew = newItem
        captureDate = draft.agendaDate ?? .now
        let initial = newItem && store.usesEmacsConfiguration
            ? OrgCaptureTemplate.inboxTask.applyingDefaults(to: draft, date: draft.agendaDate ?? .now, preservingPlanning: true)
            : draft
        _originalDraft = State(initialValue: initial)
        _draft = State(initialValue: initial)
        _tagsText = State(initialValue: initial.tags.joined(separator: ", "))
        _hasConfiguredTime = State(initialValue: initial.hasTime)
    }

    var body: some View {
        NavigationStack {
            presentedEditor
        }
        .disabled(isMoving)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isMoving {
                ProgressView(isArchiving ? "Archiving item…" : "Moving item…")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("item.editor.moveProgress")
            }
        }
        .tint(OrgendaTheme.accent)
        .interactiveDismissDisabled(hasChanges || isMoving)
    }

    private var styledEditor: some View {
        editorForm
        .accessibilityIdentifier("item.editor.form")
        .scrollDismissesKeyboard(.interactively)
        .animation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion), value: draft.scheduled != nil)
        .animation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion), value: draft.deadline != nil)
        .animation(OrgendaMotion.geometryAnimation(.selection, reduceMotion: reduceMotion), value: draft.hasTime)
        .navigationTitle(isNew ? "New Item" : "Edit Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", role: .cancel) {
                    if hasChanges {
                        showsDiscardConfirmation = true
                    } else {
                        dismiss()
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(isMoving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save", systemImage: "checkmark", role: .confirm) {
                    commit()
                }
                .labelStyle(.iconOnly)
                .disabled(!canSave || isMoving)
                .accessibilityIdentifier("item.editor.save")
            }
        }
    }

    private var observedEditor: some View {
        styledEditor
        .task { if isNew { focusedField = .title } }
        .onChange(of: captureTemplate) { previous, template in
            var item = draft
            item.tags = parsedTags
            let previousDefaults = previous.applyingDefaults(to: originalDraft, date: captureDate)
            draft = template.applyingDefaults(to: item, date: captureDate, preservingPlanning: true)
            if item.state != previousDefaults.state { draft.state = item.state }
            tagsText = draft.tags.joined(separator: ", ")
            hasConfiguredTime = draft.hasTime
        }
        .onChange(of: draft.kind) { _, kind in
            if kind == .event && draft.eventDate == nil {
                draft.eventDate = draft.scheduled ?? draft.deadline ?? captureDate
                draft.scheduled = nil
            }
        }
    }

    private var presentedEditor: some View {
        observedEditor
        .alert("Discard changes?", isPresented: $showsDiscardConfirmation) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Your changes haven't been saved.")
        }
        .alert("Couldn't Save Changes", isPresented: $showsSaveFailure) {
            Button("Copy draft") { copyDraft() }
            if !isNew, let current = store.item(withID: originalDraft.id) {
                Button("View latest version") { latestItem = current }
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The source file may have changed or be unavailable. Your draft is still here.")
        }
        .alert("Draft copied", isPresented: $showsDraftCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your draft was copied as Org text. You can paste it into another document.")
        }
        .sheet(item: $latestItem) { item in
            NavigationStack {
                OrgSourceView(item: item, originalSource: store.exactSource(for: item))
                    .navigationTitle("Latest version")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Keep Editing") { latestItem = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Copy draft and reload") { reloadLatestKeepingCopy() }
                        }
                    }
            }
        }
        .confirmationDialog("Archive this item?", isPresented: $showsArchiveConfirmation, titleVisibility: .visible) {
            Button("Archive item", role: .destructive) {
                Task { await moveItem(to: nil) }
            }
        } message: {
            Text("The complete subtree moves to the archive configured for this file.")
        }
        .alert("Couldn't Move Item", isPresented: $showsMoveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.operationError ?? String(localized: "The source file may have changed. Your item is still available."))
        }
        .navigationDestination(isPresented: $showsSource) {
            OrgSourceView(
                item: preparedDraft,
                originalSource: usesCaptureTemplates
                    ? captureTemplate.source(for: preparedDraft, createdAt: createdAt, firstAction: firstAction)
                    : hasChanges ? nil : store.exactSource(for: originalDraft)
            )
        }
    }

    private var editorForm: some View {
        Form {
            titleSection
            captureSection
            firstActionSection
            OrgItemScheduleSection(
                draft: $draft, hasConfiguredTime: $hasConfiguredTime, captureDate: captureDate,
                usesEventTimestamp: usesEventTimestamp,
                requiresSchedule: usesCaptureTemplates && captureTemplate.includesAppointmentWarning,
                onDismissKeyboard: { focusedField = nil }
            )
            OrgItemDetailsSection(
                draft: $draft, tagsText: $tagsText, contextTag: contextTag,
                focusedField: $focusedField, usesCaptureTemplates: usesCaptureTemplates,
                usesEmacsConfiguration: store.usesEmacsConfiguration
            )
            stateNoteSection
            repeatSection
            appointmentSection
            notesSection
            sourceLinkSection
            habitHistorySection
            sourceSection
            moveSection
        }
    }

    @ViewBuilder
    private var captureSection: some View {
        if usesCaptureTemplates {
            Section {
                Picker("Capture", selection: $captureTemplate) {
                    ForEach(OrgCaptureTemplate.allCases) { template in
                        Text(template.title).tag(template)
                    }
                }
                .accessibilityIdentifier("item.editor.template")
            } footer: {
                Text(captureDestination)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var titleSection: some View {
        Section {
            TextField("Add a title", text: $draft.title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isNew && (draft.kind == .note || draft.kind == .event) ? Color.primary : draft.workflowTitleColor)
                .lineLimit(1...4)
                .focused($focusedField, equals: .title)
                .accessibilityLabel("Title")
                .accessibilityIdentifier("item.editor.title")
        } header: {
            Text("Title")
        }
    }

    @ViewBuilder
    private var firstActionSection: some View {
        if usesCaptureTemplates && captureTemplate.isProject {
            Section {
                TextField("What is the first concrete step?", text: $firstAction, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .firstAction)
                    .accessibilityLabel("First next action")
                    .accessibilityHint("Required to save a project.")
                    .accessibilityIdentifier("item.editor.firstAction")
            } header: {
                Text("First next action (required)")
            } footer: {
                Text("Required to save a project.")
            }
        }
    }

    @ViewBuilder
    private var stateNoteSection: some View {
        if requiresStateNote {
            Section {
                TextField("Reason for this status change", text: $stateNote, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focusedField, equals: .stateNote)
                    .accessibilityIdentifier("item.editor.stateNote")
            } header: {
                Text("Status note")
            } footer: {
                Text("Your Org workflow requires a note for this status change.")
                    .font(.subheadline)
            }
        }
    }

    private var repeatSection: some View {
        Section {
            OrgRecurrenceEditor(
                recurrence: $draft.recurrence,
                allowsNever: !usesCaptureTemplates || captureTemplate != .repeatingReminder,
                identifier: "item.editor.recurrence"
            )
            .disabled(draft.agendaDate == nil)
        } footer: {
            if draft.agendaDate == nil {
                Text("Add a date to set a repeat schedule.")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var appointmentSection: some View {
        if draft.properties["APPT_WARNTIME"] != nil {
            Section {
                Stepper("Warn before · \(appointmentWarningMinutes.wrappedValue) min", value: appointmentWarningMinutes, in: 0...1440, step: 5)
            } footer: {
                Text("Saved as APPT_WARNTIME for your Org appointment reminders.")
                    .font(.subheadline)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.body)
                    .frame(minHeight: notesMinimumHeight)
                    .focused($focusedField, equals: .notes)
                    .accessibilityLabel("Notes")
                if draft.body.isEmpty {
                    Text("Add context, a checklist, or a link…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private var sourceLinkSection: some View {
        if usesCaptureTemplates && !captureTemplate.isProject {
            Section("Source link (optional)") {
                TextField("URL or Org link", text: $sourceLink, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .sourceLink)
            }
        }
    }

    @ViewBuilder
    private var habitHistorySection: some View {
        if draft.kind == .habit {
            Section("28-day history") {
                HabitHistoryView(completedDates: Set(draft.habitHistory.map(\.orgendaDayKey)))
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            Button("Preview Org", systemImage: "chevron.left.forwardslash.chevron.right") {
                focusedField = nil
                showsSource = true
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("File")
                Text(draft.source.file)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if !isNew {
                LabeledContent("Line", value: "\(draft.source.startLine)")
            }
        }
    }

    @ViewBuilder
    private var moveSection: some View {
        if !isNew && store.usesEmacsConfiguration {
            Section {
                NavigationLink {
                    refileDestinations
                } label: {
                    Label("Move to…", systemImage: "folder")
                }
                Button("Archive item", systemImage: "archivebox", role: .destructive) {
                    showsArchiveConfirmation = true
                }
            } footer: {
                if hasChanges { Text("Save your changes before moving or archiving this item.") }
            }
            .disabled(hasChanges || isMoving)
        }
    }

    private var usesCaptureTemplates: Bool { isNew && store.usesEmacsConfiguration }
    private var usesEventTimestamp: Bool {
        draft.eventDate != nil || (usesCaptureTemplates && captureTemplate == .calendarEvent)
    }

    private var captureDestination: String {
        captureTemplate.destinationPath + (captureTemplate.parentHeading.map { " → \($0)" } ?? "")
    }

    private var requiresStateNote: Bool {
        !isNew && store.usesEmacsConfiguration && OrgWorkflowOperations.requiresNote(from: originalDraft.state, to: draft.state)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty
            && OrgRepeater.isValid(draft.recurrence)
            && (!requiresStateNote || !stateNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!usesCaptureTemplates || !captureTemplate.isProject || !firstAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var contextTag: Binding<String> {
        Binding(
            get: { parsedTags.first { $0 == "@home" || $0 == "@work" } ?? "" },
            set: { context in
                var tags = parsedTags.filter { $0 != "@home" && $0 != "@work" }
                if !context.isEmpty { tags.append(context) }
                tagsText = tags.joined(separator: ", ")
            }
        )
    }

    private var appointmentWarningMinutes: Binding<Int> {
        Binding(
            get: { Int(draft.properties["APPT_WARNTIME"] ?? "15") ?? 15 },
            set: { draft.properties["APPT_WARNTIME"] = String($0) }
        )
    }

    private var refileDestinations: some View {
        let targets = store.refileTargets(for: originalDraft)
        return List {
            ForEach(targets) { target in
                let targetItem = store.items.first {
                    $0.source.file == target.path && $0.source.startByte == target.headingStartByte
                }
                Button {
                    Task { await moveItem(to: target) }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let item = targetItem, item.hasWorkflowState { OrgWorkflowIcon(item.state) }
                            Text(target.outline.isEmpty ? target.title : target.outline)
                                .foregroundStyle(targetItem?.workflowTitleColor ?? .primary)
                        }
                        Text(target.path).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .disabled(isMoving)
            }
        }
        .overlay {
            if targets.isEmpty {
                ContentUnavailableView("No destinations yet", systemImage: "folder", description:
                    Text("Create a heading in Actions, Projects, Routines, or Someday to use it as a destination."))
            }
        }
        .navigationTitle("Move to")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moveItem(to target: OrgRefileTarget?) async {
        guard !hasChanges && !isMoving else { return }
        isArchiving = target == nil
        isMoving = true
        let success: Bool
        if let target { success = await store.moveItem(originalDraft, to: target) }
        else { success = await store.archiveItem(originalDraft) }
        isMoving = false
        if success { dismiss() } else { showsMoveFailure = true }
    }

    private var trimmedTitle: String {
        draft.title.split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preparedDraft: OrgItem {
        var item = draft
        item.title = trimmedTitle
        item.tags = parsedTags
        if usesCaptureTemplates, !sourceLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.body += (item.body.isEmpty ? "" : "\n") + sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return item
    }

    private var draftSource: String {
        usesCaptureTemplates
            ? captureTemplate.source(for: preparedDraft, createdAt: createdAt, firstAction: firstAction)
            : OrgSourceView.source(for: preparedDraft, stateNote: stateNote)
    }

    private func copyDraft() {
        UIPasteboard.general.string = draftSource
        showsDraftCopied = true
    }

    private func reloadLatestKeepingCopy() {
        guard let current = store.item(withID: originalDraft.id) else {
            latestItem = nil
            showsSaveFailure = true
            return
        }
        UIPasteboard.general.string = draftSource
        originalDraft = current
        draft = current
        tagsText = current.tags.joined(separator: ", ")
        hasConfiguredTime = current.hasTime
        stateNote = ""
        latestItem = nil
        showsDraftCopied = true
    }

    private var parsedTags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasChanges: Bool {
        draft != originalDraft || tagsText != originalDraft.tags.joined(separator: ", ")
            || !firstAction.isEmpty || !sourceLink.isEmpty || !stateNote.isEmpty
    }

    private func commit() {
        focusedField = nil
        if store.save(preparedDraft, original: isNew ? nil : originalDraft,
                      captureTemplate: usesCaptureTemplates ? captureTemplate : nil,
                      captureFirstAction: usesCaptureTemplates && captureTemplate.isProject ? firstAction : nil,
                      stateNote: requiresStateNote ? stateNote : nil) {
            dismiss()
        } else {
            showsSaveFailure = true
        }
    }
}
