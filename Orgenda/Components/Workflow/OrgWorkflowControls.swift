import SwiftUI

/// One presentation for workflow states.
/// A symbol embedded in Text supplies a baseline beside multiline headings.
struct OrgWorkflowIcon: View {
    let keyword: String

    init(_ state: OrgWorkflowState) { keyword = state.rawValue }
    init(keyword: String) { self.keyword = keyword }

    var body: some View {
        let state = OrgWorkflowState(rawValue: keyword)
        Text(Image(systemName: state?.symbol ?? "questionmark.circle"))
            .foregroundStyle(state.map(OrgendaTheme.workflowColor) ?? .secondary)
            .fixedSize()
            .accessibilityLabel(state?.title ?? keyword)
    }
}

struct OrgWorkflowPicker: View {
    @Binding var selection: OrgWorkflowState

    var body: some View {
        OrgendaFlowLayout(horizontalSpacing: 2, verticalSpacing: 8) {
            ForEach(OrgWorkspaceConfiguration.taskStates) { state in
                OrgWorkflowOption(state: state, isSelected: selection == state) {
                    selection = state
                }
                .accessibilityIdentifier("workflow.option.\(state.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
        .accessibilityValue(selection.title)
    }
}

struct OrgWorkflowOption: View {
    let state: OrgWorkflowState
    let isSelected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var symbolSize = 21.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                OrgWorkflowIcon(state)
                    .font(.system(size: symbolSize, weight: .medium))
                Text(state.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OrgendaTheme.workflowColor(state))
                    .fixedSize(horizontal: false, vertical: true)
            }
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(isSelected ? OrgendaTheme.workflowColor(state).opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? OrgendaTheme.workflowColor(state) : .clear, lineWidth: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
