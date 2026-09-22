import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("orgRemindersEnabled") private var remindersEnabled = false
    let store: WorkspaceStore
    @State private var path: [SettingsDestination]

    init(store: WorkspaceStore, initialDestination: SettingsDestination? = nil) {
        self.store = store
        _path = State(initialValue: initialDestination.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: SettingsDestination.workspace) {
                        SettingsRow(
                            icon: "folder.fill",
                            color: OrgendaTheme.accent,
                            title: SettingsDestination.workspace.title,
                            subtitle: store.workspaceName
                        )
                    }
                    .accessibilityIdentifier("settings.workspace")
                } header: {
                    Text("Workspace")
                } footer: {
                    Label(workspaceStatus, systemImage: workspaceStatusIcon)
                        .foregroundStyle(store.fileSyncError == nil ? Color.secondary : OrgendaTheme.overdue)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    NavigationLink(value: SettingsDestination.appearance) {
                        SettingsRow(
                            icon: "circle.lefthalf.filled",
                            color: OrgendaTheme.accent,
                            title: SettingsDestination.appearance.title,
                            subtitle: appearance == "System" ? String(localized: "Follow system") : String(localized: String.LocalizationValue(appearance))
                        )
                    }
                    .accessibilityIdentifier("settings.appearance")

                    NavigationLink(value: SettingsDestination.reminders) {
                        SettingsRow(
                            icon: "bell.badge.fill",
                            color: OrgendaTheme.event,
                            title: SettingsDestination.reminders.title,
                            subtitle: reminderSummary
                        )
                    }
                    .accessibilityIdentifier("settings.reminders")
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("orgenda · Version \(appVersion)")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .accessibilityIdentifier("settings.version")
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                Group {
                    switch destination {
                    case .workspace: WorkspaceSettingsView(store: store)
                    case .appearance: AppearanceSettingsView()
                    case .reminders: ReminderSettingsView(store: store)
                    }
                }
                .toolbar { doneToolbar }
            }
            .toolbar { doneToolbar }
        }
        .task { await store.refreshReminders() }
        .preferredColorScheme(
            appearance == "Light" ? .light
                : appearance == "Dark" ? .dark : nil
        )
    }

    private var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("settings.done")
        }
    }

    private var workspaceStatus: String {
        if store.fileSyncError != nil { return String(localized: "Changes need attention") }
        if store.pendingFileCount > 0 { return String(localized: "Saving changes…") }
        return store.isFolderConnected ? String(localized: "Changes save to your folder") : String(localized: "Workspace not ready · Connect a folder")
    }

    private var workspaceStatusIcon: String {
        if store.fileSyncError != nil { return "exclamationmark.triangle" }
        if store.pendingFileCount > 0 { return "arrow.trianglehead.2.clockwise.rotate.90" }
        return store.isFolderConnected ? "checkmark.circle" : "info.circle"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        return "\(version) (\(build))"
    }

    private var reminderSummary: String {
        guard store.usesEmacsConfiguration else { return String(localized: "Connect a folder to enable") }
        if store.reminderPermissionDenied { return String(localized: "Notifications disabled in Settings") }
        return remindersEnabled ? String(localized: "On") : String(localized: "Off")
    }
}
