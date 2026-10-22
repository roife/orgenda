import Foundation

extension WorkspaceConfiguration {
    /// A workflow preset never changes paths, templates, reminder rules or history.
    func applyingClassicWorkflowPreset() -> WorkspaceConfiguration {
        var result = self
        result.workflow = Self.classic.workflow
        return result
    }
}
