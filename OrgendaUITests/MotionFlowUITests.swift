import XCTest

final class MotionFlowUITests: XCTestCase {
    func testPlainBirthdayOffersInlineCompletionAndUndo() {
        let app = gestureApp()
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.open.calendar.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.9)).tap()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd EEE"
        let title = "QA Birthday completion"
        editor.typeText("\n* \(title)\n<\(formatter.string(from: .now)) +1y>\n")
        let source = editor.value as? String
        app.buttons["Preview"].tap()
        app.tabBars.buttons["Calendar"].tap()
        let complete = app.buttons.matching(NSPredicate(format: "label == 'Complete this occurrence' AND value == %@", title)).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        if !complete.isHittable { app.scrollViews["orgenda.agenda.timeline"].swipeUp() }
        XCTAssertTrue(complete.isHittable)
        complete.tap()
        let undo = app.buttons["agenda.gesture.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Occurrence completed"].exists)
        XCTAssertFalse(app.textFields["item.editor.title"].exists)
        XCTAssertFalse(complete.isHittable)
        undo.tap()
        XCTAssertTrue(complete.isHittable)
        app.buttons[title].press(forDuration: 1)
        app.buttons["agenda.item.completeOccurrence"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        app.tabBars.buttons["Files"].tap()
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, source)
    }

    func testFileBrowserFolderDragMovesSubtreeAndPickerMovesItBack() {
        let app = fileGestureApp()
        let projects = app.buttons["files.open.projects"]
        let destination = app.buttons["files.open.destination"]
        XCTAssertTrue(projects.waitForExistence(timeout: 3))
        projects.press(forDuration: 0.7, thenDragTo: destination)
        XCTAssertTrue(app.buttons["files.action.undo"].waitForExistence(timeout: 4))
        XCTAssertFalse(projects.exists)
        destination.tap()
        let nested = app.buttons["files.open.destination/projects"]
        XCTAssertTrue(nested.waitForExistence(timeout: 3))
        nested.tap()
        app.buttons["files.open.destination/projects/child"].tap()
        app.buttons["files.open.destination/projects/child/notes.org"].tap()
        XCTAssertTrue(app.staticTexts["Nested content 中文"].waitForExistence(timeout: 3))
        edgeBack(in: app)
        edgeBack(in: app)
        edgeBack(in: app)
        XCTAssertTrue(nested.waitForExistence(timeout: 3))
        horizontalDrag(in: app, y: nested.frame.midY, from: 0.84, to: 0.22)
        app.buttons["files.swipe.move"].tap()
        app.buttons["files.move.destination.root"].tap()
        XCTAssertTrue(nested.waitForNonExistence(timeout: 4))
        edgeBack(in: app)
        XCTAssertTrue(projects.waitForExistence(timeout: 3))
    }

    func testFileBrowserSwipeDeleteCancelUndoAndRecentlyDeletedRestore() {
        let app = fileGestureApp()
        let projects = app.buttons["files.open.projects"]
        XCTAssertTrue(projects.waitForExistence(timeout: 3))
        horizontalDrag(in: app, y: projects.frame.midY, from: 0.84, to: 0.22)
        let delete = app.buttons["files.swipe.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(projects.exists)
        delete.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(projects.waitForNonExistence(timeout: 4))
        let undo = app.buttons["files.action.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(projects.waitForExistence(timeout: 3))
        horizontalDrag(in: app, y: projects.frame.midY, from: 0.84, to: 0.22)
        delete.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(projects.waitForNonExistence(timeout: 3))
        app.buttons["files.recentlyDeleted"].tap()
        let restore = app.buttons["files.restore.projects"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 3))
        app.buttons["Done"].tap()
        projects.tap()
        app.buttons["files.open.projects/child"].tap()
        app.buttons["files.open.projects/child/notes.org"].tap()
        XCTAssertTrue(app.staticTexts["Nested content 中文"].waitForExistence(timeout: 3))
    }

    func testFileBrowserMovePickerAndCancelledDrag() {
        let app = fileGestureApp()
        let inbox = app.buttons["files.open.inbox.org"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        inbox.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        XCTAssertTrue(inbox.exists)
        XCTAssertFalse(app.buttons["files.action.undo"].exists)
        horizontalDrag(in: app, y: inbox.frame.midY, from: 0.84, to: 0.22)
        app.buttons["files.swipe.move"].tap()
        app.buttons["files.move.destination.projects/child"].tap()
        XCTAssertTrue(app.buttons["files.action.undo"].waitForExistence(timeout: 4))
        XCTAssertFalse(inbox.exists)
        app.buttons["files.action.undo"].tap()
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        inbox.tap()
        XCTAssertTrue(app.staticTexts["File gesture probe"].waitForExistence(timeout: 3))
    }

    private func fileGestureApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "--file-browser-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        return app
    }

    func testAgendaShowInFilePreservesSourceAndFolderNavigation() {
        let app = fileGestureApp()
        app.buttons["files.open.projects"].tap()
        app.buttons["files.open.projects/child"].tap()
        app.buttons["files.open.projects/child/notes.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.95)).tap()
        let target = "文件定位测试🙂"
        editor.typeText("\n" + String(repeating: "中文\n", count: 12)
                        + "\n* TODO \(target)\n" + String(repeating: "正文\n", count: 35))
        let source = editor.value as? String
        app.buttons["Preview"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        chooseAgendaView("TODOs", in: app)
        let row = app.staticTexts[target]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.press(forDuration: 0.6)
        let showInFile = app.buttons["agenda.item.showInFile"]
        XCTAssertTrue(showInFile.waitForExistence(timeout: 2))
        showInFile.tap()

        XCTAssertTrue(app.tabBars.buttons["Files"].isSelected)
        let preview = app.scrollViews["org.preview.scroll"]
        let heading = preview.staticTexts[target]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        XCTAssertTrue(heading.isHittable)
        XCTAssertTrue(app.staticTexts["projects/child/notes.org"].exists)
        XCTAssertTrue(app.buttons["Preview"].isSelected)
        app.buttons["Edit"].tap()
        XCTAssertEqual(app.textViews["Org source editor"].value as? String, source)
        app.buttons["Preview"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.buttons["agenda.viewMenu"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["agenda.viewMenu"].value as? String, "Unscheduled")
        XCTAssertTrue(row.isHittable)
        app.tabBars.buttons["Files"].tap()
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Child"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["files.open.projects/child/notes.org"].isHittable)
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["files.open.projects/child"].isHittable)
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
    }

    func testAgendaAllDayEventCanShowItsFile() {
        let app = gestureApp()
        let event = app.buttons["Weekend review"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        event.press(forDuration: 1)
        let showInFile = app.buttons["agenda.item.showInFile"]
        XCTAssertTrue(showInFile.waitForExistence(timeout: 2))
        showInFile.tap()
        XCTAssertTrue(app.tabBars.buttons["Files"].isSelected)
        let previewEvent = app.scrollViews["org.preview.scroll"].staticTexts["Weekend review"]
        XCTAssertTrue(previewEvent.waitForExistence(timeout: 3))
        XCTAssertTrue(previewEvent.isHittable)
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["agenda.viewMenu"].exists)
    }

    func testGestureEdgeBackInPreviewEditorFolderAndSettings() {
        let app = gestureApp()
        app.tabBars.buttons["Files"].tap()
        let inbox = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch
        inbox.tap()
        XCTAssertTrue(app.buttons["org.document.outline"].waitForExistence(timeout: 3))
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
        inbox.tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.tap()
        editor.typeText("Gesture persistence 中文 ")
        let edited = editor.value as? String
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
        inbox.tap()
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, edited)
        edgeBack(in: app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Projects,'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 3))
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
        app.buttons["files.settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance,'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testGestureEdgeBackCanBeCancelled() {
        let app = gestureApp()
        app.tabBars.buttons["Files"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(app.buttons["org.document.outline"].isHittable)
        XCTAssertTrue(app.staticTexts["Review quarterly roadmap"].isHittable)
        edgeBack(in: app)
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
    }

    func testGestureTaskSwipesCompleteRescheduleAndUndo() {
        let app = gestureApp()
        let title = app.staticTexts["Review quarterly roadmap"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        horizontalDrag(in: app, y: title.frame.midY, from: 0.24, to: 0.87)
        let undo = app.buttons["agenda.gesture.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Mark incomplete' AND value == 'Review quarterly roadmap'")).firstMatch.exists)
        undo.tap()
        horizontalDrag(in: app, y: title.frame.midY, from: 0.86, to: 0.23)
        let reschedule = app.buttons["agenda.swipe.reschedule"]
        XCTAssertTrue(reschedule.waitForExistence(timeout: 3))
        reschedule.tap()
        app.buttons["agenda.reschedule.tomorrow"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        let y = title.frame.minY
        app.scrollViews["orgenda.agenda.timeline"].swipeUp()
        XCTAssertTrue(!title.isHittable || abs(title.frame.minY - y) > 30)
    }

    func testGestureCalendarDropAndCancelledDrop() {
        let app = gestureApp()
        let title = app.staticTexts["Review quarterly roadmap"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        XCTAssertFalse(app.buttons["agenda.gesture.undo"].exists)
        let calendar = Calendar.autoupdatingCurrent
        let target = calendar.date(byAdding: .day, value: calendar.component(.weekday, from: .now) == 7 ? -1 : 1, to: .now)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day = app.buttons["orgenda.calendar.day.\(formatter.string(from: target))"]
        XCTAssertTrue(day.isHittable)
        title.press(forDuration: 0.7, thenDragTo: day)
        let undo = app.buttons["agenda.gesture.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4))
        undo.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
    }

    func testOutlineFilterNarrowsHeadingsByStateAndRestores() {
        let app = gestureApp()
        app.tabBars.buttons["Files"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch.tap()
        app.buttons["org.document.outline"].tap()

        let todo = outlineHeading("Review quarterly roadmap", in: app)
        let project = outlineHeading("Write tree-sitter Org queries", in: app)
        XCTAssertTrue(todo.waitForExistence(timeout: 3))
        XCTAssertTrue(project.exists)

        app.buttons["org.document.outline.filter"].tap()
        XCTAssertTrue(app.navigationBars["Filter Outline"].waitForExistence(timeout: 3))
        app.buttons["org.outline.filter.state.TODO"].tap()
        app.buttons["org.outline.filter.done"].tap()
        XCTAssertTrue(app.navigationBars["Filter Outline"].waitForNonExistence(timeout: 3))

        XCTAssertTrue(todo.waitForExistence(timeout: 3))
        XCTAssertTrue(project.waitForNonExistence(timeout: 3))

        app.buttons["org.outline.filter.clear"].tap()
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        app.buttons["org.document.outline.done"].tap()
    }

    private func outlineHeading(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.document.outline.heading.' AND label == %@",
            title
        )).firstMatch
    }

    private func gestureApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        return app
    }

    private func edgeBack(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)))
    }

    private func horizontalDrag(in app: XCUIApplication, y: CGFloat, from: CGFloat, to: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: app.frame.width * from, dy: y))
            .press(forDuration: 0.02, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * to, dy: y)))
    }

    func testPlanningPreviewCanToggleRawTimestamp() {
        let app = gestureApp()
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.open.inbox.org"].tap()
        let planning = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.preview.planning.entry.'"
        )).firstMatch
        XCTAssertTrue(planning.waitForExistence(timeout: 3))
        XCTAssertFalse((planning.value as? String)?.contains("<") == true)
        planning.press(forDuration: 1)
        app.buttons["Show Org timestamp"].tap()
        XCTAssertTrue((planning.value as? String)?.contains("SCHEDULED: <") == true)
        planning.press(forDuration: 1)
        app.buttons["Show readable date"].tap()
        XCTAssertFalse((planning.value as? String)?.contains("<") == true)
    }

    func testDocumentModesPreserveCollapseAndShareUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch.tap()
        XCTAssertFalse(app.staticTexts["org.document.saveStatus"].exists)
        XCTAssertFalse(app.buttons["org.document.undo"].exists)
        XCTAssertFalse(app.buttons["org.document.redo"].exists)
        let disclosure = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.heading.disclosure.'")).firstMatch
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        app.buttons["Edit"].tap()
        let source = app.textViews["Org source editor"].value as? String
        app.buttons["Preview"].tap()
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        disclosure.tap()
        let todo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.todo.'")).firstMatch
        todo.tap()
        XCTAssertEqual(todo.value as? String, "NEXT")
        app.buttons["Edit"].tap()
        app.textViews["Org source editor"].tap()
        let undo = app.buttons["org.editor.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertEqual(app.textViews["Org source editor"].value as? String, source)
        app.buttons["Preview"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'TODO'"), object: todo)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 3), .completed)
    }

    func testOutlineDragNestsMovesOutAndUpdatesPreviewSourceAndUndo() throws {
        let app = outlineDragApp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Files'")).firstMatch.tap()
        app.buttons["files.open.journal/2026.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        let a = "* TODO Outline Alpha\nAlpha body\n** Alpha child\nNested body\n"
        let b = "* TODO Outline Beta\nBeta body\n"
        let c = "* Outline Gamma\nGamma body\n"
        let nestedA = "** TODO Outline Alpha\nAlpha body\n*** Alpha child\nNested body\n"
        editor.typeText("\n" + a + b + c)
        let original = try XCTUnwrap(editor.value as? String)
        let inserted = try XCTUnwrap(original.range(of: a + b + c), original)
        let prefix = String(original[..<inserted.lowerBound])
        let suffix = String(original[inserted.upperBound...])
        app.buttons["Preview"].tap()
        app.buttons["Collapse Outline Alpha"].tap()
        app.buttons["org.document.outline"].tap()
        let outline = app.scrollViews["org.document.outline.scroll"]
        let alpha = outlineHeading("Outline Alpha", in: app)
        let beta = outlineHeading("Outline Beta", in: app)
        XCTAssertTrue(alpha.waitForExistence(timeout: 3))
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: beta.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(app.buttons["org.document.outline.done"].exists)
        let nested = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Heading level 2'"), object: alpha)
        XCTAssertEqual(XCTWaiter.wait(for: [nested], timeout: 4), .completed)
        XCTAssertTrue(outline.buttons["Collapse Outline Beta"].exists)
        XCTAssertTrue(outline.buttons["Expand Outline Alpha"].exists)
        outline.buttons["Expand Outline Alpha"].tap()
        XCTAssertTrue(outlineHeading("Alpha child", in: app).waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Outline drag nested subtree"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["org.document.outline.done"].tap()
        XCTAssertTrue(app.buttons["Expand Outline Alpha"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + nestedA + c + suffix)
        app.buttons["org.document.outline"].tap()
        outline.buttons["Expand Outline Beta"].tap()
        let gamma = outlineHeading("Outline Gamma", in: app)
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: gamma.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.95)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        let outdented = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Heading level 1'"), object: alpha)
        XCTAssertEqual(XCTWaiter.wait(for: [outdented], timeout: 4), .completed)
        alpha.tap()
        XCTAssertTrue(app.buttons["org.document.outline.done"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, prefix + b + c + a + suffix)
        app.buttons["org.editor.undo"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + nestedA + c + suffix)
    }

    func testFilteredOutlineDragMovesHiddenContentAndPreviewNavigationStillWorks() throws {
        let app = outlineDragApp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Files'")).firstMatch.tap()
        app.buttons["files.open.journal/2026.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        let a = "* TODO Filter Alpha\nAlpha body\n** DONE Hidden child\nHidden body\n"
        let b = "* TODO Filter Beta\nBeta body\n"
        editor.typeText("\n" + a + b)
        let original = try XCTUnwrap(editor.value as? String)
        let inserted = try XCTUnwrap(original.range(of: a + b), original)
        let prefix = String(original[..<inserted.lowerBound])
        let suffix = String(original[inserted.upperBound...])
        app.buttons["Preview"].tap()
        app.buttons["org.document.outline"].tap()
        app.buttons["org.document.outline.filter"].tap()
        app.buttons["org.outline.filter.state.TODO"].tap()
        app.buttons["org.outline.filter.done"].tap()
        let alpha = outlineHeading("Filter Alpha", in: app)
        let beta = outlineHeading("Filter Beta", in: app)
        XCTAssertTrue(alpha.waitForExistence(timeout: 3))
        XCTAssertFalse(outlineHeading("Hidden child", in: app).exists)
        beta.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.05)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            beta.frame.minY < alpha.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 4), .completed)
        alpha.tap()
        XCTAssertTrue(app.buttons["org.document.outline.done"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Filter Alpha"].isHittable)
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + a + suffix)
    }

    private func outlineDragApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "Light"]
        app.launch()
        return app
    }

    func testPreviewHeadingDragMovesBodyAndSharesEditorUndo() throws {
        let app = gestureApp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Files'")).firstMatch.tap()
        app.buttons["files.open.inbox.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        let original = try XCTUnwrap(editor.value as? String)
        let first = try XCTUnwrap(original.range(of: "* TODO [#A]"))
        let second = try XCTUnwrap(original.range(of: "* TODO [#B]"))
        let third = try XCTUnwrap(original.range(of: "* TODO Evening"))
        let expected = String(original[..<first.lowerBound])
            + String(original[second.lowerBound..<third.lowerBound])
            + String(original[first.lowerBound..<second.lowerBound])
            + String(original[third.lowerBound...])
        app.buttons["Preview"].tap()
        let heading = app.staticTexts["Write tree-sitter Org queries"]
        let target = app.staticTexts["Review quarterly roadmap"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        heading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            heading.frame.minY < target.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 4), .completed)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Preview heading reordered with body"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, expected)
        editor.tap()
        app.buttons["org.editor.undo"].tap()
        XCTAssertEqual(editor.value as? String, original)
        app.buttons["Preview"].tap()
        XCTAssertLessThan(target.frame.minY, heading.frame.minY)
    }

    func testPreviewDragCarriesCollapsedNestedSubtreeAndCanMoveBack() throws {
        let app = gestureApp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Files'")).firstMatch.tap()
        app.buttons["files.open.journal/2026.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        let a = "* Drag Alpha\nAlpha body\n** Alpha child\nNested body\n"
        let b = "* Drag Beta\nBeta body\n"
        editor.typeText("\n" + a + b)
        let original = try XCTUnwrap(editor.value as? String)
        let inserted = try XCTUnwrap(original.range(of: a + b), original)
        let prefix = String(original[..<inserted.lowerBound])
        let suffix = String(original[inserted.upperBound...])
        app.buttons["Preview"].tap()
        let collapse = app.buttons["Collapse Drag Alpha"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        collapse.tap()
        let alpha = app.staticTexts["Drag Alpha"]
        let beta = app.staticTexts["Drag Beta"]
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: beta.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            beta.frame.minY < alpha.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 4), .completed)
        XCTAssertTrue(app.buttons["Expand Drag Alpha"].exists)
        XCTAssertFalse(app.staticTexts["Alpha child"].exists)
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + a + suffix)
        app.buttons["Preview"].tap()
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: beta.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        app.buttons["Expand Drag Alpha"].tap()
        XCTAssertTrue(app.staticTexts["Alpha child"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, original)
    }

    func testPreviewDragOntoHeadingNestsReparentsAndOutdentsWholeSubtree() throws {
        let app = gestureApp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Files'")).firstMatch.tap()
        app.buttons["files.open.journal/2026.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        let a = "* TODO Drag Alpha\nAlpha body\n** Alpha child\nNested body\n"
        let b = "* TODO [#B] Drag Beta :project:\nBeta body\n** Beta child\nBeta child body\n"
        let c = "* Drag Gamma\nGamma body\n"
        let nestedA = "** TODO Drag Alpha\nAlpha body\n*** Alpha child\nNested body\n"
        editor.typeText("\n" + a + b + c)
        let original = try XCTUnwrap(editor.value as? String)
        let inserted = try XCTUnwrap(original.range(of: a + b + c), original)
        let prefix = String(original[..<inserted.lowerBound])
        let suffix = String(original[inserted.upperBound...])
        app.buttons["Preview"].tap()
        app.buttons["Collapse Drag Alpha"].tap()
        app.buttons["Collapse Drag Beta"].tap()
        let alpha = app.staticTexts["Drag Alpha"]
        let beta = app.staticTexts["Drag Beta"]
        let gamma = app.staticTexts["Drag Gamma"]
        func dragAlpha(onto target: XCUIElement, y: CGFloat) {
            alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.8,
                       thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)),
                       withVelocity: .slow, thenHoldForDuration: 0.6)
        }
        dragAlpha(onto: beta, y: 0.5)
        XCTAssertTrue(app.buttons["Collapse Drag Beta"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Expand Drag Alpha"].exists)
        XCTAssertFalse(app.staticTexts["Alpha child"].exists)
        XCTAssertGreaterThan(alpha.frame.minX, beta.frame.minX)
        app.buttons["Collapse Drag Beta"].tap()
        XCTAssertTrue(alpha.waitForNonExistence(timeout: 3))
        app.buttons["Expand Drag Beta"].tap()
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + nestedA + c + suffix)
        app.buttons["Preview"].tap()

        dragAlpha(onto: gamma, y: 0.5)
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + c + nestedA + suffix)
        app.buttons["Preview"].tap()
        XCTAssertTrue(app.buttons["Expand Drag Alpha"].exists)
        dragAlpha(onto: gamma, y: 0.95)
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + c + a + suffix)
        editor.tap()
        app.buttons["org.editor.undo"].tap()
        XCTAssertEqual(editor.value as? String, prefix + b + c + nestedA + suffix)
        app.buttons["Preview"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nested heading subtree after drag"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCancelledPreviewHeadingDragDoesNotChangeSource() throws {
        let app = gestureApp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Files'")).firstMatch.tap()
        app.buttons["files.open.inbox.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        let original = try XCTUnwrap(editor.value as? String)
        app.buttons["Preview"].tap()
        let heading = app.staticTexts["Review quarterly roadmap"]
        heading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        app.buttons["Edit"].tap()
        XCTAssertEqual(editor.value as? String, original)
        app.buttons["Preview"].tap()
        let todo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.todo.'")).firstMatch
        todo.tap()
        XCTAssertEqual(todo.value as? String, "NEXT")
    }

    func testSourceEditorExtendsBehindTabBar() {
        verifySourceEditorTabBar(appearance: "Light")
    }

    func testSourceEditorExtendsBehindTabBarInDarkAppearance() {
        verifySourceEditorTabBar(appearance: "Dark")
    }

    private func verifySourceEditorTabBar(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-appearance", appearance
        ]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.open.inbox.org"].tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        let filesTab = app.tabBars.buttons["Files"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(filesTab.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let original = editor.value as? String
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Source editor under Tabbar - \(appearance)"
        before.lifetime = .keepAlways
        add(before)
        XCTAssertGreaterThan(editor.frame.maxY, filesTab.frame.maxY,
                             "The editor must extend behind the floating Tabbar, not stop above it")

        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo:
                editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(filesTab.isHittable)
        XCTAssertGreaterThan(editor.frame.maxY, filesTab.frame.maxY)
        XCTAssertEqual(editor.value as? String, original)

        app.buttons["Preview"].tap()
        app.buttons["Edit"].tap()
        XCTAssertGreaterThan(editor.frame.maxY, filesTab.frame.maxY)
        XCTAssertEqual(editor.value as? String, original)
    }

    func testOrgKeyboardCommandsAndCaretSurvivePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '2026 Journal,'")).firstMatch.tap()
        app.buttons["Edit"].tap()
        app.buttons["org.document.outline"].tap()
        app.buttons["org.document.outline.disclosure.0"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.document.outline.heading.' AND label == 'Morning note'")).firstMatch.tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(app.buttons["Edit"].isSelected)
        editor.typeText("Typed ")
        app.buttons["Preview"].tap()
        app.buttons["Edit"].tap()
        // Returning to Edit restores keyboard focus and the insertion point.
        editor.typeText("again ")
        XCTAssertTrue((editor.value as? String)?.contains("Typed again ** Morning note") == true)
        let heading = app.buttons["org.editor.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        // The document extends behind the floating controls instead of ending
        // at a full-width keyboard accessory shelf.
        XCTAssertGreaterThan(editor.frame.maxY, heading.frame.maxY + 8)
        heading.tap()
        XCTAssertTrue((editor.value as? String)?.contains("* Typed again ** Morning note") == true)
        app.buttons["org.editor.undo"].tap()
        XCTAssertTrue((editor.value as? String)?.contains("\nTyped again ** Morning note") == true)
        app.buttons["org.editor.indent"].tap()
        app.buttons["Indent"].tap()
        XCTAssertTrue((editor.value as? String)?.contains("\n  Typed again ** Morning note") == true)
        app.buttons["org.editor.indent"].tap()
        app.buttons["Outdent"].tap()
        XCTAssertTrue((editor.value as? String)?.contains("\nTyped again ** Morning note") == true)
        app.buttons["org.editor.checkbox"].tap()
        XCTAssertTrue((editor.value as? String)?.contains("\n- [ ] Typed again ** Morning note") == true)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        app.buttons["org.editor.date"].tap()
        let insert = app.buttons["org.editor.date.insert"]
        XCTAssertTrue(insert.waitForExistence(timeout: 3))
        insert.tap()
        XCTAssertNotNil((editor.value as? String)?.range(of: #"<\d{4}-\d{2}-\d{2} [A-Za-z]{3}>"#, options: .regularExpression))
        app.buttons["Preview"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
    }

    func testDocumentModeSwitchPreservesPreviewScrollPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch.tap()
        let scroll = app.scrollViews["org.preview.scroll"]
        scroll.swipeUp()
        let heading = app.staticTexts["Plan iPad reading workflow"]
        XCTAssertTrue(heading.isHittable)
        let y = heading.frame.minY
        app.buttons["Edit"].tap()
        app.buttons["Preview"].tap()
        XCTAssertTrue(heading.isHittable)
        XCTAssertEqual(heading.frame.minY, y, accuracy: 2)
    }

    func testOrgMarkupPreviewAndEditorPreserveSource() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-appearance", "Light"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        let restored = app.navigationBars.buttons["BackButton"]
        if restored.waitForExistence(timeout: 1) { restored.tap() }
        let inbox = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        inbox.tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        editor.typeText("""

        * Org reading [2/3]
        Read *bold* /italic/ _underline_ +old+ ~code~ and [[https://orgmode.org][Org manual]].
        :LOGBOOK:
        CLOCK: [2026-09-19 Sat 09:00]--[2026-09-19 Sat 10:25] => 1:25
        - State "DONE" [2026-09-19 Sat]
        :END:
        | Item | Status |
        |------+--------|
        | *Parser* | Ready |
        | Preview | [2/3] |
        #+BEGIN_SRC swift
        let message = "Hello, Org"
        #+END_SRC

        """)
        let source = editor.value as? String
        app.buttons["Preview"].tap()
        let scroll = app.scrollViews["org.preview.scroll"]
        let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Read bold italic underline old code and Org manual.'")).firstMatch
        for _ in 0..<8 {
            if text.exists && text.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(text.exists)
        XCTAssertFalse(app.staticTexts["Read *bold* /italic/ _underline_ +old+ ~code~ and [[https://orgmode.org][Org manual]]."].exists)
        let drawer = app.buttons.matching(NSPredicate(format: "label CONTAINS 'LOGBOOK'")).firstMatch
        XCTAssertTrue(drawer.isHittable)
        drawer.tap()
        XCTAssertTrue(app.staticTexts["1h 25m"].firstMatch.waitForExistence(timeout: 3))
        scroll.swipeUp()
        let code = app.staticTexts["let message = \"Hello, Org\""]
        for _ in 0..<4 {
            if code.exists && code.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(code.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '#+BEGIN_SRC'")).firstMatch.exists)
        XCTAssertTrue(app.scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.table.'")).firstMatch.exists)
        app.buttons["Edit"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, source)
    }

    func testLogbookPreviewCollapsesWithoutChangingSource() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        let restoredDocument = app.navigationBars.buttons["BackButton"]
        if restoredDocument.waitForExistence(timeout: 1) { restoredDocument.tap() }
        let inbox = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        inbox.tap()
        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        editor.typeText("\n* Drawer preview\n:PROPERTIES:\n:ID: compact-preview\n:CATEGORY: Notes\n:END:\n:LOGBOOK:\nCLOCK: => 1:25\nPrivate log note\n:END:\nVisible after drawer\n")
        let source = editor.value as? String
        XCTAssertTrue(source?.contains(":LOGBOOK:") == true)
        app.buttons["Preview"].tap()

        let drawer = app.buttons.matching(NSPredicate(format: "label CONTAINS 'LOGBOOK'")).firstMatch
        let scroll = app.scrollViews["org.preview.scroll"]
        for _ in 0..<8 {
            if drawer.exists && drawer.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(drawer.isHittable)
        let log = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Private log note'")).firstMatch
        XCTAssertFalse(log.exists)
        drawer.tap()
        XCTAssertTrue(log.waitForExistence(timeout: 3))
        drawer.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, source)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureKeepsUnsavedDraftAndSavesSearchableTask() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["New task"].tap()
        let title = app.textFields["item.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Capture regression task")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Keep Editing"].waitForExistence(timeout: 2))
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(title.value as? String, "Capture regression task")
        app.buttons["item.editor.save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))

        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields["Search orgenda"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Capture regression task")
        XCTAssertTrue(app.staticTexts["Capture regression task"].firstMatch.waitForExistence(timeout: 3))
    }

    func testCaptureSourcePreviewUsesBackNavigationAndPreservesDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["New task"].tap()

        let draftTitle = "Source preview keeps this draft"
        let title = app.textFields["item.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText(draftTitle)

        let keyboardDone = app.buttons["Done"]
        if keyboardDone.exists && keyboardDone.isHittable {
            keyboardDone.tap()
        }

        let form = app.descendants(matching: .any)
            .matching(identifier: "item.editor.form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        let previewButton = app.buttons["Preview Org"]
        for _ in 0..<12 {
            if previewButton.exists && previewButton.isHittable { break }
            // Drag in the Form's outer inset so the Notes editor cannot
            // consume the gesture as a nested text-view scroll.
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo:
                    form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.2)))
        }
        XCTAssertTrue(previewButton.isHittable)
        previewButton.tap()

        let previewNavigationBar = app.navigationBars["Org Preview"]
        XCTAssertTrue(previewNavigationBar.waitForExistence(timeout: 3))
        let back = previewNavigationBar.buttons.matching(NSPredicate(
            format: "label == 'Back' OR label == 'New Item' OR label BEGINSWITH 'Back, '"
        )).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 2))
        XCTAssertFalse(previewNavigationBar.buttons["Done"].exists,
                       "Source preview should use the editor's navigation stack, not a second sheet")
        let source = app.textViews["Org source editor"]
        XCTAssertTrue(source.waitForExistence(timeout: 2))
        XCTAssertTrue((source.value as? String)?.contains(draftTitle) == true)

        back.tap()
        XCTAssertTrue(previewNavigationBar.waitForNonExistence(timeout: 3))
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        for _ in 0..<12 {
            if title.exists && title.isHittable { break }
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.2))
                .press(forDuration: 0.05, thenDragTo:
                    form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8)))
        }
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.value as? String, draftTitle)

        app.navigationBars["New Item"].buttons["Cancel"].tap()
        let discard = app.alerts.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(form.waitForNonExistence(timeout: 3))
    }

    func testCalendarTimelineScrollSelectsTopDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        let timeline = app.scrollViews["orgenda.agenda.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 3))
        let selectedDay = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'orgenda.calendar.day.' AND selected == true"
        )).firstMatch
        let todayID = selectedDay.identifier

        func descendants(of element: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            [element] + element.children.flatMap { descendants(of: $0) }
        }

        func assertTopDayIsSelected() {
            let matchesTopDay = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let snapshot = try? timeline.snapshot() else { return false }
                let headers = descendants(of: snapshot).filter {
                    $0.identifier.hasPrefix("orgenda.agenda.day.")
                }
                guard let top = headers.filter({
                    $0.frame.maxY > snapshot.frame.minY + 1
                        && $0.frame.minY < snapshot.frame.maxY
                }).min(by: { $0.frame.minY < $1.frame.minY }) else { return false }
                let key = top.identifier.replacingOccurrences(of: "orgenda.agenda.day.", with: "")
                return selectedDay.identifier == "orgenda.calendar.day.\(key)"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [matchesTopDay], timeout: 4), .completed)
        }

        assertTopDayIsSelected()
        let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let tomorrowHeader = timeline.staticTexts["orgenda.agenda.day.\(formatter.string(from: tomorrow))"]
        let initialTomorrowY = tomorrowHeader.frame.minY
        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -80)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        assertTopDayIsSelected()
        XCTAssertEqual(selectedDay.identifier, todayID)
        XCTAssertLessThan(tomorrowHeader.frame.minY, initialTomorrowY - 30,
                          "Scrolling within a day must not snap back to its header")

        for _ in 0..<4 {
            timeline.swipeUp(velocity: .slow)
            assertTopDayIsSelected()
            if selectedDay.identifier != todayID { break }
        }
        XCTAssertNotEqual(selectedDay.identifier, todayID)
        let laterID = selectedDay.identifier
        timeline.swipeDown(velocity: .slow)
        assertTopDayIsSelected()
        XCTAssertNotEqual(selectedDay.identifier, laterID)

        timeline.swipeUp()
        assertTopDayIsSelected()
        let scrolledDateID = selectedDay.identifier
        let alternateDay = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'orgenda.calendar.day.' AND selected == false"
        )).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(alternateDay)
        alternateDay?.tap()
        assertTopDayIsSelected()
        app.buttons[scrolledDateID].tap()
        assertTopDayIsSelected()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar selection follows top timeline day"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["orgenda.calendar.today"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "identifier == %@", todayID), object: selectedDay
        )], timeout: 3), .completed)
        assertTopDayIsSelected()
    }

    func testCalendarPagingPreservesSelectionAndReturnsToday() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        let densityMenu = app.buttons["orgenda.calendar.density"]
        XCTAssertTrue(densityMenu.waitForExistence(timeout: 3))
        densityMenu.tap()
        let monthOption = app.buttons.matching(NSPredicate(format: "label == %@", "Month")).firstMatch
        XCTAssertTrue(monthOption.waitForExistence(timeout: 2))
        monthOption.tap()

        XCTAssertFalse(app.buttons["orgenda.calendar.today"].exists)
        app.tabBars.buttons["Dashboard"].tap()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertEqual(densityMenu.value as? String, "Month")

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date.now)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        let currentMonthTitle = today.formatted(.dateTime.month(.wide).year())
        let nextMonthTitle = nextMonth.formatted(.dateTime.month(.wide).year())
        let preferredDay = calendar.component(.day, from: today)
        let nextMonthDayRange = calendar.range(of: .day, in: .month, for: nextMonth) ?? 1..<2
        var nextSelectionComponents = calendar.dateComponents([.era, .year, .month], from: nextMonth)
        nextSelectionComponents.day = min(preferredDay, nextMonthDayRange.upperBound - 1)
        let nextSelectedDate = calendar.date(from: nextSelectionComponents) ?? nextMonth
        let alternateDate = calendar.date(
            byAdding: .day,
            value: calendar.component(.day, from: today) == 1 ? 1 : -1,
            to: today
        ) ?? today

        let calendarMonths = app.scrollViews["orgenda.calendar.months"]
        XCTAssertTrue(calendarMonths.waitForExistence(timeout: 3))
        XCTAssertEqual(calendarMonths.value as? String, currentMonthTitle)

        calendarMonths.swipeUp()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", nextMonthTitle), object: calendarMonths
        )], timeout: 2), .completed)
        let nextSelectedDateLabel = nextSelectedDate.formatted(date: .complete, time: .omitted)
        let visibleNextSelection = calendarMonths.buttons
            .matching(NSPredicate(format: "label == %@ AND selected == true", nextSelectedDateLabel))
            .firstMatch
        XCTAssertTrue(visibleNextSelection.waitForExistence(timeout: 3))

        calendarMonths.swipeDown()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", currentMonthTitle), object: calendarMonths
        )], timeout: 2), .completed)
        let todayLabel = today.formatted(date: .complete, time: .omitted)
        let visibleToday = calendarMonths.buttons
            .matching(NSPredicate(format: "label == %@ AND selected == true", todayLabel))
            .firstMatch
        XCTAssertTrue(visibleToday.waitForExistence(timeout: 3))

        let alternateDateLabel = alternateDate.formatted(date: .complete, time: .omitted)
        let selectedDate = calendarMonths.buttons
            .matching(NSPredicate(format: "label == %@", alternateDateLabel))
            .firstMatch
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 2))
        selectedDate.tap()

        let todayWithItems = calendarMonths.buttons
            .matching(NSPredicate(format: "label == %@", todayLabel))
            .firstMatch
        XCTAssertTrue(todayWithItems.exists)
        XCTAssertEqual(todayWithItems.value as? String, "Today, Has scheduled items")
        let returnToday = app.buttons["orgenda.calendar.today"]
        XCTAssertTrue(returnToday.isHittable)
        returnToday.tap()
        XCTAssertTrue(returnToday.waitForNonExistence(timeout: 2))
        XCTAssertTrue(visibleToday.isSelected)
    }

    func testWeekSelectionCrossesMonthBoundary() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()

        let calendar = Calendar.autoupdatingCurrent
        let currentMonth = calendar.dateInterval(of: .month, for: .now)!.start
        var nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)!
        // Choose a boundary whose two dates share a week in the user's calendar.
        let needsNextMonth = calendar.component(.weekday, from: nextMonth) == calendar.firstWeekday
        if needsNextMonth {
            nextMonth = calendar.date(byAdding: .month, value: 1, to: nextMonth)!
        }
        let previousDay = calendar.date(byAdding: .day, value: -1, to: nextMonth)!

        let densityMenu = app.buttons["orgenda.calendar.density"]
        XCTAssertTrue(densityMenu.waitForExistence(timeout: 3))
        densityMenu.tap()
        app.buttons["Month"].tap()
        let months = app.scrollViews["orgenda.calendar.months"]
        XCTAssertTrue(months.waitForExistence(timeout: 2))
        if needsNextMonth { months.swipeUp() }

        let previousLabel = previousDay.formatted(date: .complete, time: .omitted)
        let previousDate = months.buttons.matching(NSPredicate(format: "label == %@", previousLabel)).firstMatch
        XCTAssertTrue(previousDate.waitForExistence(timeout: 2))
        previousDate.tap()
        densityMenu.tap()
        app.buttons["Week"].tap()

        let nextLabel = nextMonth.formatted(date: .complete, time: .omitted)
        let nextDate = app.buttons.matching(NSPredicate(format: "label == %@", nextLabel)).firstMatch
        XCTAssertTrue(nextDate.waitForExistence(timeout: 2))
        nextDate.tap()
        XCTAssertTrue(nextDate.isSelected, "A selected date in the adjacent month must retain its glass highlight")
        XCTAssertTrue(app.staticTexts[nextMonth.formatted(.dateTime.month(.wide).year())].exists)

        let previousWeekDate = app.buttons.matching(NSPredicate(format: "label == %@", previousLabel)).firstMatch
        previousWeekDate.tap()
        XCTAssertTrue(previousWeekDate.isSelected)
        XCTAssertFalse(nextDate.isSelected)
    }

    func testCalendarCaptureUsesSelectedDate() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        let days = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'orgenda.calendar.day.' AND selected == false"
        ))
        let neighbor = days.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(neighbor)
        let key = String((neighbor?.identifier ?? "").dropFirst("orgenda.calendar.day.".count))
        neighbor?.tap()
        app.buttons["orgenda.capture"].tap()
        let title = app.textFields["item.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Calendar date capture")
        app.buttons["item.editor.save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Calendar date capture"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Files"].tap()
        app.buttons["files.open.inbox.org"].tap()
        app.buttons["Edit"].tap()
        let source = app.textViews["Org source editor"].value as? String ?? ""
        let captured = source.components(separatedBy: "* TODO Calendar date capture").last ?? ""
        XCTAssertTrue(captured.contains("SCHEDULED: <\(key)"))
    }

    func testInteractivePreviewWritesControlsBackToOrgSource() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()

        let inbox = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 3))
        inbox.tap()

        let roadmapTitle = app.staticTexts["Review quarterly roadmap"]
        XCTAssertTrue(roadmapTitle.waitForExistence(timeout: 2))

        let todo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.todo.'")).firstMatch
        XCTAssertTrue(todo.waitForExistence(timeout: 2))
        XCTAssertEqual(todo.value as? String, "TODO")

        todo.tap()
        XCTAssertEqual(todo.value as? String, "NEXT")

        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertTrue((editor.value as? String)?.contains("* NEXT [#A] Review quarterly roadmap") == true)

        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))
        let readingNotes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reading Notes,'")).firstMatch
        XCTAssertTrue(readingNotes.waitForExistence(timeout: 3))
        readingNotes.tap()

        let checkboxes = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'org.preview.checkbox.'")
        )
        let unchecked = checkboxes.element(boundBy: 1)
        XCTAssertTrue(unchecked.waitForExistence(timeout: 2))
        unchecked.tap()
        XCTAssertEqual(unchecked.value as? String, "Checked")

        app.buttons["Edit"].tap()
        let notesEditor = app.textViews["Org source editor"]
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 2))
        XCTAssertTrue((notesEditor.value as? String)?.contains("- [X] Make capture effortless") == true)
    }

    func testWorkflowIconPickerSelectsEveryStateAndSaves() {
        let app = gestureApp()
        let item = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'agenda.item.open.' AND label CONTAINS 'Review quarterly roadmap'"
        )).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()

        for state in ["TODO", "NEXT", "WAIT", "SOMEDAY", "URGENT", "DONE", "CANCELED"] {
            let option = app.buttons["workflow.option.\(state)"]
            XCTAssertTrue(option.waitForExistence(timeout: 2))
            option.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: option)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed, state)
            XCTAssertGreaterThanOrEqual(option.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(option.frame.height, 44 - 0.001)
        }
        app.buttons["workflow.option.URGENT"].tap()
        app.buttons["item.editor.save"].tap()
        XCTAssertTrue(app.buttons["item.editor.save"].waitForNonExistence(timeout: 3))
        let updated = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'agenda.item.complete.' AND value == 'Review quarterly roadmap, URGENT'"
        )).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 3))

        app.tabBars.buttons["Files"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox,'")).firstMatch.tap()
        let state = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.todo.'")).firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 3))
        XCTAssertEqual(state.value as? String, "URGENT")
        app.buttons["Edit"].tap()
        XCTAssertTrue((app.textViews["Org source editor"].value as? String)?.contains("* URGENT [#A] Review quarterly roadmap") == true)
    }

    func testPlanningPreviewEditsTypeAndDateBackToOrgSource() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()

        let calendarFile = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Calendar,'")
        ).firstMatch
        XCTAssertTrue(calendarFile.waitForExistence(timeout: 3))
        calendarFile.tap()

        let planningEntry = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'org.preview.planning.entry.'")
        ).firstMatch
        XCTAssertTrue(planningEntry.waitForExistence(timeout: 2))
        XCTAssertTrue((planningEntry.label).contains("Scheduled"))
        planningEntry.tap()

        let kindPicker = app.segmentedControls["org.preview.planning.kindPicker"]
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 2))
        kindPicker.buttons["DEADLINE"].tap()

        let nextDay = app.buttons["org.preview.planning.start.nextDay"]
        XCTAssertTrue(nextDay.exists)
        nextDay.tap()

        let save = app.buttons["org.preview.planning.save"]
        XCTAssertTrue(save.exists)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 2))

        let updatedEntry = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'org.preview.planning.entry.'")
        ).firstMatch
        XCTAssertTrue(updatedEntry.waitForExistence(timeout: 2))
        XCTAssertTrue(updatedEntry.label.contains("Deadline"))

        let calendar = Calendar.autoupdatingCurrent
        let nextDate = calendar.date(byAdding: .day, value: 1, to: Date.now) ?? Date.now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd EEE"
        let expectedTimestamp = formatter.string(from: nextDate)
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMM d EEE")
        XCTAssertTrue((updatedEntry.value as? String)?.contains(formatter.string(from: nextDate)) == true)

        app.buttons["Edit"].tap()
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (editor.value as? String)?.contains("DEADLINE: <\(expectedTimestamp)>") == true
        )
    }

    func testPlanningPreviewAddsYearlyRecurrence() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        let calendarFile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Calendar,'")).firstMatch
        XCTAssertTrue(calendarFile.waitForExistence(timeout: 3))
        calendarFile.tap()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.planning.entry.'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 2))
        entry.tap()
        let enabled = app.switches["org.preview.planning.start.recurrence.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 2))
        enabled.tap()
        let unit = app.buttons["org.preview.planning.start.recurrence.unit"]
        if !unit.isHittable { app.scrollViews["org.preview.planning.editor.scroll"].swipeUp() }
        unit.tap()
        app.buttons["Years"].tap()
        app.buttons["org.preview.planning.save"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 2))
        XCTAssertTrue((entry.value as? String)?.contains("Every year") == true)
        app.buttons["Edit"].tap()
        XCTAssertTrue((app.textViews["Org source editor"].value as? String)?.contains("+1y>") == true)
    }

    func testPlainRecurringTimestampPreviewUsesControlsAndRemovesRule() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        let calendarFile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Calendar,'")).firstMatch
        XCTAssertTrue(calendarFile.waitForExistence(timeout: 3))
        calendarFile.tap()
        app.buttons["Edit"].tap()
        let sourceEditor = app.textViews["Org source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 2))
        sourceEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.86)).tap()
        sourceEditor.typeText("\n* Yearly anniversary\n<2019-05-20 Mon +1y -2d>\n")
        app.buttons["Preview"].tap()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'org.preview.timestamp.entry.'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertTrue((entry.value as? String)?.contains("2019") == true)
        XCTAssertTrue((entry.value as? String)?.contains("Every year") == true)
        entry.tap()
        XCTAssertFalse(app.segmentedControls["org.preview.planning.kindPicker"].exists)
        XCTAssertFalse(app.textFields["org.preview.planning.start.recurrence.rule"].exists)
        let unit = app.buttons["org.preview.planning.start.recurrence.unit"]
        XCTAssertTrue(unit.waitForExistence(timeout: 2))
        XCTAssertTrue(unit.label.contains("Years"))
        unit.tap()
        app.buttons["Days"].tap()
        app.buttons["org.preview.planning.start.recurrence.interval-Increment"].tap()
        app.buttons["org.preview.planning.start.recurrence.mode"].tap()
        app.buttons["Completion date"].tap()
        app.switches["org.preview.planning.start.recurrence.maximum.enabled"].tap()
        app.buttons["org.preview.planning.start.recurrence.maximum.interval-Increment"].tap()
        let save = app.buttons["org.preview.planning.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 2))
        XCTAssertTrue((entry.value as? String)?.contains("Every 2 days after completion") == true)
        XCTAssertTrue((entry.value as? String)?.contains("maximum 3 days") == true)
        XCTAssertTrue((entry.value as? String)?.contains("-2d") == true)
        entry.tap()
        app.switches["org.preview.planning.start.recurrence.enabled"].tap()
        save.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue((sourceEditor.value as? String)?.contains("<2019-05-20 Mon -2d>") == true)
        XCTAssertFalse((sourceEditor.value as? String)?.contains("SCHEDULED: <2019-05-20") == true)
    }

    func testDocumentOutlineIsReadOnlyCollapsibleAndNavigatesToHeading() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 3))

        let journalFile = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '2026 Journal,'")
        ).firstMatch
        XCTAssertTrue(journalFile.waitForExistence(timeout: 2))
        journalFile.tap()

        let previewRootDisclosure = app.buttons["org.preview.heading.disclosure.0"]
        XCTAssertTrue(previewRootDisclosure.waitForExistence(timeout: 2))
        XCTAssertEqual(previewRootDisclosure.value as? String, "Expanded")
        previewRootDisclosure.tap()
        XCTAssertEqual(previewRootDisclosure.value as? String, "Collapsed")
        XCTAssertTrue(app.staticTexts["Morning note"].waitForNonExistence(timeout: 2))

        let outlineButton = app.buttons["org.document.outline"]
        XCTAssertTrue(outlineButton.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["org.document.more"].exists)
        outlineButton.tap()

        XCTAssertTrue(app.navigationBars["Outline"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields.count, 0)
        // The source view stays alive to retain selection and undo. It must not
        // accept input through the read-only outline sheet.
        XCTAssertFalse(app.textViews["Org source editor"].isHittable)

        let rootHeading = app.buttons["org.document.outline.heading.0"]
        XCTAssertTrue(rootHeading.waitForExistence(timeout: 2))
        XCTAssertEqual(rootHeading.value as? String, "Heading level 1")

        let outlineDisclosure = app.buttons["org.document.outline.disclosure.0"]
        let childHeading = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.document.outline.heading.' AND label == 'Morning note'"
        )).firstMatch
        XCTAssertTrue(outlineDisclosure.exists)
        XCTAssertEqual(outlineDisclosure.value as? String, "Collapsed")
        XCTAssertFalse(childHeading.exists)

        outlineDisclosure.tap()
        XCTAssertEqual(outlineDisclosure.value as? String, "Expanded")
        XCTAssertTrue(childHeading.waitForExistence(timeout: 2))
        outlineDisclosure.tap()
        XCTAssertEqual(outlineDisclosure.value as? String, "Collapsed")
        XCTAssertTrue(childHeading.waitForNonExistence(timeout: 2))
        outlineDisclosure.tap()
        XCTAssertTrue(childHeading.waitForExistence(timeout: 2))

        childHeading.tap()
        XCTAssertTrue(app.navigationBars["Outline"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Preview"].isSelected)
        XCTAssertTrue(app.staticTexts["Morning note"].waitForExistence(timeout: 2))
        XCTAssertEqual(previewRootDisclosure.value as? String, "Expanded")

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textViews["Org source editor"].waitForExistence(timeout: 2))
        outlineButton.tap()
        let repeatedDisclosure = app.buttons["org.document.outline.disclosure.0"]
        XCTAssertTrue(repeatedDisclosure.waitForExistence(timeout: 2))
        if repeatedDisclosure.value as? String == "Collapsed" {
            repeatedDisclosure.tap()
        }
        let repeatedChild = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'org.document.outline.heading.' AND label == 'Morning note'"
        )).firstMatch
        XCTAssertTrue(repeatedChild.waitForExistence(timeout: 2))
        repeatedChild.tap()
        XCTAssertTrue(app.buttons["Edit"].isSelected)
        let editor = app.textViews["Org source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("Located ")
        XCTAssertTrue((editor.value as? String)?.contains("Located ** Morning note") == true)
    }

    func testTODOCaptureKeepsNewItemUnscheduled() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace"]
        app.launch()
        app.tabBars.buttons["Dashboard"].tap()
        chooseAgendaView("TODOs", in: app)
        app.buttons["New task"].tap()
        let title = app.textFields["item.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Unscheduled capture check")
        app.buttons["item.editor.save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Unscheduled capture check"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Unscheduled · 2 open"].exists)
    }

    private func chooseAgendaView(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["agenda.viewMenu"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        // Target the picker option, not the same-named tab behind its menu.
        let option = app.buttons["agenda.mode.\(name.lowercased())"]
        XCTAssertTrue(option.waitForExistence(timeout: 2))
        option.tap()
    }

}
