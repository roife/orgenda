import SwiftUI
import UIKit

enum OrgendaQuickAction: String, CaseIterable {
    case newTask = "com.roifewu.Orgenda.new-task"
    case today = "com.roifewu.Orgenda.today"
    case search = "com.roifewu.Orgenda.search"
    case files = "com.roifewu.Orgenda.files"
}

@MainActor
final class OrgendaApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication {
            configuration.delegateClass = OrgendaSceneDelegate.self
        }
        return configuration
    }
}

/// SwiftUI supplies this observable scene delegate to that scene's environment.
/// Keep requests per scene, including requests delivered before the workspace loads.
@MainActor
final class OrgendaSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    struct Request: Identifiable {
        let id = UUID()
        let action: OrgendaQuickAction
    }

    @Published var pendingAction: Request?
    private weak var windowScene: UIWindowScene?

    var isPresentingModal: Bool {
        windowScene?.windows.contains {
            $0.rootViewController?.presentedViewController != nil
        } ?? false
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        windowScene = scene as? UIWindowScene
        if let shortcut = connectionOptions.shortcutItem {
            accept(shortcut)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(accept(shortcutItem))
    }

    @discardableResult
    func accept(_ shortcut: UIApplicationShortcutItem) -> Bool {
        guard let action = OrgendaQuickAction(rawValue: shortcut.type) else { return false }
        pendingAction = Request(action: action)
        return true
    }
}
