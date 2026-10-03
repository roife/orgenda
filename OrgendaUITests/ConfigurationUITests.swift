import XCTest
import UIKit

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
        chooseAppearance("System", in: app)
        // Reopen once to establish the system's actual appearance, regardless
        // of the simulator's style or a previous test's saved preference.
        app.buttons["settings.done"].tap()
        app.buttons["files.settings"].tap()
        let systemBrightness = appearanceRowBrightness(in: app)
        reveal("settings.appearance", in: app).tap()
        XCTAssertTrue(app.buttons["Light"].waitForExistence(timeout: 3))
        app.buttons["Light"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists, "Appearance is an inline choice, not another page.")
        XCTAssertTrue(app.buttons["settings.workspace"].label.contains("Workspace & Sync"))
        XCTAssertGreaterThan(appearanceRowBrightness(in: app), 0.7)
        screenshot("Settings panel light", app: app)
        reveal("settings.appearance", in: app).tap()
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 3))
        app.buttons["Dark"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertLessThan(appearanceRowBrightness(in: app), 0.3)
        screenshot("Settings panel dark", app: app)
        // Switch from the opposite style so System must visibly update the
        // already-presented sheet on both light and dark simulators.
        if systemBrightness < 0.5 { chooseAppearance("Light", in: app) }
        chooseAppearance("System", in: app)
        XCTAssertEqual(appearanceRowBrightness(in: app), systemBrightness, accuracy: 0.1,
                       "System must update Settings without dismissing the sheet.")
        screenshot("Settings panel follows system immediately", app: app)
        reveal("settings.reminders", in: app).tap()
        XCTAssertTrue(app.switches["settings.reminders.enabled"].waitForExistence(timeout: 3))
        screenshot("Reminder settings", app: app)
        XCTAssertFalse(app.buttons["settings.done"].exists)
        app.buttons["configuration.back"].tap()
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
        XCTAssertFalse(app.buttons["Edit"].exists, "Workflow ordering must always be available.")
        XCTAssertFalse(app.buttons["configuration.save"].exists)
        XCTAssertFalse(app.buttons["settings.done"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'configuration.keyword.reorder.'")
        ).firstMatch.exists, "Ordering must use the system control, not a custom drag handle.")
        for token in ["TODO", "WAIT", "DONE", "CANCELED"] {
            let handle = nativeReorderHandle(for: token, in: app)
            let state = app.buttons["configuration.keyword.\(token)"]
            XCTAssertTrue(handle.isHittable, "Every state must expose its native reorder control without tapping Edit.")
            XCTAssertGreaterThan(handle.frame.minX, state.frame.midX,
                                 "The system reorder control stays at the trailing side of the state row.")
        }
        reorderState("WAIT", before: "TODO", in: app)
        reorderState("CANCELED", before: "DONE", in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        // Reenter without any save action to prove reordering persists automatically.
        app.buttons["configuration.back"].tap()
        reveal("settings.workflow", in: app).tap()
        XCTAssertLessThan(app.buttons["configuration.keyword.WAIT"].frame.minY,
                          app.buttons["configuration.keyword.TODO"].frame.minY)
        XCTAssertLessThan(app.buttons["configuration.keyword.CANCELED"].frame.minY,
                          app.buttons["configuration.keyword.DONE"].frame.minY)
        screenshot("Workflow automatically saved after reordering", app: app)
        app.buttons["configuration.addProcess"].tap()
        let draftKeyword = app.textFields["configuration.newKeyword"]
        XCTAssertTrue(draftKeyword.waitForExistence(timeout: 3))
        draftKeyword.tap()
        draftKeyword.typeText("DRAFT")
        app.buttons["configuration.cancelKeyword"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard Changes"].tap()
        XCTAssertFalse(app.buttons["configuration.keyword.DRAFT"].exists)
        app.buttons["configuration.keyword.TODO"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["configuration.keyword.preview"].firstMatch.waitForExistence(timeout: 3))
        screenshot("State appearance", app: app)
        app.buttons["configuration.keyword.done"].tap()
        XCTAssertTrue(app.navigationBars["Workflow"].waitForExistence(timeout: 3))
        app.buttons["configuration.back"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        reveal("settings.configuration", in: app).tap()
        XCTAssertTrue(app.navigationBars["Configuration file"].waitForExistence(timeout: 3))
        let copy = app.buttons["configuration.copyPrompt"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        copy.tap()
        XCTAssertTrue(app.buttons["configuration.copyPrompt"].label.contains("Prompt copied"))
        let prompt = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                          "Generate an Orgenda version 1 config.json")).firstMatch
        XCTAssertFalse(prompt.exists)
        reveal("configuration.showPrompt", in: app).tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        screenshot("Configuration file with expanded Emacs prompt", app: app)
    }

    func testWorkflowStateSheetAndContextActionsPersist() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--workflow-settings-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        reveal("settings.workflow", in: app).tap()

        addState("WAIT", terminal: false, displayName: "Waiting", key: "w",
                 icon: "hourglass", color: "amber", app: app)
        app.buttons["configuration.back"].tap()
        reveal("settings.workflow", in: app).tap()
        app.buttons["configuration.keyword.WAIT"].tap()
        let displayName = app.textFields["configuration.keyword.label"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 3))
        XCTAssertEqual(displayName.value as? String, "Waiting")
        XCTAssertEqual(app.textFields["configuration.keyword.key"].value as? String, "w")
        let iconPicker = app.buttons["configuration.keyword.icon"]
        let colorPicker = app.buttons["configuration.keyword.color"]
        XCTAssertTrue([iconPicker.label, iconPicker.value as? String ?? ""].joined(separator: " ").contains("Hourglass"))
        XCTAssertTrue([colorPicker.label, colorPicker.value as? String ?? ""].joined(separator: " ").contains("Amber"))
        XCTAssertTrue(app.descendants(matching: .any)["configuration.keyword.preview"].firstMatch.exists)
        app.buttons["configuration.keyword.done"].tap()
        XCTAssertTrue(app.navigationBars["Workflow"].waitForExistence(timeout: 5))

        app.buttons["configuration.keyword.WAIT"].press(forDuration: 0.8)
        let move = app.buttons["configuration.keyword.move.WAIT"]
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        move.tap()
        XCTAssertGreaterThan(app.buttons["configuration.keyword.WAIT"].frame.minY,
                             app.buttons["configuration.keyword.DONE"].frame.minY)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["configuration.back"].tap()
        reveal("settings.workflow", in: app).tap()
        XCTAssertGreaterThan(app.buttons["configuration.keyword.WAIT"].frame.minY,
                             app.buttons["configuration.keyword.DONE"].frame.minY,
                             "Moving to Terminal must persist after reopening Workflow.")

        app.buttons["configuration.keyword.WAIT"].press(forDuration: 0.8)
        let remove = app.buttons["configuration.keyword.remove.WAIT"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertFalse(app.buttons["configuration.keyword.WAIT"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["configuration.addProcess"].tap()
        let draftKeyword = app.textFields["configuration.newKeyword"]
        XCTAssertTrue(draftKeyword.waitForExistence(timeout: 3))
        draftKeyword.tap()
        draftKeyword.typeText("DRAFT")
        let draftName = app.textFields["configuration.keyword.label"]
        draftName.tap()
        draftName.typeText("Discard this draft")
        app.buttons["configuration.cancelKeyword"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard Changes"].tap()

        app.buttons["configuration.back"].tap()
        reveal("settings.workflow", in: app).tap()
        XCTAssertFalse(app.buttons["configuration.keyword.WAIT"].exists,
                       "Removing a state must persist after reopening Workflow.")
        XCTAssertFalse(app.buttons["configuration.keyword.DRAFT"].exists,
                       "Cancel must discard the entire new-state draft.")
        screenshot("Workflow native swipe actions persisted", app: app)

        app.buttons["configuration.addProcess"].tap()
        let duplicateKeyword = app.textFields["configuration.newKeyword"]
        XCTAssertTrue(duplicateKeyword.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["configuration.keyword.done"].isEnabled)
        duplicateKeyword.tap()
        duplicateKeyword.typeText("TODO")
        app.buttons["configuration.keyword.done"].tap()
        XCTAssertTrue(app.staticTexts["That keyword already exists."].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(duplicateKeyword.exists, "Invalid input must keep the new-state editor open.")
        XCTAssertEqual(duplicateKeyword.value as? String, "TODO")
        app.buttons["configuration.cancelKeyword"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard Changes"].tap()
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
        XCTAssertFalse(app.buttons["settings.done"].exists)
        app.buttons["configuration.back"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
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

    func testFilesRemindersAndConfigAreDirectDestinations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--workflow-settings-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.buttons["configuration.back"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        reveal("settings.reminders", in: app).tap()
        XCTAssertTrue(app.switches["settings.reminders.enabled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Workspace timing"].exists)
        screenshot("Unified reminders", app: app)
        app.buttons["configuration.back"].tap()
        reveal("settings.configuration", in: app).tap()
        XCTAssertTrue(app.navigationBars["Configuration file"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["configuration.json"].exists, "JSON starts collapsed.")
        reveal("configuration.showJSON", in: app).tap()
        let before = try configurationJSON(in: app)
        // Collapse the long preview before reaching the actions above it.
        reveal("configuration.showJSON", in: app).tap()
        reveal("configuration.classicPreset", in: app).tap()
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 3))
        app.buttons["Apply"].tap()
        XCTAssertFalse(app.buttons["configuration.save"].exists)
        reveal("configuration.showJSON", in: app).tap()
        let applied = try configurationJSON(in: app)
        for field in ["files", "capture", "agenda", "logging", "reminders"] {
            XCTAssertEqual(try canonicalJSON(before[field]), try canonicalJSON(applied[field]),
                           "The classic workflow preset must preserve \(field).")
        }
        let workflow = try XCTUnwrap(applied["workflow"] as? [String: Any])
        let sequences = try XCTUnwrap(workflow["sequences"] as? [[String: Any]])
        XCTAssertTrue((sequences.first?["process"] as? [String])?.contains("NEXT") == true)
        app.buttons["configuration.back"].tap()
        reveal("settings.configuration", in: app).tap()
        reveal("configuration.showJSON", in: app).tap()
        XCTAssertEqual(try canonicalJSON(applied), try canonicalJSON(configurationJSON(in: app)),
                       "Applying a confirmed preset must persist the configuration automatically.")
        screenshot("Workflow preset preserves unrelated configuration", app: app)
    }

    func testReminderTimingPresetsCustomValuesAndInvalidDraftPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--workflow-settings-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        reveal("settings.reminders", in: app).tap()

        reveal("settings.reminders.advance.preset.30", in: app).tap()
        let advance = reveal("settings.reminders.advance.custom", in: app)
        XCTAssertEqual(advance.value as? String, "30 min")
        advance.tap()
        let input = app.textFields["settings.reminders.custom.input"]
        func replaceInput(with value: String) {
            input.tap()
            input.press(forDuration: 1.2)
            let menuItem = app.menuItems["Select All"]
            let selectAll = menuItem.waitForExistence(timeout: 1) ? menuItem : app.buttons["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 3), "The input must be selected before replacement.")
            selectAll.tap()
            input.typeText(value)
            XCTAssertEqual(input.value as? String, value)
        }
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "30")
        replaceInput(with: "37")
        let done = app.buttons["settings.reminders.custom.done"]
        XCTAssertTrue(done.isEnabled)
        done.tap()
        XCTAssertTrue(advance.waitForExistence(timeout: 3))
        XCTAssertEqual(advance.value as? String, "37 min")

        let repeatInterval = reveal("settings.reminders.repeatInterval.custom", in: app)
        XCTAssertEqual(repeatInterval.value as? String, "5 min")
        repeatInterval.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "5")
        replaceInput(with: "0")
        XCTAssertFalse(done.isEnabled, "A repeat interval of zero must not be saved.")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(repeatInterval.waitForExistence(timeout: 3))
        XCTAssertEqual(repeatInterval.value as? String, "5 min",
                       "Cancel must discard the invalid repeat-interval draft.")

        XCTAssertFalse(app.buttons["configuration.save"].exists)
        app.buttons["configuration.back"].tap()
        reveal("settings.configuration", in: app).tap()
        reveal("configuration.showJSON", in: app).tap()
        let json = app.staticTexts["configuration.json"]
        XCTAssertTrue(json.waitForExistence(timeout: 3))
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = json.label.data(using: .utf8),
                  let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reminders = configuration["reminders"] as? [String: Any] else { return false }
            return reminders["advanceMinutes"] as? Int == 37 && reminders["repeatMinutes"] as? Int == 5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed,
                       "The configuration must save the custom advance notice and retain the canceled repeat interval.")

        app.buttons["configuration.back"].tap()
        reveal("settings.reminders", in: app).tap()
        XCTAssertEqual(reveal("settings.reminders.advance.custom", in: app).value as? String, "37 min")
        XCTAssertEqual(reveal("settings.reminders.repeatInterval.custom", in: app).value as? String, "5 min")
        screenshot("Reminder timing custom value persisted", app: app)
    }

    func testChineseSettingsAndStoragePickerCopy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--workflow-settings-fixture",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", "Light"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["文件"].waitForExistence(timeout: 5))
        app.tabBars.buttons["文件"].tap()
        app.buttons["files.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.workflow"].label.contains("工作流"))
        XCTAssertTrue(app.buttons["settings.capture"].label.contains("捕获模板"))
        XCTAssertTrue(app.buttons["settings.files"].label.contains("文件与议程"))
        reveal("settings.workflow", in: app).tap()
        XCTAssertTrue(app.navigationBars["工作流"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["configuration.save"].exists)
        XCTAssertFalse(app.buttons["settings.done"].exists)
        XCTAssertFalse(app.staticTexts["Terminal"].exists)
        app.buttons["configuration.keyword.TODO"].tap()
        XCTAssertTrue(app.buttons["configuration.keyword.done"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["configuration.keyword.done"].label, "保存")
        XCTAssertFalse(app.staticTexts["Identity"].exists)
        XCTAssertFalse(app.staticTexts["Appearance"].exists)
        screenshot("Chinese state editor", app: app)
        app.buttons["configuration.cancelKeyword"].tap()
        app.buttons["configuration.back"].tap()
        reveal("settings.workspace", in: app).tap()
        reveal("workspace.chooseFolder", in: app).tap()
        XCTAssertTrue(app.navigationBars["选择存储位置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["storage.provider.iCloud"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "在设备之间保持同步")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Keep your Org files in sync across devices."].exists)
        screenshot("Chinese storage picker without removed subtitle", app: app)
        app.buttons["storage.cancel"].tap()
    }

    func testSettingsDraftSurvivesValidationAndProtectsNavigation() {
        continueAfterFailure = false
        let app = launchConfigurationFixture()
        defer { app.terminate() }
        reveal("settings.files", in: app).tap()
        let inbox = app.descendants(matching: .any)["configuration.files.inbox"].firstMatch
        revealElement(inbox, in: app)
        replaceText(in: inbox, with: "/outside.org", app: app)
        XCTAssertTrue(app.staticTexts[
            "Use a relative path inside this workspace, without .., ~, or an absolute path."
        ].firstMatch.waitForExistence(timeout: 3))
        let saveAlert = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"), object: app.alerts["Could Not Save Settings"]
        )
        saveAlert.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [saveAlert], timeout: 1), .completed,
                       "Typing invalid input must not interrupt editing with a save alert.")
        XCTAssertEqual(inbox.value as? String, "/outside.org", "Validation errors must retain the exact draft.")
        app.buttons["configuration.back"].tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 3))
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.navigationBars["Files & agenda"].exists)
        XCTAssertEqual(inbox.value as? String, "/outside.org")
        app.buttons["configuration.back"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 3))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["files.settings"].waitForExistence(timeout: 3))
        app.buttons["files.settings"].tap()
        reveal("settings.files", in: app).tap()
        revealElement(inbox, in: app)
        XCTAssertEqual(inbox.value as? String, "inbox.org", "Discard must leave the saved configuration untouched.")
        replaceText(in: inbox, with: "custom/inbox.org", app: app)
        app.buttons["configuration.back"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Valid changes must save without asking for an explicit save.")
        reveal("settings.files", in: app).tap()
        revealElement(inbox, in: app)
        XCTAssertEqual(inbox.value as? String, "custom/inbox.org", "A valid correction must persist automatically.")
        XCTAssertFalse(app.buttons["configuration.save"].exists)
        screenshot("Settings automatically saved after correcting invalid input", app: app)
    }

    func testTemplateValidationKeepsDraftAndCancelRequiresDiscard() {
        continueAfterFailure = false
        let app = launchConfigurationFixture()
        defer { app.terminate() }
        reveal("settings.capture", in: app).tap()
        reveal("configuration.template.inbox", in: app).tap()
        XCTAssertTrue(app.navigationBars["Capture template"].waitForExistence(timeout: 3))
        let name = editableField("Name", in: app)
        replaceText(in: name, with: "Reviewed capture", app: app)
        let path = editableField("File path", in: app)
        revealElement(path, in: app)
        replaceText(in: path, with: "/outside.org", app: app)
        app.buttons["configuration.template.done"].tap()
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Capture template"].exists)
        XCTAssertEqual(path.value as? String, "/outside.org")
        XCTAssertEqual(name.value as? String, "Reviewed capture")
        app.buttons["configuration.cancelTemplate"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertEqual(path.value as? String, "/outside.org")
        replaceText(in: path, with: "inbox.org", app: app)
        app.buttons["configuration.template.done"].tap()
        XCTAssertTrue(app.navigationBars["Capture templates"].waitForExistence(timeout: 5))
        let savedTemplate = app.buttons["configuration.template.inbox"]
        XCTAssertTrue(savedTemplate.label.contains("Reviewed capture"))
        savedTemplate.tap()
        let savedName = editableField("Name", in: app)
        XCTAssertEqual(savedName.value as? String, "Reviewed capture")
        replaceText(in: savedName, with: "Unsaved replacement", app: app)
        app.buttons["configuration.cancelTemplate"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard Changes"].tap()
        XCTAssertTrue(savedTemplate.waitForExistence(timeout: 3))
        XCTAssertTrue(savedTemplate.label.contains("Reviewed capture"))
        XCTAssertFalse(savedTemplate.label.contains("Unsaved replacement"))
        screenshot("Template saved after correcting validation error", app: app)
    }

    func testWorkflowKeyboardShortcutsRespectTextEditing() {
        continueAfterFailure = false
        let app = launchConfigurationFixture(extraArguments: ["--native-selection-fixture"])
        defer { app.terminate() }
        app.buttons["settings.done"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        let item = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'agenda.item.open.' AND label CONTAINS 'Project selection probe'"
        )).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let state = app.buttons["item.editor.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 3))
        app.typeKey("d", modifierFlags: [])
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'DONE'"), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 3), .completed)
        let title = app.textFields["item.editor.title"]
        title.tap()
        let previousTitle = title.value as? String ?? ""
        app.typeKey("t", modifierFlags: [])
        XCTAssertEqual(state.value as? String, "DONE", "Typing in a field must not invoke a workflow shortcut.")
        XCTAssertEqual((title.value as? String)?.count, previousTitle.count + 1)
    }

    func testReminderNativeMenuAtAccessibilitySize() {
        continueAfterFailure = false
        let app = launchConfigurationFixture(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        defer { app.terminate() }
        reveal("settings.reminders", in: app).tap()
        let presets = reveal("settings.reminders.advance.presets", in: app)
        XCTAssertTrue(presets.label.contains("Common values"))
        presets.tap()
        let thirty = app.buttons["settings.reminders.advance.preset.30"]
        XCTAssertTrue(thirty.waitForExistence(timeout: 3))
        thirty.tap()
        let custom = reveal("settings.reminders.advance.custom", in: app)
        XCTAssertEqual(custom.value as? String, "30 min")
        XCTAssertNotEqual(presets.label, custom.label, "Preset and custom controls must have distinct spoken labels.")
        screenshot("Native reminder picker at accessibility size", app: app)
    }

    func testNativePathSelectionPreservesOrderAndUnloadedPaths() throws {
        continueAfterFailure = false
        let app = launchConfigurationFixture(extraArguments: ["--native-selection-fixture"])
        defer { app.terminate() }
        reveal("settings.files", in: app).tap()
        reveal("configuration.agenda.sources", in: app).tap()
        let prefix = "configuration.agenda.sources"
        func pathRow(_ path: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: prefix + ".path." + path).firstMatch
        }
        XCTAssertTrue(pathRow("offline/planned.org").waitForExistence(timeout: 3))
        pathRow("inbox.org").tap()
        pathRow("projects/work.org").tap()
        let newPath = app.textFields[prefix + ".newPath"]
        revealElement(newPath, in: app).tap()
        newPath.typeText("later.org")
        reveal(prefix + ".addPath", in: app).tap()
        XCTAssertTrue(pathRow("later.org").waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["configuration.back"].tap()
        reveal("settings.configuration", in: app).tap()
        reveal("configuration.showJSON", in: app).tap()
        let configuration = try configurationJSON(in: app)
        let agenda = try XCTUnwrap(configuration["agenda"] as? [String: Any])
        XCTAssertEqual(agenda["sources"] as? [String], ["offline/planned.org", "inbox.org", "later.org"],
                       "Native selection must preserve retained order, unloaded paths, and newly entered paths.")
        screenshot("Native path selection persisted", app: app)
    }

    func testNativeTemplateFileSelectionSearchAndReselect() throws {
        continueAfterFailure = false
        let app = launchConfigurationFixture(extraArguments: ["--native-selection-fixture"])
        defer { app.terminate() }
        reveal("settings.capture", in: app).tap()
        reveal("configuration.template.inbox", in: app).tap()
        reveal("configuration.template.chooseFile", in: app).tap()
        let current = app.descendants(matching: .any).matching(identifier: "configuration.template.file.inbox.org").firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        current.tap()
        XCTAssertTrue(app.navigationBars["Capture template"].waitForExistence(timeout: 3),
                      "Selecting the current file should also return to the template.")
        reveal("configuration.template.chooseFile", in: app).tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("work")
        let project = app.descendants(matching: .any).matching(identifier: "configuration.template.file.projects/work.org").firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        XCTAssertFalse(current.exists, "Search should filter the file list.")
        project.tap()
        XCTAssertTrue(app.navigationBars["Capture template"].waitForExistence(timeout: 3))
        XCTAssertEqual(editableField("File path", in: app).value as? String, "projects/work.org")
        app.buttons["configuration.template.done"].tap()
        XCTAssertTrue(app.navigationBars["Capture templates"].waitForExistence(timeout: 5))
        app.buttons["configuration.back"].tap()
        reveal("settings.configuration", in: app).tap()
        reveal("configuration.showJSON", in: app).tap()
        let configuration = try configurationJSON(in: app)
        let capture = try XCTUnwrap(configuration["capture"] as? [String: Any])
        let templates = try XCTUnwrap(capture["templates"] as? [[String: Any]])
        let inbox = try XCTUnwrap(templates.first { $0["id"] as? String == "inbox" })
        let target = try XCTUnwrap(inbox["target"] as? [String: Any])
        XCTAssertEqual(target["path"] as? String, "projects/work.org")
    }

    private func launchConfigurationFixture(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--workflow-settings-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launchArguments += extraArguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Files"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        return app
    }

    private func nativeReorderHandle(for token: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.cells.containing(.button, identifier: "configuration.keyword.\(token)").firstMatch
        return row.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).firstMatch
    }

    private func reorderState(_ token: String, before target: String, in app: XCUIApplication) {
        let handle = nativeReorderHandle(for: token, in: app)
        let targetHandle = nativeReorderHandle(for: target, in: app)
        revealElement(handle, in: app)
        XCTAssertTrue(targetHandle.isHittable)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1, thenDragTo: targetHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["configuration.keyword.\(token)"].frame.minY
                < app.buttons["configuration.keyword.\(target)"].frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 3), .completed)
    }

    private func configurationJSON(in app: XCUIApplication) throws -> [String: Any] {
        let json = app.staticTexts["configuration.json"]
        XCTAssertTrue(json.waitForExistence(timeout: 3))
        let data = try XCTUnwrap(json.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonicalJSON(_ value: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: XCTUnwrap(value), options: [.sortedKeys])
    }

    private func editableField(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields[label]
        if field.exists { return field }
        let editor = app.textViews[label]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), label)
        return editor
    }

    private func replaceText(in field: XCUIElement, with replacement: String, app: XCUIApplication) {
        revealElement(field, in: app)
        field.tap()
        field.press(forDuration: 1.2)
        let menuItem = app.menuItems["Select All"]
        let selectAll = menuItem.waitForExistence(timeout: 1) ? menuItem : app.buttons["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), "Select the full value before replacing it.")
        selectAll.tap()
        field.typeText(replacement)
        XCTAssertEqual(field.value as? String, replacement)
    }

    @discardableResult
    private func revealElement(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        for _ in 0..<8 where !element.isHittable { app.swipeDown() }
        XCTAssertTrue(element.isHittable, element.debugDescription)
        return element
    }

    @discardableResult
    private func reveal(_ id: String, in app: XCUIApplication) -> XCUIElement {
        revealElement(app.buttons[id], in: app)
    }

    private func chooseAppearance(_ appearance: String, in app: XCUIApplication) {
        reveal("settings.appearance", in: app).tap()
        let option = app.buttons[appearance]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(app.buttons["settings.appearance"].label.contains(appearance))
    }

    private func appearanceRowBrightness(in app: XCUIApplication) -> CGFloat {
        // Measure rendered pixels, not the selected value: the value can
        // change while the sheet is still displaying the previous theme.
        let image = reveal("settings.appearance", in: app).screenshot().image.cgImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                    bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return CGFloat(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / (3 * 255)
    }

    private func addState(_ keyword: String, terminal: Bool, displayName: String? = nil,
                          key: String? = nil, icon: String? = nil, color: String? = nil,
                          app: XCUIApplication) {
        reveal(terminal ? "configuration.addTerminal" : "configuration.addProcess", in: app).tap()
        let field = app.textFields["configuration.newKeyword"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        for (picker, choice) in [("icon", icon), ("color", color)] {
            if let choice {
                reveal("configuration.keyword.\(picker)", in: app).tap()
                let option = app.descendants(matching: .any)["configuration.keyword.\(picker).\(choice)"].firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 3))
                option.tap()
                if !field.waitForExistence(timeout: 1) {
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
                XCTAssertTrue(field.waitForExistence(timeout: 3))
            }
        }
        field.tap()
        field.typeText(keyword)
        if let displayName {
            let nameField = app.textFields["configuration.keyword.label"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 3))
            nameField.tap()
            nameField.typeText(displayName)
        }
        if let key {
            let keyField = app.textFields["configuration.keyword.key"]
            XCTAssertTrue(keyField.waitForExistence(timeout: 3))
            keyField.tap()
            keyField.typeText(key)
        }
        app.buttons["configuration.keyword.done"].tap()
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
