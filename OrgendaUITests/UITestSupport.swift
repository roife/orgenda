import XCTest

extension XCTestCase {
    func launchTestApp(_ arguments: [String] = [], workspace: String = "--demo-workspace",
                       appearance: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [workspace, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        if let appearance { app.launchArguments += ["-appearance", appearance] }
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    func attachScreenshot(_ name: String, screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
