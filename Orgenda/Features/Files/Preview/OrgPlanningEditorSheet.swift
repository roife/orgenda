import SwiftUI

struct OrgPlanningEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: OrgPlanningEntryDraft
    @State private var saveFailed = false
    @State private var showsDiscardConfirmation = false
    private let originalDraft: OrgPlanningEntryDraft

    let onSave: (OrgPlanningEntryDraft) -> Bool

    init(
        draft: OrgPlanningEntryDraft,
        onSave: @escaping (OrgPlanningEntryDraft) -> Bool
    ) {
        _draft = State(initialValue: draft)
        originalDraft = draft
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if draft.keyword != nil {
                    Section("Planning type") {
                        if dynamicTypeSize.isAccessibilitySize {
                            planningTypePicker.pickerStyle(.menu)
                        } else {
                            planningTypePicker.pickerStyle(.segmented)
                        }
                    }
                }
                ForEach(draft.timestamps.indices, id: \.self) { index in
                    OrgPlanningTimestampEditor(
                        title: draft.isRange
                            ? (index == 0 ? String(localized: "Start") : String(localized: "End"))
                            : String(localized: "Date"),
                        identifierSuffix: index == 0 ? "start" : "end",
                        timestamp: $draft.timestamps[index]
                    )
                }
                Section {
                    if saveFailed {
                        Label("The source changed before this edit could be saved. Reopen the editor and try again.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Reminder offsets and timestamp ranges are kept when you edit the repeat rule.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("org.preview.planning.editor.scroll")
            .navigationTitle(draft.keyword == nil ? "Edit timestamp" : "Edit planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        if draft != originalDraft {
                            showsDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("org.preview.planning.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        saveFailed = !onSave(draft)
                        if !saveFailed { dismiss() }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!draft.timestamps.allSatisfy { OrgRepeater.isValid($0.recurrence) })
                    .accessibilityIdentifier("org.preview.planning.save")
                }
            }
            .alert("Discard changes?", isPresented: $showsDiscardConfirmation) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive) { dismiss() }
            } message: {
                Text("Your date and repeat changes haven't been saved.")
            }
        }
        .interactiveDismissDisabled(draft != originalDraft)
        .accessibilityIdentifier("org.preview.planning.editor")
    }

    private var planningTypePicker: some View {
        Picker("Planning type", selection: Binding<OrgPlanningKeyword>(
            get: { draft.keyword ?? .scheduled },
            set: { draft.keyword = $0 }
        )) {
            ForEach(OrgPlanningKeyword.allCases) { keyword in
                Text(keyword.title).tag(keyword)
            }
        }
        .accessibilityIdentifier("org.preview.planning.kindPicker")
    }
}

private struct OrgPlanningTimestampEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let identifierSuffix: String
    @Binding var timestamp: OrgPlanningTimestampDraft

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        Section(title) {
            dayPicker
            HStack {
                previousDayButton
                Spacer()
                nextDayButton
            }

            Toggle("Include time", isOn: $timestamp.includesTime)
                .accessibilityIdentifier("org.preview.planning.\(identifierSuffix).includesTime")
                .onChange(of: timestamp.includesTime) { wasIncluded, isIncluded in
                    guard !wasIncluded, isIncluded else { return }
                    let components = calendar.dateComponents([.hour, .minute], from: timestamp.date)
                    guard components.hour == 0, components.minute == 0,
                          let morning = calendar.date(
                            bySettingHour: 9,
                            minute: 0,
                            second: 0,
                            of: timestamp.date
                          ) else {
                        return
                    }
                    timestamp.date = morning
                }

            if timestamp.includesTime {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time")
                            timePicker.labelsHidden()
                        }
                    } else {
                        timePicker
                    }
                }
                .transition(.opacity)
            }

            OrgRecurrenceEditor(
                recurrence: $timestamp.recurrence,
                identifier: "org.preview.planning.\(identifierSuffix).recurrence"
            )
        }
    }

    private var dayPicker: some View {
        DatePicker(title, selection: $timestamp.date, displayedComponents: .date)
            .datePickerStyle(.compact)
            .accessibilityLabel(title)
            .accessibilityIdentifier("org.preview.planning.\(identifierSuffix).datePicker")
    }

    private var timePicker: some View {
        DatePicker("Time", selection: $timestamp.date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact)
            .accessibilityIdentifier("org.preview.planning.\(identifierSuffix).timePicker")
    }

    private var previousDayButton: some View {
        Button {
            timestamp.date = calendar.date(byAdding: .day, value: -1, to: timestamp.date)!
        } label: {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(OrgendaTheme.accentText)
        .accessibilityLabel("Previous \(title.lowercased()) day")
        .accessibilityIdentifier("org.preview.planning.\(identifierSuffix).previousDay")
    }

    private var nextDayButton: some View {
        Button {
            timestamp.date = calendar.date(byAdding: .day, value: 1, to: timestamp.date)!
        } label: {
            Image(systemName: "chevron.right")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(OrgendaTheme.accentText)
        .accessibilityLabel("Next \(title.lowercased()) day")
        .accessibilityIdentifier("org.preview.planning.\(identifierSuffix).nextDay")
    }
}
