import SwiftUI

enum ConfigurationPrompt {
    static func text(configuration: WorkspaceConfiguration) -> String {
        let currentConfiguration = (try? ConfigurationDocument(configuration: configuration).encoded(configuration)) ?? "{}"
        return """
        Generate a minimal Orgenda version 1 config.json from my Emacs Org configuration.
        Include only supported settings needed to reproduce my configured behavior.
        Ask for missing Emacs configuration files, and the workspace root when needed to resolve paths.
        Follow relevant variable references and related configuration files. Distinguish global settings
        from file/buffer-local and hook overrides; do not promote local overrides to workspace defaults.
        Do not execute Lisp, hooks, shell commands, or code from the configuration.
        Never invent unresolved values, credentials or private paths. Report unresolved expressions separately.

        Output one minimal, valid, standalone UTF-8 JSON document followed by a separate conversion report.
        I will save ONLY the JSON to <workspace>/config.json. Do not embed explanations in JSON.
        Keep version = 1. All other fields are optional and use the built-in defaults listed below when omitted.
        Every emitted field must come from a resolved Emacs setting, an existing customization to preserve,
        or the minimum dependency needed to keep those settings valid. Do not add suggested improvements.
        Omit default-valued fields, redundant keyword entries and empty objects. Do not add null placeholders,
        sample paths, sample templates, inferred labels/icons/colors, or sections merely because they are supported.
        Keep false, 0, empty strings or empty arrays only when omission would change the intended behavior.
        Arrays replace defaults, so preserve all needed entries and their order when emitting an array.
        The current configuration below is context, not an output template; it includes built-in defaults.
        When updating it, preserve unrelated non-default customizations, without copying default-valued fields.
        Never change Org source files.
        Convert paths inside the workspace to relative paths. Report paths outside it; never use ../.

        Supported schema and built-in defaults (a whitelist, not a checklist of fields to output):
        workflow.sequences, when supplied, must contain exactly one sequence:
        id, process[], terminal[], initial, complete, reopen.
        Defaults: id = tasks, process = [TODO], terminal = [DONE], initial/reopen = TODO, complete = DONE.
        After defaults are applied, both groups must be nonempty; initial/reopen must belong to process,
        and complete to terminal. Include these references when the default states are no longer present.
        Do not invent extra states or silently merge multiple Emacs sequences; report unsupported differences.
        workflow.keywords maps declared keywords to {label,key,icon,color,log:{enter,leave}}.
        Its default is {}; label/key default to empty, icon/color to default, and enter/leave to none.
        Include only individual properties actually configured for a declared keyword. Do not repeat its
        token as a label or add a style entry for every state. Keys must be unique single characters or empty.
        Map Org ! to time, @ to note, and / exit markers to leave; rules are none/time/note.
        Allowed icons: \(ConfigurationIcon.allCases.map(\.rawValue).joined(separator: ", ")).
        Allowed colors: \(ConfigurationColor.allCases.map(\.rawValue).joined(separator: ", ")).
        No arbitrary SF Symbols or hex colors. Use approximate face/icon mappings only when requested,
        and report them. Otherwise omit unrepresentable styles and report the limitation.
        Omitted icon/color fields inherit Orgenda's original context-specific appearance.
        These choices apply only to workflow keywords, not the application theme.
        Changing labels/keys/logging must not fill unrelated style fields with arbitrary palette choices.
        files defaults: inbox = inbox.org, attachments = .attach, journal = journal (a directory; journals remain yearly),
        archive = %s_archive::* Archived, refile = [], refileMaxLevel = 3 (allowed 1–99).
        inbox and refile entries must name .org files. Archive paths are relative to each source file's directory.
        logging: done/reschedule/redeadline = none/time/note; drawer = name or empty for body.
        Defaults: done/reschedule/redeadline = none, drawer = LOGBOOK.
        reminders: advanceMinutes 0–1440, repeatMinutes 1–1440, deadlineWarningDays 0–365.
        Defaults: advanceMinutes = 15, repeatMinutes = 5, deadlineWarningDays = 14.
        Do not add reminders without an explicit setting with equivalent meaning.
        agenda: sources[] (file or recursive directory; empty means all visible .org files),
        excluded[]; both default to []. Do not invent exclusions or broaden unresolved sources to all files.
        Dashboard layout and application shortcuts are fixed.
        Capture: defaultTemplate and templates[]; each template has id,name,key,group,type,
        target:{type,path,outline:[]},template,prepend,emptyLines (0–10).
        Defaults: defaultTemplate = inbox; templates contains one template with id = inbox, name = Inbox task,
        key = t, group = empty, type = entry, target = {type:file,path:inbox.org,outline:[]},
        template = "* TODO %^{Title}\\n%?", prepend = false, emptyLines = 1.
        Omitted fields inside supplied templates use these same defaults; include fields needed to avoid
        unintended fallback values. Template IDs and nonempty single-character keys must be unique.
        defaultTemplate must reference a retained template; templates cannot be empty.
        Generate stable IDs only as needed for converted templates, and report any default-template selection
        that Emacs does not specify. Do not append the built-in Inbox template to converted templates.
        Headline/outline targets require a nonempty outline; entry templates must start with "* ".
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

        Minimal output examples (never copy their values unless they match my configuration):
        If only logging.done needs to change to time: {"version":1,"logging":{"done":"time"}}.
        If no overrides or existing customizations are needed: {"version":1}.

        Current configuration for preserving existing customizations only:
        \(currentConfiguration)

        Inspect org-todo-keywords, org-todo-keyword-faces, org-log-*,
        org-capture-templates, org-agenda-files, org-default-notes-file, org-attach-id-dir, org-journal-dir,
        org-archive-location, org-refile-targets and org-deadline-warning-days when present.
        Before responding, check every emitted field against the whitelist, its source and the built-in default.
        Remove anything unnecessary, then verify paths, state references, template references and array semantics.
        Finish with a concise report of relevant mappings, requested approximations, unsupported features,
        unresolved values and any required dependency choices. Keep all of this outside the JSON.
        """
    }
}

struct ConfigurationPromptSection: View {
    let configuration: WorkspaceConfiguration
    @State private var copied = false
    @State private var showsPrompt = false

    var body: some View {
        Section("Extract from Emacs") {
            DisclosureGroup("Full conversion prompt", isExpanded: $showsPrompt) {
                Text(ConfigurationPrompt.text(configuration: configuration))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration.promptPreview")
            }
            .accessibilityIdentifier("configuration.showPrompt")

            Button(LocalizedStringKey(copied ? "Prompt copied" : "Copy prompt")) {
                UIPasteboard.general.string = ConfigurationPrompt.text(configuration: configuration)
                copied = true
                OrgendaHaptics.selectionChanged()
                UIAccessibility.post(notification: .announcement, argument: String(localized: "Prompt copied"))
            }
            .accessibilityIdentifier("configuration.copyPrompt")
        }
        .onChange(of: configuration) { _, _ in copied = false }
    }
}
