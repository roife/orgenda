import SwiftUI

private struct ConfigurationWorkflowKey: EnvironmentKey {
    static let defaultValue = WorkspaceConfiguration.classic.workflow
}
private struct WorkspaceConfigurationKey: EnvironmentKey {
    static let defaultValue = WorkspaceConfiguration.classic
}
extension EnvironmentValues {
    var workspaceConfiguration: WorkspaceConfiguration {
        get { self[WorkspaceConfigurationKey.self] }
        set { self[WorkspaceConfigurationKey.self] = newValue }
    }
    var orgWorkflow: WorkspaceConfiguration.Workflow {
        get { self[ConfigurationWorkflowKey.self] }
        set { self[ConfigurationWorkflowKey.self] = newValue }
    }
}
