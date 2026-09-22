import Foundation

enum DocumentSaveStatus: Equatable {
    case saving, saved, failed(String), unavailable

    var title: String {
        switch self {
        case .saving: String(localized: "Saving…")
        case .saved: String(localized: "Saved to folder")
        case .failed: String(localized: "Save failed · Tap to retry")
        case .unavailable: String(localized: "File unavailable")
        }
    }
}
