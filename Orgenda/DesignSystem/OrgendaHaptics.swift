import UIKit

/// Action feedback lives at the UI boundary so indexing and background sync
/// stay silent. UIKit also delivers feedback when the initiating view dismisses.
@MainActor
enum OrgendaHaptics {
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func selectionChanged() {
        selection.selectionChanged()
    }

    static func result(_ succeeded: Bool) {
        notification.notificationOccurred(succeeded ? .success : .error)
    }
}
