import SwiftUI

extension OrgWorkflowState {
    var symbol: String {
        switch self {
        case .todo: "circle"
        case .next: "arrow.right.circle"
        case .wait: "hourglass"
        case .someday: "moon"
        case .urgent: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        case .canceled: "xmark.circle"
        }
    }
}

extension OrgItem {
    var workflowTitleColor: Color {
        hasWorkflowState && state != .todo ? OrgendaTheme.workflowColor(state) : .primary
    }
}
