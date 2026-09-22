import XCTest

final class DatePresentationUITests: XCTestCase {
    func testCalendarHandleResizesThroughWeekMonthAndYear() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["Calendar"].tap()

        let handle = app.calendarDensityHandle
        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["orgenda.calendar.density"].exists)
        XCTAssertEqual(handle.value as? String, "Week")
        let selectedDate = try XCTUnwrap(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'orgenda.calendar.day.' AND selected == true"
        )).allElementsBoundByIndex.first).identifier
        let weekY = handle.frame.midY

        handle.swipeLeft()
        app.dragCalendarHandle(by: 20)
        XCTAssertEqual(handle.value as? String, "Week")
        XCTAssertEqual(handle.frame.midY, weekY, accuracy: 1)

        app.dragCalendarHandle(by: 230)
        XCTAssertEqual(handle.value as? String, "Month")
        XCTAssertTrue(app.buttons[selectedDate].isSelected)
        let monthY = handle.frame.midY
        XCTAssertGreaterThan(monthY, weekY + 150)

        app.dragCalendarHandle(by: 117)
        XCTAssertEqual(handle.value as? String, "Year")
        XCTAssertGreaterThan(handle.frame.midY, monthY + 70)
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Calendar year expanded with drag handle"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let years = app.scrollViews["orgenda.calendar.years"]
        XCTAssertTrue(years.waitForExistence(timeout: 3))
        let currentYear = Date.now.formatted(.dateTime.year())
        let previousYear = Calendar.current.date(byAdding: .year, value: -1, to: .now)!.formatted(.dateTime.year())
        XCTAssertEqual(years.value as? String, currentYear)
        years.swipeDown()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", previousYear), object: years
        )], timeout: 3), .completed)
        XCTAssertEqual(handle.value as? String, "Year")
        let visibleMonths = years.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'orgenda.calendar.month.'"
        )).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visibleMonths.count, 12, visibleMonths.map(\.identifier).joined(separator: ", "))
        years.swipeUp()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", currentYear), object: years
        )], timeout: 3), .completed)

        app.dragCalendarHandle(by: -117)
        XCTAssertEqual(handle.value as? String, "Month")
        XCTAssertTrue(app.buttons[selectedDate].isSelected)
        app.dragCalendarHandle(by: -230)
        XCTAssertEqual(handle.value as? String, "Week")
        XCTAssertTrue(app.buttons[selectedDate].isSelected)
        XCTAssertEqual(handle.frame.midY, weekY, accuracy: 1)
    }

    func testCalendarJournalPagingKeepsDateAndCapturesOnSelectedDay() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        XCTAssertFalse(app.tabBars.buttons["Journal"].exists)
        app.tabBars.buttons["Calendar"].tap()
        let agenda = app.scrollViews["orgenda.agenda.timeline"]
        XCTAssertTrue(agenda.waitForExistence(timeout: 5))
        let heading = app.staticTexts["orgenda.calendar.date.heading"]
        let originalHeading = heading.label
        let originalHeaderFrame = heading.frame
        let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'orgenda.calendar.day.'"))
        let today = try XCTUnwrap(dates.allElementsBoundByIndex.first { $0.isSelected })
        let todayID = today.identifier
        let capture = app.buttons["orgenda.capture"]
        XCTAssertEqual(capture.label, "New task")
        XCTAssertFalse(app.segmentedControls["calendar.content.picker"].exists)

        // A horizontal drag starting on task content must page, not reveal
        // row actions or change the selected date in the fixed calendar.
        agenda.swipeLeft()
        let journal = app.scrollViews["calendar.journal.timeline"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        XCTAssertEqual(capture.label, "New journal entry")
        XCTAssertTrue(app.tabBars.buttons["Calendar"].isSelected)
        XCTAssertEqual(heading.label, originalHeading)
        XCTAssertEqual(heading.frame.minY, originalHeaderFrame.minY, accuracy: 1)
        XCTAssertEqual(heading.frame.height, originalHeaderFrame.height, accuracy: 1)
        XCTAssertTrue(app.buttons[todayID].isSelected)
        XCTAssertTrue(journal.staticTexts["Morning note"].exists)
        XCTAssertFalse(journal.staticTexts["What moved forward"].exists)
        XCTAssertFalse(app.buttons["agenda.swipe.more"].isHittable)

        let anotherDate = try XCTUnwrap(dates.allElementsBoundByIndex.first { !$0.isSelected && $0.isHittable })
        let anotherID = anotherDate.identifier
        anotherDate.tap()
        XCTAssertEqual(capture.label, "New journal entry")
        XCTAssertTrue(app.buttons[anotherID].isSelected)
        XCTAssertFalse(journal.staticTexts["Morning note"].exists)

        capture.tap()
        let title = app.textFields["journal.composer.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Calendar journal capture")
        let body = app.textViews["journal.composer.body"]
        body.tap()
        body.typeText("Only belongs to the selected day.")
        app.buttons["journal.composer.save"].tap()
        XCTAssertTrue(journal.staticTexts["Calendar journal capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[anotherID].isSelected)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Calendar journal timeline for selected day"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons[todayID].tap()
        XCTAssertTrue(journal.staticTexts["Morning note"].waitForExistence(timeout: 3))
        XCTAssertFalse(journal.staticTexts["Calendar journal capture"].exists)
        journal.swipeRight()
        XCTAssertTrue(agenda.waitForExistence(timeout: 5))
        XCTAssertEqual(capture.label, "New task")
        XCTAssertTrue(app.buttons[todayID].isSelected)
        capture.tap()
        XCTAssertTrue(app.textFields["item.editor.title"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        agenda.swipeLeft()
        XCTAssertTrue(journal.waitForExistence(timeout: 3))
        app.tabBars.buttons["Files"].tap()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertEqual(capture.label, "New journal entry")
        XCTAssertTrue(app.buttons[todayID].isSelected)
    }

    func testCalendarDateSelectionSurvivesTabSwitching() {
        verifyDatePresentation()
    }

    func testCalendarDateSelectionAtAccessibilitySize() {
        verifyDatePresentation(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    func testCalendarDateSelectionInDarkAppearance() {
        verifyDatePresentation(appearance: "Dark")
    }

    private func verifyDatePresentation(contentSize: String? = nil, appearance: String = "Light") {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo-workspace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-appearance", appearance
        ]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
        XCTAssertFalse(app.tabBars.buttons["Journal"].exists)
        let viewMenu = app.buttons["agenda.viewMenu"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))
        viewMenu.tap()
        XCTAssertFalse(app.buttons["agenda.mode.agenda"].exists)
        app.buttons["Overdue"].tap()
        XCTAssertEqual(viewMenu.value as? String, "Overdue")
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertFalse(viewMenu.exists)
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["orgenda.capture"].isHittable)
        let searchTab = app.tabBars.buttons["Search"]
        let filesTab = app.tabBars.buttons["Files"]
        XCTAssertGreaterThan(searchTab.frame.minX - filesTab.frame.maxX, 4)

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let week = calendar.dateInterval(of: .weekOfYear, for: today)!
        let neighbor = calendar.date(
            byAdding: .day, value: calendar.isDate(today, inSameDayAs: week.start) ? 1 : -1, to: today
        )!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: today)
        let neighborKey = formatter.string(from: neighbor)

        let calendarHeading = app.staticTexts["orgenda.calendar.date.heading"]
        XCTAssertTrue(calendarHeading.waitForExistence(timeout: 3))
        let todayHeadingLabel = calendarHeading.label
        XCTAssertLessThan(calendarHeading.frame.minY, app.frame.height * 0.16)
        XCTAssertTrue(app.buttons["orgenda.calendar.day.\(todayKey)"].isSelected)

        if contentSize != nil {
            let todayButton = app.buttons["orgenda.calendar.day.\(todayKey)"]
            XCTAssertTrue(app.scrollViews["orgenda.calendar.dates"].exists)
            // Large text gets wider cells instead of seven compressed columns.
            XCTAssertGreaterThan(todayButton.frame.width, 55)
            XCTAssertGreaterThan(todayButton.frame.height, 70)
            XCTAssertLessThan(todayButton.frame.height, 170)
            // A weekday wrapping into three rows used to push dates far below
            // the heading and leave almost no room for the agenda.
            XCTAssertLessThan(todayButton.frame.minY - calendarHeading.frame.maxY, 100)
            XCTAssertLessThan(calendarHeading.frame.height, 110)
            XCTAssertTrue(todayButton.label.contains(String(calendar.component(.year, from: today))))
        }

        let calendarNeighbor = app.buttons["orgenda.calendar.day.\(neighborKey)"]
        calendarNeighbor.tap()
        XCTAssertTrue(calendarNeighbor.isSelected)
        XCTAssertFalse(app.buttons["orgenda.calendar.day.\(todayKey)"].isSelected)
        let neighborHeadingLabel = calendarHeading.label

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))
        XCTAssertEqual(viewMenu.value as? String, "Overdue")
        XCTAssertFalse(app.calendarDensityHandle.exists)
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(calendarNeighbor.isSelected)
        XCTAssertEqual(calendarHeading.label, neighborHeadingLabel)
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].isHittable)
        app.buttons["orgenda.calendar.today"].tap()
        XCTAssertTrue(app.buttons["orgenda.calendar.day.\(todayKey)"].isSelected)
        XCTAssertEqual(calendarHeading.label, todayHeadingLabel)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar date header and separate Search tab - \(contentSize ?? appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)

        if contentSize != nil {
            verifyAccessibleMonthSelection(app, calendar: calendar, today: today, formatter: formatter)
        }
    }

    private func verifyAccessibleMonthSelection(
        _ app: XCUIApplication,
        calendar: Calendar,
        today: Date,
        formatter: DateFormatter
    ) {
        app.dragCalendarHandle(by: 96)
        XCTAssertEqual(app.calendarDensityHandle.value as? String, "Month")

        let monthStart = calendar.dateInterval(of: .month, for: today)!.start
        let lastDayOffset = calendar.range(of: .day, in: .month, for: today)!.count - 1
        let lastDate = calendar.date(byAdding: .day, value: lastDayOffset, to: monthStart)!
        let lastDateButton = app.buttons["orgenda.calendar.day.\(formatter.string(from: lastDate))"]
        let strip = app.scrollViews["orgenda.calendar.dates"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 3))
        for _ in 0..<12 where !lastDateButton.isHittable {
            strip.swipeLeft()
        }
        XCTAssertTrue(lastDateButton.isHittable, "Every date remains reachable at the largest text size")
        lastDateButton.tap()
        XCTAssertTrue(lastDateButton.isSelected)
        XCTAssertTrue(app.scrollViews["orgenda.agenda.timeline"].isHittable)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Month date strip at largest accessibility size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

final class ChineseLocalizationUITests: XCTestCase {
    func testSimplifiedChinese() {
        verifyChinese(language: "zh-Hans", locale: "zh_CN", calendar: "日历", files: "文件",
                      settings: "设置", workspace: "工作区与同步", appearance: "外观", search: "搜索")
    }

    func testTraditionalChinese() {
        verifyChinese(language: "zh-Hant", locale: "zh_TW", calendar: "日曆", files: "檔案",
                      settings: "設定", workspace: "工作區與同步", appearance: "外觀", search: "搜尋")
    }

    private func verifyChinese(language: String, locale: String, calendar: String, files: String,
                               settings: String, workspace: String, appearance: String, search: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo-workspace", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        let calendarTab = app.tabBars.buttons[calendar]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 10))
        calendarTab.tap()
        XCTAssertTrue(app.buttons["orgenda.capture"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["orgenda.capture"].label, language == "zh-Hans" ? "新建任务" : "新建任務")
        app.dragCalendarHandle(by: 230)
        XCTAssertEqual(app.calendarDensityHandle.value as? String, "月")
        attach(app, name: "\(language)-calendar")

        app.buttons["orgenda.capture"].tap()
        XCTAssertTrue(app.textFields["item.editor.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["取消"].exists)
        XCTAssertEqual(app.buttons["workflow.option.TODO"].label, language == "zh-Hans" ? "待办" : "待辦")
        attach(app, name: "\(language)-capture")
        app.buttons["取消"].tap()

        app.tabBars.buttons[files].tap()
        app.buttons["files.settings"].tap()
        XCTAssertTrue(app.navigationBars[settings].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.workspace"].label.contains(workspace))
        XCTAssertTrue(app.buttons["settings.appearance"].label.contains(appearance))
        attach(app, name: "\(language)-settings")
        app.buttons["settings.appearance"].tap()
        let dark = app.buttons["settings.appearance.dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        XCTAssertTrue(dark.label.contains("深色"))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settings.done"].tap()

        app.tabBars.buttons[search].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.placeholderValue?.contains(search) == true)
        searchField.typeText("orgenda_i18n_no_match")
        let noResults = language == "zh-Hans" ? "没有结果" : "沒有結果"
        XCTAssertTrue(app.staticTexts[noResults].waitForExistence(timeout: 5))
        let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "orgenda_i18n_no_match")).firstMatch
        XCTAssertTrue(explanation.label.contains("找不到"))
        attach(app, name: "\(language)-search")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}


extension XCUIApplication {
    var calendarDensityHandle: XCUIElement {
        descendants(matching: .any)["orgenda.calendar.density.handle"].firstMatch
    }

    func dragCalendarHandle(by distance: CGFloat) {
        let handle = calendarDensityHandle
        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
