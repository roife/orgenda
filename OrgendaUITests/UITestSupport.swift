import XCTest

extension XCTestCase {
    func launchTestApp(_ arguments: [String] = [], workspace: String = "--demo-workspace",
                       appearance: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [workspace, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        if let appearance { app.launchArguments += ["-appearance", appearance] }
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    func attachScreenshot(_ name: String, screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIApplication {
    /// The system title menu exposes the current title as its button label.
    var agendaViewMenu: XCUIElement {
        navigationBars.buttons.matching(NSPredicate(format: "label IN %@", [
            "Dashboard", "Unscheduled", "Overdue", "Urgent actions", "Next actions",
            "Waiting", "Projects", "Someday"
        ])).firstMatch
    }

    /// Native iPad tabs can be exposed as cells rather than TabBar buttons.
    func selectRootTab(_ title: String) {
        let candidates = descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            candidates.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: self)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        candidates.allElementsBoundByIndex.first { $0.isHittable }?.tap()
    }

    func scrollSurface(_ identifier: String) -> XCUIElement {
        let matches = descendants(matching: .any).matching(identifier: identifier)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }
}
