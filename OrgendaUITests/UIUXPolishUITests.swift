import XCTest

final class UIUXPolishUITests: XCTestCase {
    func testSystemTitleMenuChangesPerspectiveAndPreservesSelection() {
        let app = launchApp()
        let title = app.navigationBars.buttons["Unscheduled"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        let overdue = app.buttons.matching(NSPredicate(format: "label == 'Overdue' AND identifier == ''")).firstMatch
        XCTAssertTrue(overdue.waitForExistence(timeout: 3))
        overdue.tap()
        XCTAssertTrue(app.navigationBars.buttons["Overdue"].waitForExistence(timeout: 3))
        app.selectRootTab("Calendar")
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        app.selectRootTab("Dashboard")
        XCTAssertTrue(app.navigationBars.buttons["Overdue"].waitForExistence(timeout: 3))
        attachScreenshot("System perspective title menu", screenshot: app.screenshot())
    }

    func testSystemSearchEmptyStateRecoversWithKeyboard() {
        verifySearchEmptyState()
    }

    func testSystemSearchEmptyStateAtAccessibilitySize() {
        verifySearchEmptyState(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    private func verifySearchEmptyState(arguments: [String] = []) {
        let app = launchTestApp(arguments + ["--empty-workspace-fixture"])
        app.selectRootTab("Search")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Start a search"].waitForExistence(timeout: 3))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        attachScreenshot("System search guidance with keyboard", screenshot: app.screenshot())
        app.buttons["search.scope.menu"].tap()
        app.buttons["Tasks"].tap()
        search.tap()
        search.typeText("no-matching-entry")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 3))
        let clear = app.buttons["Clear Search"]
        for _ in 0..<5 {
            if clear.isHittable { break }
            scrollSearchContentUp(in: app)
        }
        XCTAssertTrue(clear.isHittable)
        attachScreenshot("System search empty results and recovery", screenshot: app.screenshot())
        clear.tap()
        XCTAssertTrue(app.staticTexts["Start a search"].waitForExistence(timeout: 3))
        search.tap()
        search.typeText("no-matching-entry")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 3))
        let expand = app.buttons["search.expandScope"]
        for _ in 0..<5 {
            if expand.isHittable { break }
            scrollSearchContentUp(in: app)
        }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        assertValue("All categories", of: app.buttons["search.scope.menu"])
        XCTAssertEqual(search.value as? String, "no-matching-entry")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 3))
    }

    private func scrollSearchContentUp(in app: XCUIApplication) {
        let surface = app.scrollSurface("search.empty").frame
        // XCTest's default swipe can start behind the software keyboard. Keep
        // the gesture inside the visible content between the scope and field.
        let top = max(surface.minY, app.buttons["search.scope.menu"].frame.maxY) + 12
        let bottom = min(surface.maxY, app.searchFields.firstMatch.frame.minY,
                         app.keyboards.firstMatch.frame.minY) - 12
        XCTAssertGreaterThan(bottom, top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: surface.midX, dy: bottom))
        let end = origin.withOffset(CGVector(dx: surface.midX, dy: top))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testWeekPagerMovesOneWeekAndReturnsToday() {
        verifyWeekPager()
    }

    func testWeekPagerAtAccessibilitySize() {
        verifyWeekPager(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    private func verifyWeekPager(arguments: [String] = []) {
        let app = launchTestApp(arguments)
        app.selectRootTab("Calendar")
        let weeks = app.scrollViews["orgenda.calendar.weeks"]
        XCTAssertTrue(weeks.waitForExistence(timeout: 3))
        let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        let nextWeek = Calendar.autoupdatingCurrent.date(byAdding: .weekOfYear, value: 1, to: today)!
        func page(by distance: CGFloat) {
            let start = weeks.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .fast, thenHoldForDuration: 0.05)
        }
        page(by: -160)
        assertValue(nextWeek.formatted(date: .complete, time: .omitted), of: weeks)
        let selected = weeks.buttons.matching(NSPredicate(format: "selected == true")).firstMatch
        XCTAssertEqual(selected.label, nextWeek.formatted(date: .complete, time: .omitted))
        page(by: 160)
        assertValue(today.formatted(date: .complete, time: .omitted), of: weeks)
        page(by: -160)
        app.buttons["orgenda.calendar.today"].tap()
        assertValue(today.formatted(date: .complete, time: .omitted), of: weeks)
        XCTAssertTrue(app.buttons["orgenda.calendar.today"].waitForNonExistence(timeout: 3))
        attachScreenshot("System week pager", screenshot: app.screenshot())
    }

    func testSystemEditorLabelsSaveTagsAndKeepSourceVisible() {
        verifyEditorLabels()
    }

    func testSystemEditorLabelsAtAccessibilitySize() {
        verifyEditorLabels(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    private func verifyEditorLabels(arguments: [String] = []) {
        let app = launchTestApp(arguments + ["--file-browser-fixture"])
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'agenda.item.open.'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let form = app.scrollSurface("item.editor.form")
        let tags = app.descendants(matching: .any).matching(identifier: "item.editor.tags").firstMatch
        for _ in 0..<6 {
            if tags.isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(tags.isHittable)
        let previous = tags.value as? String ?? ""
        let replacement = "focus, project_name_with_many_characters, review, planning, longterm"
        tags.tap()
        tags.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + replacement)
        XCTAssertEqual(tags.value as? String, replacement)
        attachScreenshot("System multiline tags while editing", screenshot: app.screenshot())
        app.buttons["item.editor.save"].tap()
        XCTAssertTrue(app.buttons["item.editor.save"].waitForNonExistence(timeout: 3))
        item.tap()
        for _ in 0..<6 {
            if tags.isHittable { break }
            form.swipeUp()
        }
        XCTAssertEqual(tags.value as? String, replacement)
        let file = app.descendants(matching: .any).matching(identifier: "item.editor.sourceFile").firstMatch
        for _ in 0..<10 {
            if file.isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(file.isHittable)
        XCTAssertTrue((file.label + String(describing: file.value)).contains("inbox.org"))
        attachScreenshot("System editor labels", screenshot: app.screenshot())
    }

    func testEditorAccessoryUndoRedoAndDismissKeyboard() throws {
        let app = launchApp()
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
        openInbox(in: app)
        app.buttons["org.document.outline"].tap()
        let roadmap = outlineHeading("Review quarterly roadmap", in: app)
        let workflow = outlineHeading("Plan iPad reading workflow", in: app)
        XCTAssertTrue(roadmap.waitForExistence(timeout: 3))
        XCTAssertTrue(workflow.exists)

        app.buttons["org.document.outline.filter"].tap()
        let waiting = app.switches["org.outline.filter.state.WAIT"]
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
        app.selectRootTab("Search")
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

    func testCustomBlockPreviewPreservesContentAndCheckboxEditing() {
        let app = launchTestApp(["--file-browser-fixture"], workspace: "--ui-test-workspace", appearance: "Light")
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
        let app = launchTestApp(["--file-browser-fixture"], workspace: "--ui-test-workspace", appearance: "Light")
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


    func testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom() {
        let app = launchTestApp(["--image-preview-fixture"], workspace: "--ui-test-workspace", appearance: "Light")
        app.selectRootTab("Files")
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
        app.selectRootTab("Files")
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
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, "Expected \(value); got \(String(describing: element.value))", file: file, line: line)
    }

    private func launchApp() -> XCUIApplication {
        let app = launchTestApp(workspace: "--ui-test-workspace", appearance: "Light")
        return app
    }

    private func attach(_ app: XCUIApplication, name: String, always: Bool = false) {
        let environment = ProcessInfo.processInfo.environment
        guard always || environment["ORGENDA_CAPTURE_AUDIT"] == "1"
            || environment["TEST_RUNNER_ORGENDA_CAPTURE_AUDIT"] == "1" else { return }
        attachScreenshot(name, screenshot: app.screenshot())
    }
}
