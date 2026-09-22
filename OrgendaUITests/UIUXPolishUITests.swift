import XCTest

final class UIUXPolishUITests: XCTestCase {
    /// An explicit visual audit, intentionally compatible with both the original
    /// UI and the polished UI so its screenshots can be compared side by side.
    func testCaptureAuditFlow() {
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["agenda.viewMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Plan iPad reading workflow"].waitForExistence(timeout: 5))
        attach(app, name: "01 Dashboard", always: true)

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["orgenda.calendar.density"].waitForExistence(timeout: 3))
        attach(app, name: "02 Calendar week", always: true)
        app.buttons["orgenda.calendar.density"].tap()
        app.buttons["Month"].tap()
        attach(app, name: "03 Calendar month", always: true)

        app.buttons["orgenda.capture"].tap()
        XCTAssertTrue(app.textFields["item.editor.title"].waitForExistence(timeout: 3))
        // A fresh simulator can display the system typing introduction over the
        // focused title field. Capture the usable form with its actual keyboard.
        let typingIntroduction = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Speed up your typing'"
        )).firstMatch
        if typingIntroduction.exists {
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        attach(app, name: "04 New task", always: true)
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.buttons["files.open.inbox.org"].waitForExistence(timeout: 3))
        attach(app, name: "05 Files", always: true)
        app.buttons["files.open.inbox.org"].tap()
        XCTAssertTrue(app.buttons["org.document.outline"].waitForExistence(timeout: 3))
        attach(app, name: "06 Document preview", always: true)

        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        attach(app, name: "07 Source editor keyboard", always: true)
        app.buttons["Preview"].tap()
        app.buttons["org.document.outline"].tap()
        XCTAssertTrue(app.buttons["org.document.outline.done"].waitForExistence(timeout: 3))
        attach(app, name: "08 Document outline", always: true)
        app.buttons["org.document.outline.done"].tap()

        app.navigationBars.buttons["Files"].tap()
        app.buttons["files.settings"].tap()
        XCTAssertTrue(app.buttons["settings.workspace"].waitForExistence(timeout: 3))
        attach(app, name: "09 Settings", always: true)
        app.buttons["settings.done"].tap()

        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 3))
        attach(app, name: "10 Search", always: true)
    }

    func testEditorAccessoryUndoRedoAndDismissKeyboard() throws {
        let app = launchApp()
        defer { app.terminate() }
        openInbox(in: app)
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let original = try XCTUnwrap(editor.value as? String)

        for identifier in ["heading", "checkbox", "indent", "date", "dismissKeyboard"] {
            let control = app.buttons["org.editor.\(identifier)"]
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            XCTAssertTrue(control.isHittable, "\(identifier) must remain reachable above the keyboard")
        }

        let heading = app.buttons["org.editor.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        heading.tap()
        let changed = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(changed, original, "The heading command must create an undoable source edit")


        let undo = app.buttons["org.editor.undo"]
        XCTAssertTrue(undo.isEnabled)
        XCTAssertTrue(undo.isHittable)
        undo.tap()
        assertValue(original, of: editor)

        let redo = app.buttons["org.editor.redo"]
        XCTAssertTrue(redo.waitForExistence(timeout: 3))
        XCTAssertTrue(redo.isEnabled)
        XCTAssertTrue(redo.isHittable)
        redo.tap()
        assertValue(changed, of: editor)
        attach(app, name: "Editor redo restores heading")

        let dismiss = app.buttons["org.editor.dismissKeyboard"]
        XCTAssertTrue(dismiss.isHittable)
        dismiss.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Files"].isHittable)
        XCTAssertEqual(editor.value as? String, changed, "Dismissing the keyboard must preserve the source")
        attach(app, name: "Editor keyboard dismissed")
    }

    func testOutlineEmptyFilterCanBeClearedInPlace() {
        let app = launchApp()
        defer { app.terminate() }
        openInbox(in: app)
        app.buttons["org.document.outline"].tap()
        let roadmap = outlineHeading("Review quarterly roadmap", in: app)
        let workflow = outlineHeading("Plan iPad reading workflow", in: app)
        XCTAssertTrue(roadmap.waitForExistence(timeout: 3))
        XCTAssertTrue(workflow.exists)

        app.buttons["org.document.outline.filter"].tap()
        let waiting = app.buttons["org.outline.filter.state.WAIT"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 3))
        waiting.tap()
        app.buttons["org.outline.filter.done"].tap()
        // The filtered empty state is installed before the nested sheet finishes
        // dismissing. Wait until the underlying outline can receive interaction.
        XCTAssertTrue(app.navigationBars["Filter Outline"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No matching headings"].waitForExistence(timeout: 3))
        XCTAssertFalse(roadmap.exists)
        let clear = app.buttons["org.outline.filter.clear"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: clear)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed,
                       "The Clear action must become hittable after the filter sheet closes")
        XCTAssertTrue(clear.isHittable, "A zero-result filter must offer recovery in the empty state")
        attach(app, name: "Outline empty filter recovery")

        clear.tap()
        XCTAssertTrue(roadmap.waitForExistence(timeout: 3))
        XCTAssertTrue(workflow.exists)
        XCTAssertFalse(app.staticTexts["No matching headings"].exists)
        // Native toolbar buttons may omit accessibilityValue in XCTest's
        // snapshot. Verify the actual restored list and cleared-filter controls.
        XCTAssertFalse(app.buttons["org.outline.filter.clear"].exists)
        XCTAssertFalse(app.otherElements["org.outline.filter.summary"].exists)
    }

    func testReplacingSearchQueryAndChangingScopeShowsCurrentResults() {
        let app = launchApp()
        defer { app.terminate() }
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Appearance")
        let appearance = app.buttons["search.setting.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))

        // Send deletion and replacement as one typing action without waiting for
        // intermediate searches. Only the eventual current query is asserted.
        replaceSearchText("Appearance", with: "workflow", in: search)
        let inbox = app.buttons["search.document.inbox.org"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "workflow")
        XCTAssertTrue(appearance.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No results"].exists)

        replaceSearchText("workflow", with: "Appearance", in: search)
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue(inbox.waitForNonExistence(timeout: 3))
        app.buttons["search.scope.menu"].tap()
        // SwiftUI's native Picker menu exports the option title but omits the
        // child accessibility identifier; the active search has no Files tab.
        let filesScope = app.buttons["Files"]
        XCTAssertTrue(filesScope.waitForExistence(timeout: 3))
        filesScope.tap()
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["search.scope.menu"].value as? String, "Files")
        XCTAssertFalse(appearance.exists)
        let expandScope = app.buttons["search.expandScope"]
        XCTAssertTrue(expandScope.isHittable)
        expandScope.tap()
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Appearance")
        XCTAssertEqual(app.buttons["search.scope.menu"].value as? String, "All categories")
        XCTAssertFalse(app.staticTexts["No results"].exists)
        attach(app, name: "Search results after query and scope changes")
    }

    func testPreviewHeadingActionsPreserveEachOther() {
        let app = launchApp()
        defer { app.terminate() }
        openInbox(in: app)
        let disclosure = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.preview.heading.disclosure.'"
        )).firstMatch
        let state = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.preview.todo.'"
        )).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(state.waitForExistence(timeout: 3))

        let initialExpansion = disclosure.value as? String
        let initialState = state.value as? String
        disclosure.tap()
        XCTAssertNotEqual(disclosure.value as? String, initialExpansion)
        XCTAssertEqual(state.value as? String, initialState, "Collapsing a heading must not change its status")
        let changedExpansion = disclosure.value as? String
        state.tap()
        XCTAssertNotEqual(state.value as? String, initialState)
        XCTAssertEqual(disclosure.value as? String, changedExpansion, "Changing status must not toggle collapse")
        attach(app, name: "Compact preview heading actions")
    }

    func testCustomBlockPreviewPreservesContentAndCheckboxEditing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--file-browser-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        defer { app.terminate() }
        openInbox(in: app)
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.9)).tap()
        editor.typeText("\n\n#+begin_note\nA *custom block* with a pale background.\n#+begin_tip\nNested content stays readable.\n#+end_tip\n- [ ] Keep custom checklist\n\n#+end_note\n")
        let source = editor.value as? String ?? ""
        XCTAssertTrue(source.contains("#+begin_note"))
        XCTAssertTrue(source.contains("#+end_note"))
        app.buttons["Preview"].tap()
        let outerBlocks = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.preview.custom-block.'"))
        XCTAssertTrue(outerBlocks.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["A custom block with a pale background."].exists)
        XCTAssertTrue(app.staticTexts["Nested content stays readable."].exists)
        let checkbox = app.buttons["Mark Keep custom checklist complete"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 3))
        attach(app, name: "Custom blocks with pale gray background", always: true)
        checkbox.tap()
        let checked = app.buttons["Mark Keep custom checklist incomplete"]
        XCTAssertTrue(checked.waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String,
                       source.replacingOccurrences(of: "[ ] Keep custom checklist", with: "[X] Keep custom checklist"))
    }

    func testPreviewRendersNewlineDelimitedMathEnvironments() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--file-browser-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        defer { app.terminate() }
        openInbox(in: app)
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.9)).tap()
        let source = #"""

        * Bracket formula
        \[
        \alpha
        \]

        * Aligned environment
        \begin{aligned}
        \alpha
        \end{aligned}
        """# + "\n"
        editor.typeText(source)
        XCTAssertTrue((editor.value as? String)?.contains(source) == true)
        app.buttons["Preview"].tap()
        let bracket = app.images.matching(NSPredicate(format: "label == %@", "\\[\n\\alpha\n\\]")).firstMatch
        let aligned = app.images.matching(NSPredicate(format: "label == %@", "\\begin{aligned}\n\\alpha\n\\end{aligned}")).firstMatch
        XCTAssertTrue(bracket.waitForExistence(timeout: 3), "Bracket math should appear as a rendered image")
        XCTAssertTrue(aligned.waitForExistence(timeout: 3), "Aligned math should appear as a rendered image")
        XCTAssertTrue(bracket.isHittable)
        XCTAssertTrue(aligned.isHittable)
        XCTAssertFalse(app.staticTexts["\\alpha"].exists)
        attach(app, name: "Rendered newline delimited math environments", always: true)
    }

    func testPreviewRendersFullSubtypeParagraphWithoutRawDelimiters() throws {
        let source = #"""
        * Full F
        将全称量词看作是“函数”后，类型 \( T = \forall X \mathrel{\raisebox{0.1ex}{\scriptsize$<$}}\!\colon T_1. T_2\) 可以看作是一个“将 \( T_1 \) 的 subtypes 映射到类型为 \( T_2 \) 的 terms 上”的函数。令 \( S = \forall X <: S1. S2\)，其中 \( T_1 <: S_1 \)，也就是说 \( \operatorname{dom}(T) \subseteq \operatorname{dom}(S) \)。
        """# + "\n"
        let app = openRenderedMathFixture(source)
        defer { app.terminate() }
        let preview = app.scrollViews["org.preview.scroll"]
        XCTAssertTrue(preview.staticTexts["Full F"].waitForExistence(timeout: 3))
        XCTAssertTrue(preview.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "subtypes")).firstMatch.exists)
        for command in [#"\("#, #"\)"#, #"\forall"#, #"\mathrel"#] {
            XCTAssertFalse(preview.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", command)).firstMatch.exists, command)
        }
        attach(app, name: "Subtype paragraph rendered in Preview", always: true)
    }

    func testPreviewRendersFiveRowErasureDefinition() throws {
        let formula = #"""
        \begin{aligned}

        & \operatorname{erase}(x) &&= x \\

        & \operatorname{erase}(\lambda x : T_1 . t_2) &&= \lambda x. \operatorname{erase}(t_2) \\

        & \operatorname{erase}(t_1\ t_2) &&= \operatorname{erase}(t_1)\ \operatorname{erase}(t_2) \\

        & \operatorname{erase}(\lambda X. t_2) &&= \operatorname{erase}(t_2) \\

        & \operatorname{erase}(t_1\ [T_2]) &&= \operatorname{erase}(t_1) \\
        \end{aligned}
        """#
        let source = "* Erasure\n#+begin_definition\n*(erasure)*\nThe erasure of a term \\(t\\) in System F is defined as follows:\n"
            + formula + "\n#+end_definition\nAfter the definition.\n"
        let app = openRenderedMathFixture(source)
        defer { app.terminate() }
        let image = app.images.matching(NSPredicate(format: "label == %@", formula)).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 3), "The full definition equation should render as one image")
        XCTAssertGreaterThan(image.frame.height, 80)
        let preview = app.scrollViews["org.preview.scroll"]
        XCTAssertTrue(preview.staticTexts["definition"].exists)
        XCTAssertTrue(preview.staticTexts["After the definition."].exists)
        XCTAssertFalse(preview.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", #"\begin{aligned}"#)).firstMatch.exists)
        attach(app, name: "Five row erasure definition rendered in Preview", always: true)
    }

    private func openRenderedMathFixture(_ source: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--file-browser-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        openInbox(in: app)
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.9)).tap()
        editor.typeText("\n" + source)
        XCTAssertTrue((editor.value as? String)?.contains(source) == true)
        app.buttons["Preview"].tap()
        return app
    }

    func testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-workspace", "--image-preview-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.open.notes"].tap()
        app.buttons["files.open.notes/note.org"].tap()
        let relative = app.buttons["Relative picture"]
        XCTAssertTrue(relative.waitForExistence(timeout: 5))
        let attachment = app.buttons["Attached picture"]
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        attach(app, name: "Relative and ID attachment images in Preview", always: true)

        relative.tap()
        let zoom = app.scrollViews["org.preview.image.zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 3))
        let image = app.images["Relative picture"]
        XCTAssertTrue(image.exists)
        let width = image.frame.width
        zoom.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(image.frame.width, width)
        app.buttons["org.preview.image.close"].tap()
        XCTAssertTrue(relative.waitForExistence(timeout: 3))

        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.image.retry.'")).firstMatch
        let preview = app.scrollViews["org.preview.scroll"]
        if !retry.isHittable { preview.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The image could not be found at this path."].exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["The image could not be found at this path."].waitForExistence(timeout: 3))
        attach(app, name: "Missing image has a retry action", always: true)

        let headingImage = app.buttons["Heading picture"]
        for _ in 0..<3 where !headingImage.isHittable { preview.swipeUp() }
        XCTAssertTrue(headingImage.isHittable)
        headingImage.tap()
        XCTAssertTrue(app.scrollViews["org.preview.image.zoom"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.images["Heading picture"].exists)
        app.buttons["org.preview.image.close"].tap()
    }

    private func openInbox(in app: XCUIApplication) {
        app.tabBars.buttons["Files"].tap()
        let inbox = app.buttons["files.open.inbox.org"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        inbox.tap()
        XCTAssertTrue(app.buttons["org.document.outline"].waitForExistence(timeout: 3))
    }

    private func outlineHeading(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.document.outline.heading.' AND label == %@", title
        )).firstMatch
    }

    private func replaceSearchText(_ previous: String, with replacement: String, in field: XCUIElement) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + replacement)
    }

    private func assertValue(_ value: String, of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-workspace", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "-appearance", "Light"
        ]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String, always: Bool = false) {
        let environment = ProcessInfo.processInfo.environment
        guard always || environment["ORGENDA_CAPTURE_AUDIT"] == "1"
            || environment["TEST_RUNNER_ORGENDA_CAPTURE_AUDIT"] == "1" else { return }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
