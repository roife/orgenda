import Foundation

enum DocumentSaveStatus: Equatable {
    case saving, saved, failed(String), unavailable
    case savedOnDevice, pendingSync, conflict

    var title: String {
        switch self {
        case .saving: String(localized: "Saving…")
        case .saved: String(localized: "Saved to folder")
        case .failed: String(localized: "Save failed · Tap to retry")
        case .unavailable: String(localized: "File unavailable")
        case .savedOnDevice: String(localized: "Saved on this device")
        case .pendingSync: String(localized: "Saved on this device · Waiting to sync")
        case .conflict: String(localized: "Saved on this device · Resolve sync conflict")
        }
    }
}
