import XCTest

final class WorkspaceSyncUITests: XCTestCase {
    func testSearchSettingsOpensMatchingPageAndKeepsQuery() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Appearance")
        let result = app.buttons["search.setting.appearance"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings.workspace"].isHittable)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Appearance")
    }

    func testSearchDocumentOpensEditableSourceAndKeepsResults() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("workflow")
        let result = app.buttons["search.document.inbox.org"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["search.setting.workflow"].exists)
        result.tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Edit"].isSelected)
        XCTAssertTrue(app.buttons["Preview"].exists)
        // The first match is selected; typing replaces it in the real editor.
        editor.typeText("workflow revised")
        XCTAssertTrue((editor.value as? String)?.contains("workflow revised") == true)
        app.navigationBars.buttons["Search"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "workflow")
    }

    func testFixtureStartupShowsIndexedAgendaAndAllowsTabNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["agenda.viewMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["workspace.loading"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.progressIndicators["workspace.loading"].exists)
        XCTAssertTrue(app.staticTexts["Plan iPad reading workflow"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Review quarterly roadmap"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.buttons["files.settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["files.syncStatus"].exists)
        XCTAssertEqual(app.images["files.syncStatus"].label, "Workspace unavailable")
        XCTAssertFalse(app.staticTexts["orgenda Demo"].exists)
        XCTAssertFalse(app.staticTexts["Demo workspace"].exists)
    }

    func testStartupSkeletonKeepsFirstScreenChromeUntilIndexIsReady() {
        verifyStartupSkeleton()
    }

    func testStartupSkeletonInDarkAppearance() {
        verifyStartupSkeleton(appearance: "Dark")
    }

    func testStartupSkeletonAtAccessibilitySize() {
        verifyStartupSkeleton(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func verifyStartupSkeleton(appearance: String = "Light", contentSize: String? = nil) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-appearance", appearance
        ]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launchEnvironment["ORGENDA_UI_TEST_STARTUP_DELAY"] = "15"
        app.launch()

        let skeleton = app.otherElements["workspace.loading"]
        let viewMenu = app.buttons["agenda.viewMenu"]
        let capture = app.buttons["orgenda.capture"]
        XCTAssertTrue(skeleton.waitForExistence(timeout: 5))
        XCTAssertEqual(skeleton.label, "Loading workspace")
        XCTAssertEqual(skeleton.value as? String, "Dashboard")
        XCTAssertFalse(app.progressIndicators["workspace.loading"].exists)
        XCTAssertTrue(viewMenu.exists)
        XCTAssertFalse(viewMenu.isEnabled)
        XCTAssertTrue(capture.exists)
        XCTAssertFalse(capture.isEnabled)
        for tab in ["Dashboard", "Calendar", "Files", "Search"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists)
            XCTAssertTrue(app.tabBars.buttons[tab].isEnabled)
        }
        XCTAssertGreaterThan(
            app.tabBars.buttons["Search"].frame.minX - app.tabBars.buttons["Files"].frame.maxX, 4
        )
        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
        XCTAssertTrue(skeleton.exists)
        XCTAssertFalse(app.buttons["files.settings"].exists)
        XCTAssertFalse(app.staticTexts["No scheduled items"].exists)
        XCTAssertFalse(app.staticTexts["No items in Dashboard"].exists)
        XCTAssertFalse(app.staticTexts["Review quarterly roadmap"].exists)
        let menuFrame = viewMenu.frame
        let captureFrame = capture.frame
        let tabFrame = app.tabBars.buttons["Dashboard"].frame

        XCTAssertTrue(skeleton.waitForNonExistence(timeout: 20))
        XCTAssertTrue(viewMenu.isEnabled)
        XCTAssertTrue(capture.isEnabled)
        XCTAssertEqual(viewMenu.frame.minY, menuFrame.minY, accuracy: 1)
        XCTAssertEqual(capture.frame.minY, captureFrame.minY, accuracy: 1)
        XCTAssertEqual(app.tabBars.buttons["Dashboard"].frame.minY, tabFrame.minY, accuracy: 1)
        XCTAssertTrue(app.staticTexts["Plan iPad reading workflow"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.buttons["files.settings"].waitForExistence(timeout: 5))
    }

    func testFolderPickerCanOpenAndCancel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        let workspace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Workspace & Sync'")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        workspace.tap()
        let choose = app.buttons["workspace.chooseFolder"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
    }
}
