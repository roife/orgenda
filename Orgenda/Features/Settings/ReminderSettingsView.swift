import SwiftUI
import UIKit

/// Device permission controls embedded alongside the workspace timing controls.
struct ReminderSettingsSections: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: WorkspaceStore
    @AppStorage("orgRemindersEnabled") private var remindersEnabled = false

    var body: some View {
        Group {
            Section {
                Toggle(isOn: $remindersEnabled) {
                    SettingsRow(icon: "bell", color: OrgendaTheme.accentText,
                                title: String(localized: "Agenda reminders"),
                                subtitle: String(localized: "For timed entries in your agenda"))
                }
                .disabled(!store.usesEmacsConfiguration && !store.hasWorkspaceConfiguration)
                .accessibilityIdentifier("settings.reminders.enabled")
                .onChange(of: remindersEnabled) { _, enabled in
                    Task { await store.refreshReminders(requestPermission: enabled) }
                }
            }
            if !store.usesEmacsConfiguration && !store.hasWorkspaceConfiguration {
                Text("Connect a workspace to enable").foregroundStyle(.secondary)
            }

            if store.usesEmacsConfiguration || store.hasWorkspaceConfiguration {
                Section("Notification status") {
                    Label(store.reminderStatus, systemImage: store.reminderPermissionDenied ? "bell.slash" : "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(store.reminderPermissionDenied ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.reminders.status")
                    if store.reminderPermissionDenied {
                        Link(destination: URL(string: UIApplication.openNotificationSettingsURLString)!) {
                            Label("Open Notification Settings", systemImage: "arrow.up.forward.app")
                        }
                        .accessibilityIdentifier("settings.reminders.openSystemSettings")
                    }
                }
            }
        }
        .task { await store.refreshReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshReminders() } }
        }
    }
}
