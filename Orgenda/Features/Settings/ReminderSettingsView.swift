import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: WorkspaceStore
    @AppStorage("orgRemindersEnabled") private var remindersEnabled = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $remindersEnabled) {
                    Label("Agenda reminders", systemImage: "bell.badge")
                }
                .disabled(!store.usesEmacsConfiguration)
                .accessibilityIdentifier("settings.reminders.enabled")
                .onChange(of: remindersEnabled) { _, enabled in
                    Task { await store.refreshReminders(requestPermission: enabled) }
                }
            } footer: {
                Text(store.usesEmacsConfiguration
                     ? "Get notified before timed entries in your agenda."
                     : "Connect a workspace folder in Workspace & Sync to use reminders.")
            }

            if store.usesEmacsConfiguration {
                Section {
                    SettingsValueRow(title: String(localized: "Status"), value: store.reminderStatus)
                        .accessibilityIdentifier("settings.reminders.status")
                    if store.reminderPermissionDenied {
                        Link(destination: URL(string: UIApplication.openNotificationSettingsURLString)!) {
                            Label("Open Notification Settings", systemImage: "arrow.up.forward.app")
                        }
                        .accessibilityIdentifier("settings.reminders.openSystemSettings")
                    }
                } footer: {
                    Text("Reminders start \(OrgWorkspaceConfiguration.appointmentWarningMinutes) minutes before an entry and repeat every \(OrgWorkspaceConfiguration.appointmentRepeatMinutes) minutes until it starts. An entry’s custom warning time takes precedence.")
                }
            }
        }
        .task { await store.refreshReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshReminders() } }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Reminders")
    }
}
