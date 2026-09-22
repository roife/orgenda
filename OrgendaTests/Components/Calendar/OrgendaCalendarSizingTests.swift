import XCTest
@testable import Orgenda

final class OrgendaCalendarSizingTests: XCTestCase {
    func testResizeKeepsAllDensitiesReachableAtRegularAndAccessibilitySizes() {
        for usesAccessibilityText in [false, true] {
            let sizing = OrgendaCalendarSizing(
                usesAccessibilityText: usesAccessibilityText,
                dayNumberSize: usesAccessibilityText ? 44 : 17,
                weekdayLineHeight: usesAccessibilityText ? 36 : 14,
                monthLabelHeight: usesAccessibilityText ? 44 : 18
            )
            let stops = OrgendaCalendar.Density.allCases.map { sizing.dragPosition(for: $0) }
            XCTAssertLessThan(stops[0], stops[1])
            XCTAssertLessThan(stops[1], stops[2])
            for density in OrgendaCalendar.Density.allCases {
                let stop = sizing.dragPosition(for: density)
                XCTAssertEqual(sizing.density(at: stop), density)
                XCTAssertEqual(sizing.selectionHeight(at: stop), sizing.selectionHeight(for: density), accuracy: 0.001)
            }
            for position in stride(from: 0.0, through: Double(stops[2]), by: 1) {
                let height = sizing.selectionHeight(at: position)
                XCTAssertTrue(height.isFinite)
                XCTAssertGreaterThan(height, 0)
            }
        }
    }
}
