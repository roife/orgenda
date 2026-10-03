import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance = "System"

    var body: some View {
        List {
            Section {
                Picker("Color scheme", selection: $appearance) {
                    Text("System").tag("System")
                        .accessibilityIdentifier("settings.appearance.system")
                    Text("Light").tag("Light")
                        .accessibilityIdentifier("settings.appearance.light")
                    Text("Dark").tag("Dark")
                        .accessibilityIdentifier("settings.appearance.dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("settings.appearance")
            } header: {
                Text("Color scheme")
            }
        }
        .listStyle(.insetGrouped)
        .tint(OrgendaTheme.accentText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Appearance")
    }

}
