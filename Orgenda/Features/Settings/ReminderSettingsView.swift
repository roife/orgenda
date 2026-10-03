import SwiftUI

/// Workspace defaults share the configuration editor's validated save pipeline.
struct WorkspaceReminderTimingSections: View {
    @Binding var advance: Int
    @Binding var repeatInterval: Int
    @Binding var deadline: Int
    let edit: (ReminderTimingKind) -> Void

    var body: some View {
        Group {
            Section {
                timingRow(.advance, value: $advance)
                timingRow(.repeatInterval, value: $repeatInterval)
            } header: {
                Text("Workspace timing")
            }

            Section("Reminder preview") {
                let offsets = ConfigurationSettingsPreview.reminderOffsets(advanceMinutes: advance, repeatMinutes: repeatInterval)
                let preview = offsets.prefix(6).map { offset in
                    offset == 0 ? String(localized: "At start") : String(localized: "\(offset) minutes before")
                }
                Text(preview.joined(separator: " → ") + (offsets.count > 6 ? " → … → " + String(localized: "At start") : ""))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.reminders.preview")
            }

            Section {
                timingRow(.deadline, value: $deadline)
            }
        }
    }

    private func timingRow(_ kind: ReminderTimingKind, value: Binding<Int>) -> some View {
        ReminderTimingRow(kind: kind, value: value) {
            edit(kind)
        }
    }
}

enum ReminderTimingKind: String, Identifiable {
    case advance, repeatInterval, deadline

    var id: String { rawValue }

    var configurationPath: WritableKeyPath<WorkspaceConfiguration, Int> {
        switch self {
        case .advance: \.reminders.advanceMinutes
        case .repeatInterval: \.reminders.repeatMinutes
        case .deadline: \.reminders.deadlineWarningDays
        }
    }

    var title: String {
        switch self {
        case .advance: String(localized: "Advance notice")
        case .repeatInterval: String(localized: "Repeat interval")
        case .deadline: String(localized: "Deadline lookahead")
        }
    }

    var symbol: String {
        switch self {
        case .advance: "bell.badge"
        case .repeatInterval: "arrow.trianglehead.2.clockwise.rotate.90"
        case .deadline: "calendar.badge.clock"
        }
    }

    var presets: [Int] {
        switch self {
        case .advance: [0, 5, 15, 30]
        case .repeatInterval: [1, 5, 10, 15]
        case .deadline: [0, 3, 7, 14]
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .advance: 0...1440
        case .repeatInterval: 1...1440
        case .deadline: 0...365
        }
    }

    var unit: String { self == .deadline ? String(localized: "Days") : String(localized: "Minutes") }

    func label(for value: Int) -> String {
        if self == .advance && value == 0 { return String(localized: "At start") }
        if self == .deadline && value == 0 { return String(localized: "No lookahead") }
        return self == .deadline ? String(localized: "\(value) days") : String(localized: "\(value) min")
    }
}

private struct ReminderTimingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: ReminderTimingKind
    @Binding var value: Int
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading

            if dynamicTypeSize.isAccessibilitySize || !kind.presets.contains(value) {
                presetPicker.pickerStyle(.menu)
            } else {
                presetPicker.pickerStyle(.segmented)
            }
        }
    }

    private var presetPicker: some View {
        Picker("Common values", selection: $value) {
            ForEach(kind.presets, id: \.self) { preset in
                Text(kind.label(for: preset))
                    .tag(preset)
                    .accessibilityIdentifier("settings.reminders.\(kind.id).preset.\(preset)")
            }
            if !kind.presets.contains(value) {
                Text(kind.label(for: value)).tag(value)
            }
        }
        .accessibilityLabel(Text(verbatim: "\(kind.title), \(String(localized: "Common values"))"))
        .accessibilityIdentifier("settings.reminders.\(kind.id).presets")
    }

    @ViewBuilder private var heading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedHeading
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    customValue.fixedSize()
                }
                stackedHeading
            }
        }
    }

    private var stackedHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
            customValue
        }
    }

    private var title: some View {
        Label(kind.title, systemImage: kind.symbol)
            .font(.body.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var customValue: some View {
        Button(action: edit) {
            HStack(spacing: 6) {
                Text(kind.label(for: value))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(OrgendaTheme.accentText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityValue(kind.label(for: value))
        .accessibilityHint("Choose a custom value")
        .accessibilityIdentifier("settings.reminders.\(kind.id).custom")
    }
}

struct ReminderTimingEditor: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ReminderTimingKind
    @Binding var value: Int
    @State private var input: String

    init(kind: ReminderTimingKind, value: Binding<Int>) {
        self.kind = kind
        _value = value
        _input = State(initialValue: String(value.wrappedValue))
    }

    private var validValue: Int? {
        guard let number = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              kind.range.contains(number) else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(kind.unit) {
                        TextField(kind.unit, text: $input)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.monospacedDigit())
                            .accessibilityLabel(kind.unit)
                            .accessibilityIdentifier("settings.reminders.custom.input")
                    }
                } header: {
                    Text("Custom timing")
                } footer: {
                    if validValue == nil {
                        Text("Enter a whole number from \(kind.range.lowerBound) to \(kind.range.upperBound).")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let validValue else { return }
                        value = validValue
                        dismiss()
                    }
                    .disabled(validValue == nil)
                    .accessibilityIdentifier("settings.reminders.custom.done")
                }
            }
            .tint(OrgendaTheme.accentText)
        }
    }
}

/// Device permission controls embedded alongside the workspace timing controls.
struct ReminderSettingsSections: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: WorkspaceStore
    let openWorkspace: () -> Void
    @AppStorage("orgRemindersEnabled") private var remindersEnabled = false

    var body: some View {
        Group {
            Section {
                Toggle(isOn: $remindersEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Agenda reminders")
                                .foregroundStyle(.primary)
                            if store.reminderPermissionDenied {
                                Text("Notifications disabled in Settings")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .accessibilityIdentifier("settings.reminders.status")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "bell")
                            .foregroundStyle(OrgendaTheme.accentText)
                            .accessibilityHidden(true)
                    }
                    .labelStyle(.titleAndIcon)
                }
                .disabled(!store.usesEmacsConfiguration && !store.hasWorkspaceConfiguration)
                .accessibilityIdentifier("settings.reminders.enabled")
                .onChange(of: remindersEnabled) { _, enabled in
                    Task { await store.refreshReminders(requestPermission: enabled) }
                }
            } header: {
                Text("On this device")
            }
            if !store.usesEmacsConfiguration && !store.hasWorkspaceConfiguration {
                Section {
                    Button("Connect workspace", systemImage: "folder.badge.plus", action: openWorkspace)
                        .accessibilityIdentifier("settings.reminders.connectWorkspace")
                }
            }
        }
        .task { await store.refreshReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshReminders() } }
        }
    }
}
