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
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsRow(
                                icon: "folder",
                                color: OrgendaTheme.accentText,
                                title: SettingsDestination.workspace.title,
                                subtitle: store.storageConnection?.provider.title ?? store.workspaceName
                            )
                            Label(store.syncState.title, systemImage: store.syncState.storageSymbol)
                                .font(.footnote)
                                .foregroundStyle(store.syncState.needsAttention ? Color.red : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 46)
                        }
                        .padding(.bottom, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier("settings.workspace")
                } header: {
                    Text(store.isWorkspaceReady ? store.workspaceName : String(localized: "Workspace"))
                }

                Section {
                    settingsLink(.workflow, icon: "checklist")
                    settingsLink(.capture, icon: "square.and.pencil")
                    settingsLink(.files, icon: "doc.text")
                } header: {
                    Text("Org tasks")
                }
                Section {
                    Menu {
                        ForEach(["System", "Light", "Dark"], id: \.self) { choice in
                            Button {
                                appearance = choice
                            } label: {
                                if appearance == choice {
                                    Label(LocalizedStringKey(choice), systemImage: "checkmark")
                                } else {
                                    Text(LocalizedStringKey(choice))
                                }
                            }
                            .accessibilityIdentifier("settings.appearance.\(choice.lowercased())")
                        }
                    } label: {
                        HStack {
                            Label("Appearance", systemImage: "circle.lefthalf.filled")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text(LocalizedStringKey(appearance)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")
                    settingsLink(.reminders, icon: "bell")
                } header: {
                    Text("On this device")
                }
                Section("Configuration tools") {
                    settingsLink(.emacs, icon: "doc.on.clipboard")
                    settingsLink(.configuration, icon: "curlybraces")
                }
                Section {
                    Text("orgenda · Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                    case .emacs: ConfigurationPromptView(configuration: store.configuration)
                    case .workflow, .capture, .files, .reminders, .configuration:
                        ConfigurationSettingsView(store: store, destination: destination)
                    }
                }
                .toolbar { doneToolbar }
            }
            .toolbar { doneToolbar }
        }
        .tint(OrgendaTheme.accentText)
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
        .task { await store.refreshReminders() }
        .preferredColorScheme(
            appearance == "Light" ? .light
                : appearance == "Dark" ? .dark : nil
        )
    }

    private var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done", systemImage: "checkmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("settings.done")
        }
    }

    private func settingsLink(_ destination: SettingsDestination, icon: String) -> some View {
        NavigationLink(value: destination) {
            // The destination itself explains the options. Home stays a short
            // list of tasks rather than another page of descriptions.
            Label(destination.title, systemImage: icon)
                .foregroundStyle(.primary)
        }
        .accessibilityIdentifier("settings.\(destination.rawValue)")
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        return "\(version) (\(build))"
    }

}
