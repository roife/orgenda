import SwiftUI

struct AppearanceSettingsView: View {
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
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
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
