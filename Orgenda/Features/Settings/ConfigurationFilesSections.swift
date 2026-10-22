import SwiftUI

struct ConfigurationFilesSections: View {
    let store: WorkspaceStore
    @Binding var draft: WorkspaceConfiguration
    @State private var archiveSource: String?

    private var orgPaths: [String] { store.documents.filter { $0.kind == .org }.map(\.path).sorted() }
    private var directories: [String] { ConfigurationSettingsPreview.directories(in: store.documents) }
    private var agendaPaths: [String] { ConfigurationSettingsPreview.agendaPaths(in: store.documents, agenda: draft.agenda) }
    private var archiveExample: String {
        if let archiveSource, orgPaths.contains(archiveSource) { return archiveSource }
        return orgPaths.first ?? draft.files.inbox
    }

    var body: some View {
        Group {
            Section {
                ConfigurationPathSelectionRow(title: "Included paths", paths: $draft.agenda.sources,
                                              choices: orgPaths + directories, directories: Set(directories),
                                              emptyTitle: "All visible Org files", identifier: "configuration.agenda.sources")
                ConfigurationPathSelectionRow(title: "Excluded paths", paths: $draft.agenda.excluded,
                                              choices: orgPaths + directories, directories: Set(directories),
                                              emptyTitle: "None", identifier: "configuration.agenda.excluded")
                DisclosureGroup {
                    if agendaPaths.isEmpty {
                        Text("No currently loaded Org files match these rules.").foregroundStyle(.secondary)
                    }
                    ForEach(agendaPaths, id: \.self) { Text(verbatim: $0).font(.subheadline) }
                } label: { Text("Matching Org files: \(agendaPaths.count)") }
                .accessibilityIdentifier("configuration.agenda.preview")
            } header: {
                Text("Agenda sources")
            }

            Section {
                ConfigurationPathField(title: "Inbox file", path: $draft.files.inbox, choices: orgPaths,
                                       requiresOrgFile: true, identifier: "configuration.files.inbox")
                ConfigurationPathField(title: "Attachment directory", path: $draft.files.attachments, choices: directories,
                                       identifier: "configuration.files.attachments")
                ConfigurationPathField(title: "Journal directory", path: $draft.files.journal, choices: directories,
                                       identifier: "configuration.files.journal")
            } header: {
                Text("Default locations")
            }

            archiveSection

            Section {
                ConfigurationPathSelectionRow(title: "Target files", paths: $draft.files.refile,
                                              choices: orgPaths, directories: [], emptyTitle: "No refile destinations",
                                              identifier: "configuration.files.refile", requiresOrgFile: true)
                ConfigurationIntegerField(title: "Maximum heading level", value: $draft.files.refileMaxLevel,
                                          range: ConfigurationValidation.refileMaxLevel,
                                          identifier: "configuration.files.refileMaxLevel", presets: [1, 2, 3, 5, 10])
            } header: {
                Text("Refile")
            }
        }
    }

    private var archiveSection: some View {
        Section {
            Label {
                Text(LocalizedStringKey(draft.files.archive == WorkspaceConfiguration.standard.files.archive
                                        ? "Alongside each source file" : "Custom archive rule"))
            } icon: { Image(systemName: "archivebox") }
            if draft.files.archive != WorkspaceConfiguration.standard.files.archive {
                Button("Use an archive beside each source file") {
                    draft.files.archive = WorkspaceConfiguration.standard.files.archive
                }
                .accessibilityIdentifier("configuration.archive.followSource")
            }
            if !orgPaths.isEmpty {
                Picker("Example source file", selection: Binding(get: { archiveExample }, set: { archiveSource = $0 })) {
                    ForEach(orgPaths, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .accessibilityIdentifier("configuration.archive.source")
            } else {
                LabeledContent("Example source file", value: archiveExample)
            }
            if let destination = ConfigurationSettingsPreview.archive(rule: draft.files.archive, sourcePath: archiveExample) {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Archive file") {
                        Text(verbatim: destination.path).textSelection(.enabled)
                    }
                    if let heading = destination.outline {
                        Text("Under heading: \(heading)").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("At the end of the archive file").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("configuration.archive.preview")
            }
            DisclosureGroup("Advanced archive rule") {
                LabeledContent("Archive rule") {
                    TextField("Archive rule", text: $draft.files.archive, axis: .vertical)
                        .foregroundStyle(.primary).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("configuration.files.archive")
                }
            }
            .accessibilityIdentifier("configuration.archive.advanced")
            if let message = ConfigurationValidation.archiveMessage(draft.files.archive) {
                ConfigurationFieldError(message: message)
            }
        } header: {
            Text("Archive")
        }
    }
}

private struct ConfigurationPathField: View {
    let title: String
    @Binding var path: String
    let choices: [String]
    var requiresOrgFile = false
    let identifier: String

    var body: some View {
        Group {
            LabeledContent(LocalizedStringKey(title)) {
                TextField(LocalizedStringKey(title), text: $path, axis: .vertical)
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(identifier)
            }
            if !choices.isEmpty {
                Picker("Choose existing location", selection: $path) {
                    ForEach(choices, id: \.self) { choice in
                        Text(verbatim: choice).tag(choice)
                    }
                    if !choices.contains(path) {
                        Text(verbatim: path.isEmpty ? "—" : path).tag(path)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(Text("\(String(localized: "Choose existing location")): \(String(localized: String.LocalizationValue(title)))"))
                .accessibilityValue(Text(verbatim: path))
                .accessibilityIdentifier(identifier + ".choose")
            }
            if let message = ConfigurationValidation.pathMessage(path, requiresOrgFile: requiresOrgFile) {
                ConfigurationFieldError(message: message)
            }
        }
    }
}

private struct ConfigurationPathSelectionRow: View {
    let title: String
    @Binding var paths: [String]
    let choices: [String]
    let directories: Set<String>
    let emptyTitle: String
    let identifier: String
    var requiresOrgFile = false

    var body: some View {
        NavigationLink {
            ConfigurationPathSelectionView(title: title, paths: $paths, choices: choices, directories: directories,
                                           emptyTitle: emptyTitle, identifier: identifier, requiresOrgFile: requiresOrgFile)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(LocalizedStringKey(title)) {
                    if paths.isEmpty { Text(LocalizedStringKey(emptyTitle)) }
                    else { Text(paths.joined(separator: ", ")).lineLimit(2) }
                }
                if let message = paths.compactMap({ ConfigurationValidation.pathMessage($0, requiresOrgFile: requiresOrgFile) }).first {
                    ConfigurationFieldError(message: message)
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct ConfigurationPathSelectionView: View {
    let title: String
    @Binding var paths: [String]
    let choices: [String]
    let directories: Set<String>
    let emptyTitle: String
    let identifier: String
    let requiresOrgFile: Bool
    @State private var newPath = ""

    private var allChoices: [String] { Set(choices + paths).sorted() }
    private var pathError: String? { ConfigurationValidation.pathMessage(newPath, requiresOrgFile: requiresOrgFile) }

    private var selectedPaths: Binding<Set<String>> {
        Binding(get: { Set(paths) }, set: { selection in
            let previous = Set(paths)
            // Retain existing order; native range selection adds new paths in display order.
            paths = paths.filter(selection.contains)
                + allChoices.filter { selection.contains($0) && !previous.contains($0) }
        })
    }

    var body: some View {
        List(selection: selectedPaths) {
            Section {
                if paths.isEmpty {
                    Text(LocalizedStringKey(emptyTitle))
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                } else {
                    Button("Clear selection") { paths = [] }
                        .accessibilityIdentifier(identifier + ".clear")
                        .selectionDisabled()
                }
                ForEach(allChoices, id: \.self) { path in
                    Label {
                        Text(verbatim: path).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: directories.contains(path) ? "folder" : "doc.text")
                            .foregroundStyle(.secondary)
                    }
                    .tag(path)
                    .accessibilityIdentifier(identifier + ".path." + path)
                }
            }
            Section {
                TextField("New relative path", text: $newPath)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(identifier + ".newPath")
                    .selectionDisabled()
                Button("Add path to selection", systemImage: "plus") {
                    guard pathError == nil else { return }
                    if !paths.contains(newPath) { paths.append(newPath) }
                    newPath = ""
                }
                .disabled(pathError != nil)
                .accessibilityIdentifier(identifier + ".addPath")
                .selectionDisabled()
                if !newPath.isEmpty, let pathError {
                    ConfigurationFieldError(message: pathError).selectionDisabled()
                }
            }
            .environment(\.editMode, .constant(.inactive))
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
