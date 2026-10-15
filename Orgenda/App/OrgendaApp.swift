import SwiftUI

@main
struct OrgendaApp: App {
    @UIApplicationDelegateAdaptor(OrgendaApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        WindowGroup {
            OrgendaRootView()
        }
    }
}
