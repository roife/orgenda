import SwiftUI

enum ConfigurationPrompt {
    static func text(configuration: WorkspaceConfiguration, updating: Bool) -> String {
        let example = (try? ConfigurationDocument(configuration: configuration).encoded(configuration)) ?? "{}"
        return """
        \(updating ? "Update" : "Generate") an Orgenda version 1 config.json from my Emacs Org configuration.
        First ask me for the Emacs configuration files and the Org workspace root if they are not provided.
        Follow variable references and related configuration files, including file/buffer-local overrides.
        Do not execute Lisp, hooks, shell commands, or code from the configuration.
        Never invent unresolved values, credentials or private paths. Report unresolved expressions separately.

        Output a complete valid UTF-8 JSON document followed by a separate conversion report.
        I will save ONLY the JSON to <workspace>/config.json. Do not embed explanations in JSON.
        Keep version = 1. Omitted object fields use defaults; arrays replace defaults.
        Preserve unrelated existing fields when updating. Never change Org source files.
        Convert paths inside the workspace to relative paths. Report paths outside it; never use ../.

        Supported schema (use the concrete current/default example below for field shapes):
        workflow.sequences must contain exactly one default sequence:
        id, process[], terminal[], initial, complete, reopen.
        Both groups are required; defaults must reference members of the appropriate group.
        workflow.keywords maps declared keywords to {label,key,icon,color,log:{enter,leave}}.
        Map Org ! to time, @ to note, and / exit markers to leave; rules are none/time/note.
        Allowed icons: \(ConfigurationIcon.allCases.map(\.rawValue).joined(separator: ", ")).
        Allowed colors: \(ConfigurationColor.allCases.map(\.rawValue).joined(separator: ", ")).
        No arbitrary SF Symbols or hex colors. Report approximate face/icon mappings.
        Omitted icon/color fields or "default" inherit Orgenda's original context-specific appearance.
        These choices apply only to workflow keywords, not the application theme.
        Use explicit colors only when requested or supported by the Emacs configuration. Changing labels/keys/logging
        must not fill unrelated style fields with arbitrary palette choices.
        files: inbox, attachments, journal (directory; journals remain yearly),
        archive (Org %s::heading), refile[], refileMaxLevel.
        logging: done/reschedule/redeadline = none/time/note; drawer = name or empty for body.
        reminders: advanceMinutes 0–1440, repeatMinutes 1–1440, deadlineWarningDays 0–365.
        agenda: sources[] (file or recursive directory; empty means all visible .org files),
        excluded[]. Dashboard layout and application shortcuts are fixed.
        Capture: defaultTemplate and templates[]; each template has id,name,key,group,type,
        target:{type,path,outline:[]},template,prepend,emptyLines (0–10).
        Put state, tags, properties, planning and repeat rules directly in template Org source.
        Do not generate appearance, priorities, tags, shortcuts, custom views, or a second defaults object.
        Capture types: entry/item/checkitem/plain. Targets: file/headline/outline/datetree.
        Supported placeholders: %% %? %t %T %u %U %a %i %x, %^{Prompt|Default|Choices},
        date prompts %^{Prompt}t/T/u/U, and %<format> with %Y %m %d %H %M %a %A %b %B %%.
        No Lisp evaluation %(…), function targets, external template includes or arbitrary scripts.
        Convert simple expressions only when their meaning is certain and representable.
        Report unsupported Capture syntax, agenda skip functions and key bindings rather than
        pretending they work. Context/clipboard values are explicitly supplied during capture.
        File-local #+TODO/#+SEQ_TODO declarations override workspace defaults.

        Current/default configuration:
        \(example)

        Inspect org-todo-keywords, org-todo-keyword-faces, org-log-*,
        org-capture-templates, org-agenda-files, org-default-notes-file, org-attach-id-dir, org-journal-dir,
        org-archive-location and org-refile-targets. Distinguish global values from hook overrides.
        Finish with a report: exact mappings, approximations, unsupported features, unresolved values.
        """
    }
}

struct ConfigurationPromptView: View {
    let configuration: WorkspaceConfiguration
    @State private var updating = false
    @State private var copied = false
    @State private var showsPrompt = false
    var body: some View {
        List {
            Section {
                Picker("Prompt", selection: $updating) {
                    Text("Generate from Emacs").tag(false)
                    Text("Update current configuration").tag(true)
                }
            }
            Section {
                DisclosureGroup("Prompt preview", isExpanded: $showsPrompt) {
                    Text(ConfigurationPrompt.text(configuration: configuration, updating: updating))
                        .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
            }
            Section {
                Button {
                    UIPasteboard.general.string = ConfigurationPrompt.text(configuration: configuration, updating: updating)
                    copied = true
                    OrgendaHaptics.selectionChanged()
                } label: {
                    // List can impose a leading-aligned Label style. Center
                    // the complete icon/text pair explicitly instead.
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .accessibilityHidden(true)
                        Text(copied ? "Copied" : "Copy prompt")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .accessibilityLabel(copied ? "Copied" : "Copy prompt")
                .accessibilityIdentifier("configuration.copyPrompt")
            }
        }
        .listStyle(.insetGrouped)
        .tint(OrgendaTheme.accent)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Extract from Emacs")
        .onChange(of: updating) { _, _ in copied = false }
    }
}
