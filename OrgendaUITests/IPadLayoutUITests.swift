import XCTest
import UIKit

final class IPadLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires an iPad simulator")
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testSidebarGroupsDashboardViewsAndPreservesSelection() throws {
        let app = launchApp(configuredAgenda: true)
        defer { app.terminate() }
        showSidebar(in: app)

        let calendar = try sidebarItem("Calendar", in: app)
        let files = try sidebarItem("Files", in: app)
        let search = try sidebarItem("Search", in: app)
        XCTAssertLessThan(calendar.frame.minY, files.frame.minY)
        XCTAssertLessThan(files.frame.minY, search.frame.minY)
        let dashboardLabels = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Dashboard'"))
            .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minX < calendar.frame.maxX }
        XCTAssertTrue(dashboardLabels.contains { $0.frame.minY > search.frame.maxY },
                      "Dashboard should label a section below the main destinations")
        XCTAssertFalse(dashboardLabels.contains { $0.frame.minY < calendar.frame.minY },
                       "The sidebar must not repeat the top-level Dashboard tab")

        for title in ["Overdue", "Unscheduled", "Urgent actions", "Next actions", "Waiting", "Projects", "Someday"] {
            let item = try sidebarItem(title, in: app)
            XCTAssertGreaterThan(item.frame.minY, search.frame.maxY)
        }
        XCTAssertTrue(app.buttons["agenda.viewMenu"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].isHittable)

        try sidebarItem("Overdue", in: app).tap()
        XCTAssertTrue(app.scrollViews["agenda.view.overdue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Overdue sidebar task"].isHittable)
        showSidebar(in: app)
        try sidebarItem("Waiting", in: app).tap()
        XCTAssertTrue(app.staticTexts["Waiting for review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Waiting for review"].isHittable)
        showSidebar(in: app)
        XCTAssertEqual(element("agenda.currentPerspective", in: app).label, "Waiting")
        XCTAssertFalse(app.buttons["agenda.viewMenu"].exists)
        attach(app, name: "iPad sidebar with Dashboard perspectives")

        tap(app.buttons.matching(NSPredicate(format: "label == 'Hide Sidebar'")).firstMatch)
        let menu = app.buttons["agenda.viewMenu"]
        assertValue("Waiting", of: menu)
        XCTAssertTrue(app.staticTexts["Waiting for review"].isHittable)
        selectRootTab("Calendar", in: app)
        XCTAssertTrue(app.calendarDensityHandle.waitForExistence(timeout: 5))
        selectRootTab("Dashboard", in: app)
        assertValue("Waiting", of: menu)
        attach(app, name: "Dashboard menu restored after hiding sidebar")
    }

    func testNativeSidebarDismissesAfterSelectionInPortrait() throws {
        let app = launchApp(configuredAgenda: true)
        defer { app.terminate() }
        rotate(.portrait, in: app)
        showSidebar(in: app)
        try sidebarItem("Overdue", in: app).tap()
        XCTAssertTrue(app.staticTexts["Overdue sidebar task"].waitForExistence(timeout: 5))
        assertValue("Overdue", of: app.buttons["agenda.viewMenu"])
        let hideSidebar = app.buttons.matching(NSPredicate(format: "label == 'Hide Sidebar'")).firstMatch
        XCTAssertFalse(hideSidebar.exists && hideSidebar.isHittable,
                       "The native temporary sidebar should dismiss after navigation")
        attach(app, name: "Native iPad sidebar dismisses after selection")
    }

    func testTopTabsStayUniqueAcrossSidebarSelections() throws {
        let app = launchApp(configuredAgenda: true)
        defer { app.terminate() }
        rotate(.portrait, in: app)
        for (identifier, title) in [("dashboard", "Dashboard"), ("waiting", "Waiting"),
                                    ("dashboard", "Dashboard")] {
            showSidebar(in: app)
            tap(app.cells["sidebar.perspective.\(identifier)"])
            assertValue(title, of: app.buttons["agenda.viewMenu"])
            // The separate toolbar menu can also be titled Dashboard. Count
            // only entries in the floating tab strip, after its sidebar toggle.
            let sidebarToggle = app.buttons.matching(NSPredicate(
                format: "label == 'Show Sidebar' OR identifier == 'ToggleSideBar' OR label == 'Toggle sidebar'"
            )).firstMatch
            XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
            let tabStripLeadingEdge = sidebarToggle.frame.minX
            for tab in ["Dashboard", "Calendar", "Files", "Search"] {
                let visibleTabs = app.buttons.matching(NSPredicate(format: "label == %@", tab))
                    .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minX > tabStripLeadingEdge }
                XCTAssertEqual(visibleTabs.count, 1,
                               "The tab bar must contain exactly one \(tab) entry. Toggle: \(sidebarToggle.debugDescription). Matches: \(visibleTabs.map(\.debugDescription))")
            }
            selectRootTab("Calendar", in: app)
            XCTAssertTrue(app.calendarDensityHandle.waitForExistence(timeout: 5))
        }
        attach(app, name: "One Dashboard tab after repeated sidebar selections")
    }

    func testCompactDashboardKeepsItsTabAndMenu() {
        let app = launchApp(viewportSize: CGSize(width: 600, height: 600), horizontalSizeClass: "compact")
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isHittable)
        assertValue("Unscheduled", of: app.buttons["agenda.viewMenu"])
        XCTAssertTrue(app.staticTexts["Plan iPad reading workflow"].isHittable)
        XCTAssertFalse(app.buttons["sidebar.perspective.overdue"].exists)
    }

    private func toggleWorkspaceSidebar(in app: XCUIApplication) {
        let toggles = app.buttons.matching(NSPredicate(
            format: "label == 'Hide Sidebar' OR label == 'Show Sidebar' OR identifier == 'ToggleSideBar' OR label == 'Toggle sidebar'"
        )).allElementsBoundByIndex.filter(\.isHittable)
        // Files also has a document-browser sidebar; target the outer one.
        guard let toggle = toggles.min(by: { $0.frame.minX < $1.frame.minX }) else {
            XCTFail("The workspace sidebar toggle must be reachable")
            return
        }
        toggle.tap()
    }

    private func showSidebar(in app: XCUIApplication) {
        let hide = app.buttons.matching(NSPredicate(format: "label == 'Hide Sidebar'")).firstMatch
        if hide.exists && hide.isHittable { return }
        let toggle = app.buttons.matching(NSPredicate(
            format: "identifier == 'ToggleSideBar' OR label == 'Toggle sidebar' OR label == 'Show Sidebar'"
        )).firstMatch
        tap(toggle)
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
    }

    private func sidebarItem(_ title: String, in app: XCUIApplication) throws -> XCUIElement {
        let items = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            items.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "Sidebar item: \(title)")
        // A content heading can share a sidebar label. The native navigation
        // item is the leftmost visible match while the sidebar is presented.
        return try XCTUnwrap(items.allElementsBoundByIndex.filter(\.isHittable)
            .min { $0.frame.minX < $1.frame.minX })
    }

    func testNestedFileDraftSurvivesRotationAndTabNavigation() throws {
        let app = launchApp(fileBrowserFixture: true)
        defer { app.terminate() }
        selectRootTab("Files", in: app)
        tap(app.buttons["files.open.projects"])
        tap(app.buttons["files.open.projects/child"])
        tap(app.buttons["files.open.projects/child/notes.org"])
        let documentHeading = app.staticTexts["Nested content 中文"]
        XCTAssertTrue(documentHeading.waitForExistence(timeout: 5))

        // The browser and document must both be usable in the expanded split.
        let browser = app.scrollViews["files.browser"]
        let preview = app.scrollViews["org.preview.scroll"]
        XCTAssertTrue(browser.isHittable)
        XCTAssertTrue(preview.isHittable)
        let inboxRow = app.buttons["files.open.inbox.org"]
        XCTAssertTrue(inboxRow.isHittable)
        XCTAssertTrue(documentHeading.isHittable)
        // SwiftUI can report a preview scroll view's frame in local coordinates;
        // rendered controls give the actual split-column positions on screen.
        XCTAssertLessThan(inboxRow.frame.maxX, documentHeading.frame.minX)

        tap(app.buttons["Edit"])
        let editor = app.textViews["Org source editor"]
        tap(editor)
        dismissTypingIntroduction(in: app)
        editor.typeText("\niPad rotation draft\n")
        let draft = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(draft.contains("iPad rotation draft"))
        tap(app.buttons["org.editor.dismissKeyboard"])

        rotate(.portrait, in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertTrue(app.buttons["Edit"].isSelected)

        selectRootTab("Calendar", in: app)
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].waitForExistence(timeout: 5))
        selectRootTab("Files", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, draft, "Returning to Files must retain the nested document and its draft")

        rotate(.landscapeLeft, in: app)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertTrue(browser.isHittable)
        // Selecting another root file proves that the sidebar still drives the detail.
        tap(app.buttons["files.open.inbox.org"])
        XCTAssertTrue(app.staticTexts["File gesture probe"].waitForExistence(timeout: 5))
        attach(app, name: "iPad Files split after rotation")
    }

    func testCalendarColumnsKeepSelectedDateAndJournalAcrossRotation() throws {
        let app = launchApp()
        defer { app.terminate() }
        selectRootTab("Calendar", in: app)
        assertValue("Columns", of: element("calendar.layout", in: app))
        let densityHandle = app.calendarDensityHandle
        assertValue("Month", of: densityHandle)
        let monthHandleY = densityHandle.frame.midY
        app.dragCalendarHandle(by: 20)
        assertValue("Month", of: densityHandle)
        XCTAssertEqual(densityHandle.frame.midY, monthHandleY, accuracy: 1,
                       "A short resize drag must settle back to the month height")

        // A regular-width iPad starts at Month, including a drag that selects
        // Week in a compact layout. Year must still collapse back to Month.
        app.dragCalendarHandle(by: -230)
        assertValue("Month", of: densityHandle)
        XCTAssertEqual(densityHandle.frame.midY, monthHandleY, accuracy: 1)
        app.dragCalendarHandle(by: 117)
        assertValue("Year", of: densityHandle)
        XCTAssertTrue(app.scrollViews["orgenda.calendar.years"].isHittable)
        app.dragCalendarHandle(by: -347)
        assertValue("Month", of: densityHandle)
        XCTAssertEqual(densityHandle.frame.midY, monthHandleY, accuracy: 1,
                       "Collapsing Year must stop at Month on a regular-width iPad")

        let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'orgenda.calendar.day.'"))
        XCTAssertTrue(dates.firstMatch.waitForExistence(timeout: 5))
        let visibleDates = dates.allElementsBoundByIndex.filter(\.isHittable)
        let datesTrailingEdge = try XCTUnwrap(visibleDates.map(\.frame.maxX).max())
        let taskTitle = app.staticTexts["Review quarterly roadmap"]
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(taskTitle.isHittable)
        XCTAssertLessThan(datesTrailingEdge, taskTitle.frame.minX,
                          "A wide iPad window should place dates beside the timeline's visible tasks")
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].isHittable)
        attach(app, name: "iPad calendar agenda columns")

        let anotherDay = try XCTUnwrap(visibleDates.first { !$0.isSelected })
        let selectedIdentifier = anotherDay.identifier
        anotherDay.tap()
        assertVisibleSelectedDate(selectedIdentifier, in: app)
        let heading = element("orgenda.calendar.date.heading", in: app)
        let selectedHeading = heading.label

        tap(app.segmentedControls["calendar.content.picker"].buttons["Journal"])
        let journal = app.scrollViews["calendar.journal.timeline"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["orgenda.capture"].label, "New journal entry")
        rotate(.portrait, in: app)
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        assertVisibleSelectedDate(selectedIdentifier, in: app)
        XCTAssertEqual(heading.label, selectedHeading)
        XCTAssertEqual(app.buttons["orgenda.capture"].label, "New journal entry")

        rotate(.landscapeLeft, in: app)
        assertValue("Columns", of: element("calendar.layout", in: app))
        XCTAssertTrue(journal.isHittable)
        XCTAssertTrue(app.segmentedControls["calendar.content.picker"].buttons["Journal"].isSelected)
        assertVisibleSelectedDate(selectedIdentifier, in: app)
        tap(app.buttons["orgenda.capture"])
        XCTAssertTrue(app.textFields["journal.composer.title"].waitForExistence(timeout: 5))
        tap(app.buttons["Cancel"])
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        assertVisibleSelectedDate(selectedIdentifier, in: app)
        attach(app, name: "iPad calendar and journal columns")
    }

    func testCalendarDaysDoNotLeaveBlankRowsAfterScrollingAndResizing() throws {
        let app = launchApp(calendarLayoutFixture: true)
        defer { app.terminate() }
        toggleWorkspaceSidebar(in: app)
        selectRootTab("Calendar", in: app)
        let timeline = app.scrollViews["orgenda.agenda.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        let hideSidebar = app.buttons.matching(NSPredicate(format: "label == 'Hide Sidebar'")).firstMatch
        if hideSidebar.exists && hideSidebar.isHittable { hideSidebar.tap() }

        func assertCompactDay(_ offset: Int) throws {
            let first = app.staticTexts["Calendar day \(offset) first"]
            let second = app.staticTexts["Calendar day \(offset) second"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(second.waitForExistence(timeout: 5))
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(second.isHittable)
            XCTAssertLessThan(second.frame.minY - first.frame.maxY, 120,
                              "Consecutive tasks must not have blank row placeholders between them")
        }

        try assertCompactDay(0)
        let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 2, to: Date.now)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateButton = try XCTUnwrap(app.buttons.matching(
            identifier: "orgenda.calendar.day.\(formatter.string(from: day))"
        ).allElementsBoundByIndex.first { $0.isHittable })
        dateButton.tap()
        try assertCompactDay(2)
        for title in ["Daily morning routine", "Daily evening routine"] {
            let visibleOccurrence = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts.matching(NSPredicate(format: "label == %@", title))
                    .allElementsBoundByIndex.contains { $0.isHittable }
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [visibleOccurrence], timeout: 5), .completed,
                           "Repeated occurrences must render on each day instead of leaving blank rows")
        }
        attach(app, name: "Calendar renders every recurring occurrence without blank rows")
        for _ in 0..<3 { timeline.swipeUp(velocity: .slow) }
        for _ in 0..<2 { timeline.swipeDown(velocity: .slow) }
        rotate(.portrait, in: app)
        rotate(.landscapeLeft, in: app)
        tap(app.buttons["orgenda.calendar.today"])
        try assertCompactDay(0)
        attach(app, name: "Calendar day rows stay compact after scrolling and resizing")
    }

    func testRootNavigationAndSearchRemainUsableAcrossRotation() {
        let app = launchApp()
        defer { app.terminate() }
        selectRootTab("Calendar", in: app)
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].waitForExistence(timeout: 5))
        selectRootTab("Files", in: app)
        XCTAssertTrue(app.buttons["files.open.inbox.org"].waitForExistence(timeout: 5))
        selectRootTab("Dashboard", in: app)
        XCTAssertTrue(app.staticTexts["Plan iPad reading workflow"].waitForExistence(timeout: 5))
        selectRootTab("Search", in: app)

        let search = app.searchFields.firstMatch
        tap(search)
        dismissTypingIntroduction(in: app)
        search.typeText("workflow")
        let result = app.buttons["search.document.inbox.org"]
        tap(result)
        XCTAssertTrue(app.scrollViews["org.preview.scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Preview"].isSelected)
        rotate(.portrait, in: app)
        XCTAssertTrue(app.scrollViews["org.preview.scroll"].isHittable)
        tap(app.navigationBars.buttons["Search"])
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "workflow")

        rotate(.landscapeLeft, in: app)
        XCTAssertTrue(result.isHittable)
        XCTAssertEqual(search.value as? String, "workflow")
        attach(app, name: "iPad search preserves query after rotation")
    }

    func testAccessibilityTextUsesStackedCalendarInWideWindow() {
        let app = launchApp(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        selectRootTab("Calendar", in: app)
        assertValue("Stacked", of: element("calendar.layout", in: app))
        XCTAssertTrue(element("orgenda.calendar.date.heading", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.calendarDensityHandle.isHittable)
        assertValue("Month", of: app.calendarDensityHandle)
        app.dragCalendarHandle(by: -230)
        assertValue("Month", of: app.calendarDensityHandle)
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].isHittable)
        XCTAssertTrue(app.buttons["orgenda.capture"].isHittable)
        attach(app, name: "iPad calendar at accessibility text size")
    }

    func testCalendarViewportKeepsAllMonthRowsAndHandleVisible() {
        // The debug harness constrains the normal production root to a real
        // viewport. Each check reads rendered bounds; flags are only setup.
        let wideSize = CGSize(width: 760, height: 480)
        let wideApp = launchApp(viewportSize: wideSize, horizontalSizeClass: "regular")
        defer { wideApp.terminate() }
        let wideViewport = assertViewportSize(wideSize, in: wideApp)
        selectRootTab("Calendar", in: wideApp)
        XCTAssertTrue(element("calendar.layout", in: wideApp).waitForExistence(timeout: 5))
        // This fixture measures a 760-point calendar viewport with top tabs.
        // The workspace sidebar would otherwise consume part of that width.
        let hideSidebar = wideApp.buttons.matching(NSPredicate(format: "label == 'Hide Sidebar'")).firstMatch
        if hideSidebar.exists && hideSidebar.isHittable { hideSidebar.tap() }
        assertValue("Columns", of: element("calendar.layout", in: wideApp))
        assertValue("Month", of: wideApp.calendarDensityHandle)
        wideApp.dragCalendarHandle(by: -230)
        assertValue("Month", of: wideApp.calendarDensityHandle)
        // Native top tabs and the sidebar toggle can occupy two toolbar rows
        // in a short window. The outer page must let the full month scroll into
        // view instead of clipping its last row or resize handle.
        let handle = wideApp.calendarDensityHandle
        if !wideViewport.frame.contains(handle.frame) {
            let viewport = wideViewport.frame
            let origin = wideViewport.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: 8,
                dy: viewport.height - 40
            ))
            let distance = max(120, handle.frame.maxY - viewport.maxY + 8)
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        assertMonthFitsViewport(in: wideApp, viewportFrame: wideViewport.frame)
        attach(wideApp, name: "iPad month calendar in a 760 by 480 viewport")
    }

    func testNarrowCalendarViewportShowsFullMonthAndScrollsToAgenda() {
        let narrowSize = CGSize(width: 600, height: 600)
        let app = launchApp(viewportSize: narrowSize, horizontalSizeClass: "compact")
        defer { app.terminate() }
        let narrowViewport = assertViewportSize(narrowSize, in: app)
        selectRootTab("Calendar", in: app)
        assertValue("Stacked", of: element("calendar.layout", in: app))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let calendarTab = tabBar.buttons["Calendar"].firstMatch
        XCTAssertTrue(calendarTab.isHittable)
        XCTAssertGreaterThan(calendarTab.frame.minY, narrowViewport.frame.midY,
                             "Compact iPad navigation must use the bottom tab bar")
        XCTAssertTrue(narrowViewport.frame.insetBy(dx: -1, dy: -1).contains(calendarTab.frame))

        let heading = element("orgenda.calendar.date.heading", in: app)
        let selectedHeading = heading.label
        assertValue("Week", of: app.calendarDensityHandle)
        attach(app, name: "Compact iPad week calendar with bottom tabs")
        app.dragCalendarHandle(by: 230)
        assertValue("Month", of: app.calendarDensityHandle)
        app.dragCalendarHandle(by: 117)
        assertValue("Year", of: app.calendarDensityHandle)
        app.dragCalendarHandle(by: -347)
        assertValue("Week", of: app.calendarDensityHandle)
        XCTAssertEqual(heading.label, selectedHeading)
        app.dragCalendarHandle(by: 230)
        assertValue("Month", of: app.calendarDensityHandle)
        assertMonthFitsViewport(in: app, viewportFrame: narrowViewport.frame, requiresHittableTimeline: false)
        XCTAssertEqual(heading.label, selectedHeading)
        XCTAssertTrue(calendarTab.isHittable)
        attach(app, name: "Compact iPad full month in a 600 by 600 viewport")

        // Start below the month pager and to the right of the handle's touch
        // target. The calendar's AX bounds omit its transparent outer padding.
        let datePanel = element("calendar.datePanel", in: app)
        let originalPanelTop = datePanel.frame.minY
        let origin = narrowViewport.coordinate(withNormalizedOffset: .zero)
        let x = datePanel.frame.maxX - narrowViewport.frame.minX - 8
        let y = app.calendarDensityHandle.frame.midY - narrowViewport.frame.minY
        let start = origin.withOffset(CGVector(dx: x, dy: y))
        let end = origin.withOffset(CGVector(dx: x, dy: y - 200))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let task = app.staticTexts["Review quarterly roadmap"]
        let pageScrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            datePanel.frame.minY < originalPanelTop - 10 && task.isHittable
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [pageScrolled], timeout: 5), .completed,
                       "Scrolling the stacked page must reveal the agenda without changing the month")
        XCTAssertEqual(heading.label, selectedHeading)
        assertValue("Month", of: app.calendarDensityHandle)
        attach(app, name: "iPad narrow calendar viewport scrolled to agenda")
    }

    private func assertViewportSize(_ expected: CGSize, in app: XCUIApplication) -> XCUIElement {
        let viewport = element("ui-test.viewport", in: app)
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(viewport.frame.width - expected.width) <= 1
                && abs(viewport.frame.height - expected.height) <= 1
        }, object: viewport)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed,
                       "The production root must render at the requested viewport size")
        XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(viewport.frame),
                      "The test host window must be large enough to display the whole constrained viewport")
        return viewport
    }

    private func assertMonthFitsViewport(in app: XCUIApplication, viewportFrame: CGRect,
                                         requiresHittableTimeline: Bool = true) {
        let datePanel = element("calendar.datePanel", in: app)
        let timeline = app.scrollViews["orgenda.agenda.timeline"]
        XCTAssertTrue(datePanel.waitForExistence(timeout: 5))
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        if requiresHittableTimeline { XCTAssertTrue(timeline.isHittable) }
        let dateButtons = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'orgenda.calendar.day.'"
        ))
        let allRowsVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Set(dateButtons.allElementsBoundByIndex.filter(\.isHittable).map(\.identifier)).count == 42
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [allRowsVisible], timeout: 12), .completed,
                       "All six calendar rows must remain visible in the small window")

        let dates = dateButtons.allElementsBoundByIndex.filter(\.isHittable)
        var rowPositions: [CGFloat] = []
        for y in dates.map(\.frame.midY).sorted() {
            if rowPositions.last.map({ abs(y - $0) > 1 }) ?? true { rowPositions.append(y) }
        }
        XCTAssertEqual(rowPositions.count, 6, "The viewport must show all six month rows at once")
        let panelViewport = datePanel.frame.insetBy(dx: -1, dy: -1)
        let windowViewport = viewportFrame.insetBy(dx: -1, dy: -1)
        for date in dates {
            XCTAssertTrue(panelViewport.contains(date.frame), "\(date.identifier) is clipped by the date panel")
            XCTAssertTrue(windowViewport.contains(date.frame), "\(date.identifier) extends outside the window")
            assertDoesNotOverlap(date.frame, timeline.frame, "A date row must not be covered by the timeline")
        }
        let handle = app.calendarDensityHandle
        XCTAssertTrue(handle.isHittable)
        XCTAssertTrue(panelViewport.contains(handle.frame), "The density handle must remain inside the date panel")
        XCTAssertTrue(windowViewport.contains(handle.frame), "The density handle must remain inside the window")
        assertDoesNotOverlap(handle.frame, timeline.frame, "The timeline must not cover the density handle")
        assertDoesNotOverlap(datePanel.frame, timeline.frame, "Calendar and timeline viewports must not overlap")
    }

    private func launchApp(fileBrowserFixture: Bool = false, configuredAgenda: Bool = false,
                           calendarLayoutFixture: Bool = false, contentSize: String? = nil,
                           viewportSize: CGSize? = nil, horizontalSizeClass: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let appearance = ProcessInfo.processInfo.environment["TEST_RUNNER_ORGENDA_UI_TEST_APPEARANCE"]
            ?? ProcessInfo.processInfo.environment["ORGENDA_UI_TEST_APPEARANCE"] ?? "Light"
        app.launchArguments = [
            "--ui-test-workspace", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "-appearance", appearance
        ]
        if fileBrowserFixture { app.launchArguments += ["--file-browser-fixture"] }
        if configuredAgenda { app.launchArguments += ["--configured-agenda-fixture"] }
        if calendarLayoutFixture { app.launchArguments += ["--calendar-layout-fixture"] }
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        if let viewportSize {
            app.launchEnvironment["ORGENDA_UI_TEST_WINDOW_WIDTH"] = String(describing: viewportSize.width)
            app.launchEnvironment["ORGENDA_UI_TEST_WINDOW_HEIGHT"] = String(describing: viewportSize.height)
        }
        if let horizontalSizeClass {
            app.launchEnvironment["ORGENDA_UI_TEST_HORIZONTAL_SIZE_CLASS"] = horizontalSizeClass
        }
        app.launch()
        dismissMapsWidgetLocationPrompt()
        // Compact toolbars can move both Capture and the view menu into More.
        // Wait for indexed fixture content instead of a particular toolbar item.
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'agenda.item.open.'"
        )).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element("workspace.loading", in: app).waitForNonExistence(timeout: 5))
        rotate(.landscapeLeft, in: app)
        return app
    }

    private func selectRootTab(_ title: String, in app: XCUIApplication) {
        dismissMapsWidgetLocationPrompt()
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.exists && tab.isHittable {
            tab.tap()
            return
        }
        // iPadOS can expose top tabs outside a tab-bar node. Hittability is a
        // live element property and is not supported in an element-query predicate.
        let candidates = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
        if let target = candidates.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            target.tap()
            return
        }
        // iPadOS can restore the adaptable tab view as a sidebar between runs.
        // Close it only when the tabs are hidden; Files has its own sidebar.
        let hideSidebar = app.buttons.matching(NSPredicate(format: "label == 'Hide Sidebar'")).firstMatch
        if hideSidebar.exists && hideSidebar.isHittable { hideSidebar.tap() }
        if tab.exists && tab.isHittable {
            tab.tap()
        } else {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                candidates.allElementsBoundByIndex.contains(where: { $0.isHittable })
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            guard let target = candidates.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
                XCTFail("The \(title) navigation item must be reachable")
                return
            }
            target.tap()
        }
    }

    private func rotate(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        waitForStableWindow(in: app, orientation: orientation)
    }

    private func waitForStableWindow(in app: XCUIApplication, orientation: UIDeviceOrientation? = nil) {
        var previousFrame: CGRect?
        var unchangedSince = Date.now
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if let orientation, XCUIDevice.shared.orientation != orientation { return false }
            let window = app.windows.firstMatch
            guard window.exists else { return false }
            let frame = window.frame
            guard frame.width > 0, frame.height > 0 else { return false }
            if frame != previousFrame {
                previousFrame = frame
                unchangedSince = .now
                return false
            }
            return Date.now.timeIntervalSince(unchangedSince) >= 0.5
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The iPad app window must settle after orientation or window-size changes")
    }

    private func assertDoesNotOverlap(_ first: CGRect, _ second: CGRect, _ message: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let overlap = first.intersection(second)
        XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                      message, file: file, line: line)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        element.tap()
    }

    private func assertValue(_ value: String, of element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func assertVisibleSelectedDate(_ identifier: String, in app: XCUIApplication) {
        // Month pages can contain duplicate adjacent-month dates. Verify the
        // visible selected date rather than resolving an offscreen duplicate.
        let dates = app.buttons.matching(identifier: identifier)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            dates.allElementsBoundByIndex.contains { $0.isSelected && $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "The selected date must remain visible after navigation and rotation")
    }

    private func dismissTypingIntroduction(in app: XCUIApplication) {
        if app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Speed up your typing'")).firstMatch.exists {
            tap(app.buttons["Continue"])
        }
    }

    private func dismissMapsWidgetLocationPrompt() {
        // Fresh simulators can present this unrelated Maps widget permission
        // over the app. Only dismiss the observed prompt, always by denying it.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let promptText = NSPredicate(format: "label CONTAINS[c] 'Maps' AND label CONTAINS[c] 'location'")
        guard let alert = springboard.alerts.allElementsBoundByIndex.first(where: {
            $0.staticTexts.matching(promptText).firstMatch.exists
        }) else { return }
        let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"]))
            .firstMatch
        tap(deny)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        // App-level screenshots can crop the rotated iPad window into a buffer
        // with the wrong dimensions. Capture the device's full display instead.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
