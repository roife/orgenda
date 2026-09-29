import SwiftUI

@main
struct OrgendaApp: App {
    @UIApplicationDelegateAdaptor(OrgendaApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let size = testViewportSize {
                OrgendaRootView()
                    .environment(\.horizontalSizeClass,
                                 ProcessInfo.processInfo.environment["ORGENDA_UI_TEST_HORIZONTAL_SIZE_CLASS"] == "compact"
                                 ? .compact : .regular)
                    .frame(width: size.width, height: size.height)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ui-test.viewport")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OrgendaRootView()
            }
            #else
            OrgendaRootView()
            #endif
        }
    }

    #if DEBUG
    /// Exercise the normal root view at repeatable window sizes without relying
    /// on iPadOS window-manager drag physics. Only isolated UI fixtures opt in.
    private var testViewportSize: CGSize? {
        guard WorkspaceStore.isUITestWorkspace() else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let width = environment["ORGENDA_UI_TEST_WINDOW_WIDTH"].flatMap(Double.init),
              let height = environment["ORGENDA_UI_TEST_WINDOW_HEIGHT"].flatMap(Double.init),
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
    #endif
}
