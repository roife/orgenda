import SwiftUI

/// Field-level validation shared by the settings rows and their Save action.
enum ConfigurationSettingsFieldValidation {
    static func pathMessage(_ path: String, requiresOrgFile: Bool = false) -> String? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains(":"),
              !path.contains(where: { $0.isNewline || $0 == "\0" }),
              !path.split(separator: "/").contains("..") else {
            return String(localized: "Use a relative path inside this workspace, without .., ~, or an absolute path.")
        }
        if requiresOrgFile && !path.hasSuffix(".org") {
            return String(localized: "Choose an Org file or enter a path ending in .org.")
        }
        return nil
    }

    static func archiveMessage(_ rule: String) -> String? {
        let parts = rule.components(separatedBy: "::")
        guard parts.count == 2 else {
            return String(localized: "Separate the archive file and heading with ::, for example %s_archive::* Archived.")
        }
        let path = parts[0].replacingOccurrences(of: "%s", with: "example.org")
            .trimmingCharacters(in: .whitespaces)
        if let message = pathMessage(path) { return message }
        guard !path.contains("%"), path.hasSuffix(".org") || path.hasSuffix(".org_archive") else {
            return String(localized: "The archive file must end in .org or .org_archive. Only %s is supported as a filename placeholder.")
        }
        let heading = parts[1].trimmingCharacters(in: .whitespaces)
        if !heading.isEmpty && (heading.contains(where: \.isNewline)
            || heading.range(of: #"^\*+[ \t]+\S[^\r\n]*$"#, options: .regularExpression) == nil) {
            return String(localized: "Start the archive heading with stars and a space, or leave it empty to append at the end of the file.")
        }
        return nil
    }

    static func message(for configuration: WorkspaceConfiguration) -> String? {
        let paths = [(configuration.files.inbox, true), (configuration.files.attachments, false),
                     (configuration.files.journal, false)]
            + (configuration.agenda.sources + configuration.agenda.excluded + configuration.files.refile).map { ($0, false) }
        for (path, requiresOrg) in paths {
            if let message = pathMessage(path, requiresOrgFile: requiresOrg) { return message }
        }
        if let message = archiveMessage(configuration.files.archive) { return message }
        guard (1...99).contains(configuration.files.refileMaxLevel) else {
            return String(localized: "Enter a whole number from 1 to 99.")
        }
        guard (0...1440).contains(configuration.reminders.advanceMinutes) else {
            return String(localized: "Enter a whole number from 0 to 1440.")
        }
        guard (1...1440).contains(configuration.reminders.repeatMinutes) else {
            return String(localized: "Enter a whole number from 1 to 1440.")
        }
        guard (0...365).contains(configuration.reminders.deadlineWarningDays) else {
            return String(localized: "Enter a whole number from 0 to 365.")
        }
        guard configuration.logging.drawer.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return String(localized: "Use only letters, numbers, or underscores for the log drawer, or leave it empty.")
        }
        return nil
    }
}

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
        guard ConfigurationSettingsFieldValidation.archiveMessage(rule) == nil else { return nil }
        return try? OrgWorkflowOperations.archiveDestination(
            sourcePath: sourcePath, source: "* Example\n", headingStartByte: 0, defaultLocation: rule
        )
    }

    static func reminderOffsets(advanceMinutes: Int, repeatMinutes: Int) -> [Int] {
        guard (0...1440).contains(advanceMinutes), (1...1440).contains(repeatMinutes) else { return [] }
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

/// Invalid text is reflected in the draft immediately, so Save cannot persist
/// the previous number while the field visibly contains an invalid edit.
struct ConfigurationIntegerField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let errorMessage: String
    let identifier: String
    var presets: [Int] = []
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title)).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                TextField(LocalizedStringKey(title), text: Binding(get: { text }, set: { next in
                    text = next
                    value = Int(next) ?? Int.min
                }))
                .keyboardType(.numberPad)
                .foregroundStyle(.primary)
                .accessibilityLabel(LocalizedStringKey(title))
                .accessibilityIdentifier(identifier)
                if !presets.isEmpty {
                    Menu {
                        ForEach(presets, id: \.self) { preset in
                            Button { value = preset } label: { Text(preset, format: .number) }
                        }
                    } label: { Label("Common values", systemImage: "slider.horizontal.3") }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(Text("\(String(localized: "Common values")): \(String(localized: String.LocalizationValue(title)))"))
                    .accessibilityIdentifier(identifier + ".presets")
                }
            }
            if !range.contains(value) { ConfigurationFieldError(message: errorMessage) }
        }
        .padding(.vertical, 3)
        .onAppear { text = value == Int.min ? "" : String(value) }
        .onChange(of: value) { _, next in
            if next != Int.min && Int(text) != next { text = String(next) }
        }
    }
}
