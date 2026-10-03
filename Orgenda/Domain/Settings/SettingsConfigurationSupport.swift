import Foundation

extension WorkspaceConfiguration {
    /// A workflow preset never changes paths, templates, reminder rules or history.
    func applyingClassicWorkflowPreset() -> WorkspaceConfiguration {
        var result = self
        result.workflow = Self.classic.workflow
        return result
    }
}

enum ConfigurationImportFailure {
    static func message(for error: Error) -> String {
        let detail = error.localizedDescription
        if detail.contains("version") {
            return String(localized: "Use an Orgenda configuration with version set to 1.")
        }
        if detail.contains("path must stay") || detail.contains("expected an .org") || detail.contains("target must be an .org") {
            return String(localized: "Check file paths: use relative paths inside the workspace and .org files for task and capture destinations.")
        }
        if detail.contains("workflow") {
            return String(localized: "Check task states: include one sequence with both active and completed states, and choose valid default actions.")
        }
        if detail.contains("reminders") {
            return String(localized: "Use 0–1440 minutes of advance notice, a 1–1440 minute repeat interval, and 0–365 days of deadline lookahead.")
        }
        if detail.contains("capture") {
            return String(localized: "Check capture templates, their default selection, destination paths and required headings.")
        }
        if detail.contains("archive") {
            return String(localized: "Separate the archive file and heading with ::, for example %s_archive::* Archived.")
        }
        if error is ConfigurationFailure { return detail }
        return String(localized: "Paste valid JSON only, without code fences or the conversion report. Check commas, quotes and brackets.")
    }
}
