import SwiftUI

/// One presentation for workflow states.
/// A symbol embedded in Text supplies a baseline beside multiline headings.
struct OrgWorkflowIcon: View {
    let keyword: String
    private var suppliedState: OrgWorkflowState?
    @Environment(\.orgWorkflow) private var workflow

    init(_ state: OrgWorkflowState) { keyword = state.rawValue; suppliedState = state }
    init(keyword: String) { self.keyword = keyword; suppliedState = nil }

    var body: some View {
        let state = suppliedState ?? workflow.state(keyword)
        Text(Image(systemName: state?.symbol ?? "questionmark.circle"))
            .foregroundStyle(state.map(OrgendaTheme.workflowColor) ?? .secondary)
            .fixedSize()
            .accessibilityLabel(state?.title ?? keyword)
    }
}

struct OrgWorkflowPicker: View {
    @Environment(\.orgWorkflow) private var workflow
    @Binding var selection: OrgWorkflowState
    var states: [OrgWorkflowState] = OrgWorkspaceConfiguration.taskStates

    var body: some View {
        Picker(selection: $selection) {
            ForEach(states) { state in
                OrgWorkflowLabel(state: state)
                    .foregroundStyle(OrgendaTheme.workflowColor(state))
                    .tag(state)
                    .accessibilityIdentifier("workflow.option.\(state.rawValue)")
            }
        } label: {
            Text("Status")
        } currentValueLabel: {
            OrgWorkflowLabel(state: selection)
                .foregroundStyle(OrgendaTheme.workflowColor(selection))
        }
        .pickerStyle(.menu)
        .accessibilityValue(selection.title)
        .tint(OrgendaTheme.workflowColor(selection))
        .background {
            // Picker labels do not perform actions. Keep real controls in the
            // scene for the configured workflow keyboard shortcuts instead.
            shortcutCommands.hidden()
        }
    }

    private var shortcutCommands: some View {
        ForEach(states) { state in
            if let key = workflow.keywords[state.rawValue]?.key.first {
                Button(state.title) { selection = state }
                    .keyboardShortcut(KeyEquivalent(key), modifiers: [])
                    .accessibilityHidden(true)
            }
        }
    }
}

struct OrgWorkflowLabel: View {
    let state: OrgWorkflowState

    var body: some View {
        Label(state.title, systemImage: state.symbol)
    }
}
