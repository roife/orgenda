import Foundation

enum SearchPresentation: Identifiable {
    case item(OrgItem)
    case settings(SettingsDestination?)

    var id: String {
        switch self {
        case .item(let item): "item-\(item.id)"
        case .settings(let destination): "settings-\(destination?.rawValue ?? "root")"
        }
    }
}
