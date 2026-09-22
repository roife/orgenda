import SwiftUI

/// Shared by Preview timestamp editing and the agenda item editor.
struct OrgRecurrenceEditor: View {
    @Binding var recurrence: String?
    var allowsNever = true
    var identifier = "org.recurrence"
    @State private var draft: OrgRepeater

    init(recurrence: Binding<String?>, allowsNever: Bool = true, identifier: String = "org.recurrence") {
        _recurrence = recurrence
        self.allowsNever = allowsNever
        self.identifier = identifier
        _draft = State(initialValue: recurrence.wrappedValue.flatMap(OrgRepeater.init) ?? OrgRepeater("+1d")!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allowsNever {
                Toggle("Repeat", isOn: Binding(
                    get: { recurrence != nil },
                    set: { recurrence = $0 ? draft.token : nil }
                ))
                .accessibilityIdentifier("\(identifier).enabled")
            } else {
                Label("Repeat", systemImage: "repeat")
                    .font(.subheadline.weight(.semibold))
            }

            if recurrence != nil {
                Stepper("Interval: \(draft.interval)", value: $draft.interval, in: 1...Int.max)
                    .accessibilityIdentifier("\(identifier).interval")
                unitPicker(String(localized: "Unit"), selection: $draft.unit, identifier: "\(identifier).unit")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Repeat from").fixedSize()
                        Spacer(minLength: 0)
                        repeatModePicker.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Repeat from")
                        repeatModePicker
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Habit maximum interval", isOn: Binding(
                    get: { draft.maximumInterval != nil },
                    set: { enabled in
                        draft.maximumInterval = enabled ? draft.interval : nil
                        draft.maximumUnit = enabled ? draft.unit : nil
                    }
                ))
                .accessibilityIdentifier("\(identifier).maximum.enabled")
                if draft.maximumInterval != nil {
                    Stepper("Maximum: \(draft.maximumInterval ?? draft.interval)", value: Binding(
                        get: { draft.maximumInterval ?? draft.interval },
                        set: { draft.maximumInterval = $0 }
                    ), in: 1...Int.max)
                    .accessibilityIdentifier("\(identifier).maximum.interval")
                    unitPicker(String(localized: "Maximum unit"), selection: Binding(
                        get: { draft.maximumUnit ?? draft.unit },
                        set: { draft.maximumUnit = $0 }
                    ), identifier: "\(identifier).maximum.unit")
                }

                if OrgRepeater.isValid(recurrence) {
                    Label(draft.summary, systemImage: "repeat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(recurrence ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Org repeat rule")
                        .accessibilityIdentifier("\(identifier).rule")
                } else {
                    Text("This repeat rule is unsupported. Choose an interval above to replace it.")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: draft) { _, value in
            guard recurrence != nil else { return }
            var normalized = value
            if let maximum = value.maximumInterval, value.maximumUnit == value.unit {
                normalized.maximumInterval = max(maximum, value.interval)
            }
            draft = normalized
            recurrence = normalized.token
        }
        .onChange(of: recurrence) { _, value in
            if let parsed = value.flatMap(OrgRepeater.init) { draft = parsed }
        }
    }

    private var repeatModePicker: some View {
        Picker("Repeat from", selection: $draft.mode) {
            Text("Scheduled date").tag(OrgRepeater.Mode.cumulative)
            Text("Next future date").tag(OrgRepeater.Mode.catchUp)
            Text("Completion date").tag(OrgRepeater.Mode.restart)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("\(identifier).mode")
    }

    private func unitPicker(_ title: String, selection: Binding<OrgRepeater.Unit>, identifier: String) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                Text("Hours").tag(OrgRepeater.Unit.hour)
                Text("Days").tag(OrgRepeater.Unit.day)
                Text("Weeks").tag(OrgRepeater.Unit.week)
                Text("Months").tag(OrgRepeater.Unit.month)
                Text("Years").tag(OrgRepeater.Unit.year)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier(identifier)
        }
    }

    private var modeExplanation: String {
        switch draft.mode {
        case .cumulative: String(localized: "Advance by one interval from the scheduled date when completed.")
        case .catchUp: String(localized: "Keep the original schedule and skip missed dates when completed.")
        case .restart: draft.unit == .hour
            ? String(localized: "Start the next interval from the time you complete the task.")
            : String(localized: "Start the next interval from the day you complete the task.")
        }
    }
}
