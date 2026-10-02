import XCTest

final class ConfigurationUITests: XCTestCase {
    func testSettingsPanelNavigationAndAppearance() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Do not force -appearance here: launch-argument defaults override
        // persisted values, preventing the picker from changing the theme.
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        reveal("settings.appearance", in: app).tap()
        XCTAssertTrue(app.buttons["Light"].waitForExistence(timeout: 3))
        app.buttons["Light"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists, "Appearance is an inline choice, not another page.")
        XCTAssertTrue(app.buttons["settings.workspace"].label.contains("Workspace & Sync"))
        screenshot("Settings panel light", app: app)
        reveal("settings.appearance", in: app).tap()
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 3))
        app.buttons["Dark"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        screenshot("Settings panel dark", app: app)
        reveal("settings.reminders", in: app).tap()
        XCTAssertTrue(app.switches["settings.reminders.enabled"].waitForExistence(timeout: 3))
        screenshot("Reminder settings", app: app)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["files.settings"].waitForExistence(timeout: 3))
        app.buttons["files.settings"].tap()
        app.buttons["settings.workspace"].tap()
        XCTAssertTrue(app.buttons["workspace.chooseFolder"].waitForExistence(timeout: 3))
        screenshot("Workspace settings", app: app)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["files.settings"].waitForExistence(timeout: 3))
    }

    func testSettingsPanelWithLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-appearance", "Dark"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        XCTAssertTrue(app.buttons["settings.workspace"].waitForExistence(timeout: 3))
        screenshot("Settings panel accessibility", app: app)
        reveal("settings.appearance", in: app).tap()
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 3))
        app.buttons["Dark"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        screenshot("Appearance inline accessibility", app: app)
        XCTAssertTrue(app.buttons["settings.done"].isHittable)
        app.buttons["settings.done"].tap()
    }

    func testSettingsShowsWorkflowAndCopiesEmacsPrompt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--workflow-settings-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let filesTab = app.tabBars.buttons["Files"]
        XCTAssertTrue(filesTab.waitForExistence(timeout: 5))
        filesTab.tap()
        app.buttons["files.settings"].tap()
        screenshot("Settings direct entry points", app: app)
        XCTAssertFalse(app.navigationBars["Workspace configuration"].exists)
        XCTAssertFalse(app.staticTexts["config.json · Workspace root"].exists)
        XCTAssertFalse(app.buttons["Appearance choices"].exists)
        XCTAssertFalse(app.buttons["Keyboard shortcuts"].exists)
        XCTAssertFalse(app.buttons["Tags & priorities"].exists)
        XCTAssertFalse(app.buttons["Agenda & Dashboard"].exists)
        reveal("settings.workflow", in: app).tap()
        XCTAssertTrue(app.navigationBars["Workflow"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["In progress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Terminal"].exists)
        XCTAssertFalse(app.buttons["States & order"].exists)
        XCTAssertFalse(app.buttons["Add sequence"].exists)
        XCTAssertTrue(app.buttons["configuration.addProcess"].exists)
        XCTAssertTrue(app.buttons["configuration.addTerminal"].exists)
        screenshot("Workflow", app: app)
        addState("WAIT", terminal: false, app: app)
        addState("CANCELED", terminal: true, app: app)
        let waitRow = app.cells.containing(.button, identifier: "configuration.keyword.WAIT").firstMatch
        let todoRow = app.cells.containing(.button, identifier: "configuration.keyword.TODO").firstMatch
        XCTAssertTrue(waitRow.exists)
        waitRow.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            .press(forDuration: 1, thenDragTo: todoRow.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.2)))
        XCTAssertLessThan(app.buttons["configuration.keyword.WAIT"].frame.minY,
                          app.buttons["configuration.keyword.TODO"].frame.minY)
        let canceledRow = app.cells.containing(.button, identifier: "configuration.keyword.CANCELED").firstMatch
        let doneRow = app.cells.containing(.button, identifier: "configuration.keyword.DONE").firstMatch
        canceledRow.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            .press(forDuration: 1, thenDragTo: doneRow.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.2)))
        XCTAssertLessThan(app.buttons["configuration.keyword.CANCELED"].frame.minY,
                          app.buttons["configuration.keyword.DONE"].frame.minY)
        screenshot("Workflow directly reordered", app: app)
        // Reenter the page to prove that the order was saved, not just moved visually.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal("settings.workflow", in: app).tap()
        XCTAssertLessThan(app.buttons["configuration.keyword.WAIT"].frame.minY,
                          app.buttons["configuration.keyword.TODO"].frame.minY)
        XCTAssertLessThan(app.buttons["configuration.keyword.CANCELED"].frame.minY,
                          app.buttons["configuration.keyword.DONE"].frame.minY)
        app.buttons["configuration.addProcess"].tap()
        app.textFields["configuration.newKeyword"].typeText("DRAFT")
        app.buttons["configuration.cancelKeyword"].tap()
        XCTAssertFalse(app.buttons["configuration.keyword.DRAFT"].exists)
        app.buttons["configuration.keyword.TODO"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["configuration.keyword.preview"].firstMatch.waitForExistence(timeout: 3))
        screenshot("State appearance", app: app)
        app.buttons["configuration.keyword.done"].tap()
        XCTAssertTrue(app.navigationBars["Workflow"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        reveal("settings.emacs", in: app).tap()
        let copy = app.buttons["configuration.copyPrompt"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertEqual(copy.frame.midX, app.frame.midX, accuracy: 3)
        let label = copy.staticTexts["Copy prompt"]
        XCTAssertTrue(label.exists)
        XCTAssertLessThan(abs(label.frame.midX - copy.frame.midX), 30,
                          "The icon and title must be centered, not leading-aligned.")
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 3))
        screenshot("Emacs prompt", app: app)
    }

    func testSettingsSearchOpensWorkflowWithoutCategoryHub() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Search"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("workflow")
        let result = app.buttons["search.setting.workflow"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.navigationBars["Workflow"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["configuration.addProcess"].exists)
        XCTAssertFalse(app.navigationBars["Workspace configuration"].exists)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "workflow")
    }

    func testConfigurationAndTemplateAtAccessibilitySize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-appearance", "Dark"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        screenshot("Settings accessibility dark", app: app)
        reveal("settings.capture", in: app).tap()
        let template = app.buttons["configuration.template.inbox"]
        XCTAssertTrue(template.waitForExistence(timeout: 3))
        for _ in 0..<4 where !template.isHittable { app.swipeUp() }
        template.tap()
        XCTAssertTrue(app.navigationBars["Capture template"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Name"].exists || app.textViews["Name"].exists)
        screenshot("Template accessibility dark", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Capture templates"].waitForExistence(timeout: 3))
    }

    func testFilesRemindersAndConfigAreDirectDestinations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        reveal("settings.files", in: app).tap()
        XCTAssertTrue(app.navigationBars["Files & agenda"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Agenda sources"].exists)
        XCTAssertTrue(app.staticTexts["Default locations"].exists)
        screenshot("Files and agenda combined", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        reveal("settings.reminders", in: app).tap()
        XCTAssertTrue(app.switches["settings.reminders.enabled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Workspace timing"].exists)
        screenshot("Unified reminders", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal("settings.configuration", in: app).tap()
        XCTAssertTrue(app.navigationBars["Configuration file"].waitForExistence(timeout: 3))
        let json = app.staticTexts["configuration.json"]
        XCTAssertTrue(json.waitForExistence(timeout: 3), "JSON is visible without expanding a disclosure.")
        XCTAssertTrue(json.label.contains("\"workflow\""))
        let preset = app.buttons["Apply classic workflow preset"]
        let reset = app.buttons["Restore generic defaults"]
        XCTAssertTrue(preset.isHittable)
        XCTAssertTrue(reset.isHittable)
        XCTAssertLessThan(preset.frame.maxY, reset.frame.maxY)
        XCTAssertLessThan(reset.frame.maxY, json.frame.minY)
        screenshot("Configuration file inline preview", app: app)
    }

    @discardableResult
    private func reveal(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[id]
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, id)
        return element
    }

    private func addState(_ keyword: String, terminal: Bool, app: XCUIApplication) {
        reveal(terminal ? "configuration.addTerminal" : "configuration.addProcess", in: app).tap()
        let field = app.textFields["configuration.newKeyword"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(keyword)
        app.buttons["configuration.addKeyword"].tap()
        XCTAssertTrue(app.buttons["configuration.keyword.\(keyword)"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Connect a workspace first."].exists)
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
