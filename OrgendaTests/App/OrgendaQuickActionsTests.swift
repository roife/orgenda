import UIKit
import XCTest
@testable import Orgenda

@MainActor
final class OrgendaQuickActionsTests: XCTestCase {
    func testEveryInstalledShortcutCanBeRouted() throws {
        let shortcuts = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        let types = shortcuts.compactMap { $0["UIApplicationShortcutItemType"] as? String }
        XCTAssertEqual(Set(types), Set(OrgendaQuickAction.allCases.map(\.rawValue)))
        XCTAssertEqual(types.count, 4)
        let delegate = OrgendaSceneDelegate()
        for type in types {
            XCTAssertTrue(delegate.accept(UIApplicationShortcutItem(type: type, localizedTitle: "Action")))
            XCTAssertEqual(delegate.pendingAction?.action.rawValue, type)
        }
    }

    func testUnknownShortcutDoesNotReplacePendingRequestAndRepeatedActionsGetNewIDs() throws {
        let delegate = OrgendaSceneDelegate()
        let shortcut = UIApplicationShortcutItem(type: OrgendaQuickAction.newTask.rawValue, localizedTitle: "New task")
        XCTAssertTrue(delegate.accept(shortcut))
        let firstID = try XCTUnwrap(delegate.pendingAction?.id)
        XCTAssertFalse(delegate.accept(UIApplicationShortcutItem(type: "unknown", localizedTitle: "Unknown")))
        XCTAssertEqual(delegate.pendingAction?.id, firstID)
        XCTAssertTrue(delegate.accept(shortcut))
        XCTAssertNotEqual(delegate.pendingAction?.id, firstID)
    }
}
