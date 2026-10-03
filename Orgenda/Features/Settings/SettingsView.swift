import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "System"
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
                            icon: store.storageConnection?.provider.symbol ?? "folder",
                            color: .primary,
                            title: SettingsDestination.workspace.title,
                            subtitle: store.storageConnection?.providerSummary ?? store.workspaceName,
                            subtitleIcon: store.syncState.storageSymbol,
                            iconAsset: store.storageConnection?.provider.iconAsset
                        )
                    }
                    .accessibilityValue([store.storageConnection?.provider.title, store.syncState.title]
                        .compactMap { $0 }.joined(separator: ", "))
                    .accessibilityIdentifier("settings.workspace")
                }

                Section {
                    settingsLink(.workflow, icon: "checklist")
                    settingsLink(.capture, icon: "square.and.pencil")
                    settingsLink(.files, icon: "doc.text")
                } header: {
                    Text("Tasks & capture")
                }
                Section {
                    settingsLink(.reminders, icon: "bell")
                }
                Section {
                    Picker(selection: $appearance) {
                        ForEach(["System", "Light", "Dark"], id: \.self) { choice in
                            Text(LocalizedStringKey(choice))
                                .tag(choice)
                                .accessibilityIdentifier("settings.appearance.\(choice.lowercased())")
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                            .foregroundStyle(.primary)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text("On this device")
                }
                Section("Advanced configuration") {
                    settingsLink(.configuration, icon: "curlybraces")
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .workspace:
                    WorkspaceSettingsView(store: store).toolbar { doneToolbar }
                case .appearance:
                    AppearanceSettingsView().toolbar { doneToolbar }
                case .workflow, .capture, .files, .reminders, .configuration:
                    ConfigurationSettingsView(store: store, destination: destination,
                                              openWorkspace: { path.append(.workspace) })
                }
            }
            .toolbar { if path.isEmpty { doneToolbar } }
        }
        .tint(OrgendaTheme.accentText)
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
        .task { await store.refreshReminders() }
    }

    private var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Close", systemImage: "checkmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.done")
        }
    }

    private func settingsLink(_ destination: SettingsDestination, icon: String) -> some View {
        NavigationLink(value: destination) {
            Label(destination.title, systemImage: icon)
                .foregroundStyle(.primary)
        }
        .accessibilityIdentifier("settings.\(destination.rawValue)")
    }

}
