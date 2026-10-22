import SwiftUI

enum ConfigurationSettingsPreview {
    static func directories(in documents: [WorkspaceDocument]) -> [String] {
        var paths = Set(documents.filter { $0.kind == .folder }.map(\.path))
        for document in documents {
            let components = document.path.split(separator: "/")
            if components.count > 1 {
                for count in 1..<components.count { paths.insert(components.prefix(count).joined(separator: "/")) }
            }
        }
        return paths.sorted()
    }

    static func agendaPaths(in documents: [WorkspaceDocument], agenda: WorkspaceConfiguration.Agenda) -> [String] {
        documents.filter { $0.kind == .org && agenda.includes($0.path) }.map(\.path).sorted()
    }

    static func archive(rule: String, sourcePath: String) -> OrgArchiveDestination? {
        guard ConfigurationValidation.archiveMessage(rule) == nil else { return nil }
        return try? OrgWorkflowOperations.archiveDestination(
            sourcePath: sourcePath, source: "* Example\n", headingStartByte: 0, defaultLocation: rule
        )
    }

    static func reminderOffsets(advanceMinutes: Int, repeatMinutes: Int) -> [Int] {
        guard ConfigurationValidation.advanceMinutes.contains(advanceMinutes),
              ConfigurationValidation.repeatMinutes.contains(repeatMinutes) else { return [] }
        return Set(Array(stride(from: advanceMinutes, through: 0, by: -repeatMinutes)) + [0]).sorted(by: >)
    }
}

struct ConfigurationFieldError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ConfigurationLogRulePicker: View {
    let title: LocalizedStringKey
    @Binding var selection: WorkspaceConfiguration.LogRule

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Don't log").tag(WorkspaceConfiguration.LogRule.none)
            Text("Timestamp").tag(WorkspaceConfiguration.LogRule.time)
            Text("Ask for a note").tag(WorkspaceConfiguration.LogRule.note)
        }
    }
}

/// Invalid text is reflected in the draft immediately, so Save cannot persist
/// the previous number while the field visibly contains an invalid edit.
struct ConfigurationIntegerField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let identifier: String
    var presets: [Int] = []
    @State private var text = ""

    var body: some View {
        Group {
            LabeledContent(LocalizedStringKey(title)) {
                TextField(LocalizedStringKey(title), text: Binding(get: { text }, set: { next in
                    text = next
                    value = Int(next) ?? Int.min
                }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                .accessibilityIdentifier(identifier)
            }
            .onAppear { text = value == Int.min ? "" : String(value) }
            .onChange(of: value) { _, next in
                if next != Int.min && Int(text) != next { text = String(next) }
            }
            if !presets.isEmpty {
                Picker("Common values", selection: $value) {
                    ForEach(presets, id: \.self) { preset in
                        Text(preset, format: .number).tag(preset)
                    }
                    if !presets.contains(value) {
                        Text(verbatim: text.isEmpty ? "—" : text).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(Text("\(String(localized: "Common values")): \(String(localized: String.LocalizationValue(title)))"))
                .accessibilityIdentifier(identifier + ".presets")
            }
            if let message = ConfigurationValidation.integerMessage(value, in: range) {
                ConfigurationFieldError(message: message)
            }
        }
    }
}
