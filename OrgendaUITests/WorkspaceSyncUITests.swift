import XCTest

final class WorkspaceSyncUITests: XCTestCase {
    func testSearchDocumentOpensPreviewAndKeepsResults() {
        let app = launchTestApp(workspace: "--ui-test-workspace")
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

    func testStartupSkeletonKeepsFirstScreenChromeUntilIndexIsReady() {
        verifyStartupSkeleton()
    }

    func testStartupSkeletonAtAccessibilitySize() {
        verifyStartupSkeleton(appearance: "Dark", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
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
        let app = launchTestApp()
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        let workspace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Workspace & Sync'")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        workspace.tap()
        let choose = app.buttons["workspace.chooseFolder"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        for provider in ["iCloud", "oneDrive", "googleDrive", "dropbox", "webDAV", "local"] {
            XCTAssertTrue(app.buttons["storage.provider.\(provider)"].waitForExistence(timeout: 3))
        }
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

    func testWebDAVFormRejectsInsecureAddressWithoutConnecting() {
        let app = openWorkspaceSettings()
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
        let conflict = app.buttons["workspace.resolveConflict"]
        XCTAssertTrue(conflict.waitForExistence(timeout: 3))
        let connection = app.descendants(matching: .any).matching(identifier: "workspace.connection").firstMatch
        XCTAssertTrue(connection.exists)
        let originalConnection = connection.label

        app.buttons["workspace.chooseFolder"].tap()
        let oneDrive = app.buttons["storage.provider.oneDrive"]
        XCTAssertTrue(oneDrive.waitForExistence(timeout: 3))
        oneDrive.tap()
        let keepCopies = app.buttons["Keep Copies and Change Location"]
        XCTAssertTrue(keepCopies.waitForExistence(timeout: 3))
        let explanation = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "Current location: WebDAV", "New location: OneDrive"
        )).firstMatch
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(explanation.label.contains("Existing files stay where they are and will not be moved or copied."))
        XCTAssertTrue(explanation.label.contains("Unsynced edits will be kept in orgenda → Unsaved Edits"))
        XCTAssertTrue(explanation.label.contains("They will not be uploaded to the new location."))

        // Cancel the confirmation without dismissing the provider picker below it.
        let cancel = app.buttons.matching(NSPredicate(
            format: "label == 'Cancel' AND identifier != 'storage.cancel'"
        )).firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // The native popover can cover the navigation bar. Dismiss it
            // from the exposed area below its actual bounds instead.
            let popover = app.popovers.firstMatch
            XCTAssertTrue(popover.exists)
            XCTAssertLessThan(popover.frame.maxY, app.frame.maxY)
            let point = CGVector(dx: app.frame.midX,
                                 dy: (popover.frame.maxY + app.frame.maxY) / 2)
            app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
        }
        XCTAssertTrue(keepCopies.waitForNonExistence(timeout: 3))
        XCTAssertTrue(oneDrive.isHittable)
        app.buttons["storage.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Workspace & Sync"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["storage.provider.webDAV"].exists)
        XCTAssertTrue(conflict.exists, "Canceling must keep the unresolved workspace conflict.")
        XCTAssertEqual(connection.label, originalConnection, "Canceling must keep the current storage connection.")
    }

    private func openWorkspaceSettings(extraArguments: [String] = []) -> XCUIApplication {
        let app = launchTestApp(extraArguments, workspace: "--ui-test-workspace")
        app.selectRootTab("Files")
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
