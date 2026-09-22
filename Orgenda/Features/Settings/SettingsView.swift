import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
            .orgendaSettingsListSurface()
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var reminderSummary: String {
        guard store.usesEmacsConfiguration else { return String(localized: "Connect a folder to enable") }
        if store.reminderPermissionDenied { return String(localized: "Notifications disabled in Settings") }
        return remindersEnabled ? String(localized: "On") : String(localized: "Off")
    }
}

private struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize = 18.0
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var isSelected: Bool? = nil

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        iconTile
                        Spacer(minLength: 0)
                        selectionIndicator
                    }
                    text
                }
            } else {
                HStack(spacing: 14) {
                    iconTile
                    text
                    selectionIndicator
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var iconTile: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: iconSize + 18, height: iconSize + 18)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var selectionIndicator: some View {
        if let isSelected {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(OrgendaTheme.accentText)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

private struct WorkspaceSettingsView: View {
    let store: WorkspaceStore
    @State private var isChoosingFolder = false
    @State private var isConfirmingReload = false

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: String(localized: "Workspace"), value: store.workspaceName)
                SettingsValueRow(title: String(localized: "Org files"), value: String(localized: "\(store.documents.filter { $0.kind == .org }.count)"))
                SettingsValueRow(title: String(localized: "Location"), value: store.workspaceLocation)
                if let lastSync = store.lastFileSync {
                    SettingsValueRow(title: String(localized: "Last checked"), value: lastSync.formatted(date: .omitted, time: .standard))
                }
                if store.pendingFileCount > 0 {
                    SettingsValueRow(title: String(localized: "Pending saves"), value: "\(store.pendingFileCount)")
                }
            } header: {
                Text("Current Workspace")
            } footer: {
                Text(store.storageDescription + String(localized: " Choose a folder in Files to use iCloud Drive or another file provider. Cloud transfer is managed by the provider."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Choose Folder…", systemImage: "folder.badge.plus") { isChoosingFolder = true }
                    .disabled(store.isSynchronizing || store.pendingFileCount > 0)
                    .accessibilityIdentifier("workspace.chooseFolder")
                if store.isFolderConnected {
                    Button(store.isSynchronizing ? "Checking…" : "Save & Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.synchronizeFiles() }
                    }
                    .disabled(store.isSynchronizing)
                    .accessibilityIdentifier("workspace.refresh")
                }
            }
            if let error = store.fileSyncError {
                Section("File changes need attention") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                    Text("Conflicting source files are left untouched. You can keep copies of pending edits in orgenda → Unsaved Edits, then reload the folder versions.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if store.pendingFileCount > 0 {
                        Button("Use Folder Versions…", systemImage: "arrow.down.document") {
                            isConfirmingReload = true
                        }
                        .disabled(store.isSynchronizing)
                        .accessibilityIdentifier("workspace.resolveConflict")
                    }
                }
            }
        }
        .orgendaSettingsListSurface()
        .navigationTitle("Workspace & Sync")
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await store.connectFolder(url) }
            case .failure(let error):
                store.fileSyncError = error.localizedDescription
            }
        }
        .confirmationDialog("Reload folder versions?", isPresented: $isConfirmingReload, titleVisibility: .visible) {
            Button("Keep Copies and Reload", role: .destructive) {
                Task { await store.adoptFolderVersions() }
            }
        } message: {
            Text("Pending edits will be saved in orgenda → Unsaved Edits before the folder versions replace them in orgenda. Files in the connected folder will not be changed.")
        }
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance = "System"

    var body: some View {
        List {
            Section {
                appearanceOption("System", subtitle: String(localized: "Match your device"), icon: "circle.lefthalf.filled")
                appearanceOption("Light", subtitle: String(localized: "Always use a light appearance"), icon: "sun.max.fill")
                appearanceOption("Dark", subtitle: String(localized: "Always use a dark appearance"), icon: "moon.fill")
            } header: {
                Text("Theme")
            } footer: {
                Text("System switches automatically with your device’s appearance.")
            }
        }
        .orgendaSettingsListSurface()
        .navigationTitle("Appearance")
    }

    private func appearanceOption(_ title: String, subtitle: String, icon: String) -> some View {
        Button {
            appearance = title
        } label: {
            SettingsRow(icon: icon, color: OrgendaTheme.accent, title: String(localized: String.LocalizationValue(title)), subtitle: subtitle, isSelected: appearance == title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appearance == title ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(title.lowercased())")
    }
}

private struct ReminderSettingsView: View {
    @Environment(\.openURL) private var openURL
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
                        Button("Open Notification Settings", systemImage: "arrow.up.forward.app") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
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
        .orgendaSettingsListSurface()
        .navigationTitle("Reminders")
    }
}

/// Keep long paths, localized values, and accessibility text readable without
/// squeezing either side of a settings row.
private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).fixedSize()
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                Text(value)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Group settings using the system content surface, while the navigation
    /// bar supplies its own Liquid Glass and adaptive scroll boundary.
    func orgendaSettingsListSurface() -> some View {
        listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
    }
}
