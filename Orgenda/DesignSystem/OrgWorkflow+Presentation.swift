import SwiftUI

extension OrgWorkflowState {
    var symbol: String {
        icon.symbol
    }
}

extension OrgItem {
    var workflowTitleColor: Color {
        hasWorkflowState && (state.rawValue != "TODO" || state.color != .default)
            ? OrgendaTheme.workflowColor(state) : .primary
    }
}
