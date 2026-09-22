import SwiftUI

struct OrgItemScheduleSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var draft: OrgItem
    @Binding var hasConfiguredTime: Bool
    let captureDate: Date
    let usesEventTimestamp: Bool
    let requiresSchedule: Bool
    let onDismissKeyboard: () -> Void

    var body: some View {
        Section {
            if usesEventTimestamp {
                datePicker("Event date", selection: eventDate, displayedComponents: .date)
            } else {
                Toggle("Scheduled", isOn: hasSchedule)
                    .disabled(requiresSchedule)
            }
            if draft.scheduled != nil && !usesEventTimestamp {
                datePicker("Scheduled date", selection: scheduledDate, displayedComponents: .date)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    quickDateButton("Today", date: .now)
                    quickDateButton("Tomorrow", date: Date.now.adding(days: 1))
                }
                .buttonStyle(.bordered)
            }
            Toggle("Deadline", isOn: hasDeadline)
            if draft.deadline != nil {
                datePicker("Deadline date", selection: deadlineDate, displayedComponents: .date)
            }
            if draft.agendaDate != nil {
                Toggle("Set a time", isOn: hasTime)
                if draft.hasTime {
                    if draft.eventDate != nil {
                        datePicker("Event time", selection: eventDate, displayedComponents: .hourAndMinute)
                    }
                    if draft.scheduled != nil {
                        datePicker("Scheduled time", selection: scheduledDate, displayedComponents: .hourAndMinute)
                        Stepper("Duration · \(draft.durationMinutes) min", value: $draft.durationMinutes, in: 5...480, step: 5)
                    }
                    if draft.deadline != nil {
                        datePicker("Deadline time", selection: deadlineDate, displayedComponents: .hourAndMinute)
                    }
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(usesEventTimestamp
                 ? "Events use an active Org timestamp, so they also appear in your Emacs calendar."
                 : "Scheduled is when you plan to work. Deadline is when it's due.")
                .font(.subheadline)
        }
    }

    private var hasTime: Binding<Bool> {
        Binding(
            get: { draft.hasTime },
            set: { enabled in
                if enabled, !hasConfiguredTime {
                    draft.scheduled = draft.scheduled.map(initialTime)
                    draft.deadline = draft.deadline.map(initialTime)
                    draft.eventDate = draft.eventDate.map(initialTime)
                    hasConfiguredTime = true
                }
                draft.hasTime = enabled
                if enabled, draft.durationMinutes < 5 { draft.durationMinutes = 30 }
            }
        )
    }

    private func initialTime(on date: Date) -> Date {
        guard date == date.startOfDay else { return date }
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: calendar.component(.minute, from: now),
            second: 0,
            of: date
        ) ?? date
    }

    @ViewBuilder
    private func datePicker(
        _ title: LocalizedStringKey,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                DatePicker(title, selection: selection, displayedComponents: displayedComponents)
                    .labelsHidden()
            }
        } else {
            DatePicker(title, selection: selection, displayedComponents: displayedComponents)
        }
    }

    private func quickDateButton(_ title: LocalizedStringKey, date: Date) -> some View {
        Button(title) {
            onDismissKeyboard()
            let calendar = Calendar.autoupdatingCurrent
            let scheduled = draft.scheduled ?? .now
            draft.scheduled = calendar.date(
                bySettingHour: calendar.component(.hour, from: scheduled),
                minute: calendar.component(.minute, from: scheduled),
                second: 0,
                of: date
            ) ?? date
        }
        .frame(minHeight: 44)
        .accessibilityHint("Changes the scheduled date and keeps the selected time")
    }

    private var hasSchedule: Binding<Bool> {
        Binding(
            get: { draft.scheduled != nil },
            set: { draft.scheduled = $0 ? (draft.scheduled ?? .now) : nil }
        )
    }

    private var scheduledDate: Binding<Date> {
        Binding(
            get: { draft.scheduled ?? .now },
            set: { draft.scheduled = $0 }
        )
    }

    private var hasDeadline: Binding<Bool> {
        Binding(
            get: { draft.deadline != nil },
            set: { draft.deadline = $0 ? (draft.deadline ?? draft.scheduled ?? .now) : nil }
        )
    }

    private var deadlineDate: Binding<Date> {
        Binding(
            get: { draft.deadline ?? .now },
            set: { draft.deadline = $0 }
        )
    }

    private var eventDate: Binding<Date> {
        Binding(get: { draft.eventDate ?? captureDate }, set: { draft.eventDate = $0 })
    }

}
