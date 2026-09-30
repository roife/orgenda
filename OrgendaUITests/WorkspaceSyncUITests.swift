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

    func testSearchDocumentOpensPreviewAndKeepsResults() {
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
        XCTAssertTrue(app.scrollViews["org.preview.scroll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Preview"].isSelected)
        XCTAssertFalse(editor.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["Edit"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Edit"].isSelected)
        XCTAssertTrue(app.buttons["Preview"].exists)
        // Explicitly entering Edit selects the first match in the real editor.
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
        let local = app.buttons["storage.provider.local"]
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        local.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' AND identifier != 'storage.cancel'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["storage.connectionError"].exists)
        app.buttons["storage.cancel"].tap()
        XCTAssertTrue(app.buttons["storage.cancel"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
    }

    func testStoragePickerShowsEveryProviderAndCancelKeepsWorkspace() {
        let app = openWorkspaceSettings()
        defer { app.terminate() }
        app.buttons["workspace.chooseFolder"].tap()
        for provider in ["iCloud", "oneDrive", "googleDrive", "dropbox", "webDAV", "local"] {
            XCTAssertTrue(app.buttons["storage.provider.\(provider)"].waitForExistence(timeout: 3))
        }
        app.buttons["storage.cancel"].tap()
        XCTAssertTrue(app.buttons["storage.cancel"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Workspace & Sync"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["workspace.error"].exists)
    }

    func testWebDAVFormRejectsInsecureAddressWithoutConnecting() {
        let app = openWorkspaceSettings()
        defer { app.terminate() }
        app.buttons["workspace.chooseFolder"].tap()
        app.buttons["storage.provider.webDAV"].tap()
        XCTAssertTrue(app.navigationBars["Connect WebDAV"].waitForExistence(timeout: 3))
        let connect = app.buttons["storage.webDAV.connect"]
        XCTAssertFalse(connect.isEnabled)
        let server = app.textFields["storage.webDAV.server"]
        server.tap()
        server.typeText("http://dav.example.com")
        let username = app.textFields["storage.webDAV.username"]
        username.tap()
        username.typeText("alice")
        let password = app.secureTextFields["storage.webDAV.password"]
        password.tap()
        password.typeText("test-password")
        app.textFields["storage.webDAV.directory"].tap()
        app.textFields["storage.webDAV.directory"].typeText("\n")
        let error = app.staticTexts["storage.webDAV.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "Enter a valid HTTPS server address without a username, password, query, or fragment.")
        XCTAssertTrue(app.navigationBars["Connect WebDAV"].exists)
    }

    func testConflictPreviewAndReplacementConfirmation() {
        let app = openWorkspaceSettings(extraArguments: ["--storage-sync-fixture"])
        defer { app.terminate() }
        app.buttons["workspace.resolveConflict"].tap()
        let conflict = app.buttons["storage.conflict.notes.org"]
        XCTAssertTrue(conflict.waitForExistence(timeout: 3))
        conflict.tap()
        XCTAssertTrue(app.scrollViews["storage.conflict.local"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.scrollViews["storage.conflict.remote"].exists)
        let replace = app.buttons["storage.conflict.useRemote"]
        if !replace.isHittable { app.swipeUp() }
        replace.tap()
        dismissConfirmation(in: app, navigationTitle: "Resolve Conflict")
        XCTAssertTrue(app.navigationBars["Resolve Conflict"].exists)
    }

    func testChangingStorageWithPendingEditsRequiresKeepingCopies() {
        let app = openWorkspaceSettings(extraArguments: ["--storage-sync-fixture"])
        defer { app.terminate() }
        app.buttons["workspace.chooseFolder"].tap()
        XCTAssertTrue(app.buttons["Keep Copies and Continue"].waitForExistence(timeout: 3))
        dismissConfirmation(in: app, navigationTitle: "Workspace & Sync")
        XCTAssertTrue(app.navigationBars["Workspace & Sync"].exists)
        XCTAssertFalse(app.buttons["storage.provider.webDAV"].exists)
    }

    private func openWorkspaceSettings(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
        app.launch()
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        let workspace = app.buttons["settings.workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        workspace.tap()
        XCTAssertTrue(app.navigationBars["Workspace & Sync"].waitForExistence(timeout: 5))
        if !extraArguments.contains("--storage-sync-fixture") {
            XCTAssertTrue(app.buttons["workspace.chooseFolder"].waitForExistence(timeout: 5))
        }
        return app
    }

    private func dismissConfirmation(in app: XCUIApplication, navigationTitle: String) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            // Popover-style confirmation dialogs omit a visible cancel row.
            // Tapping the title outside the popover dismisses it without choosing an action.
            app.navigationBars[navigationTitle]
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
