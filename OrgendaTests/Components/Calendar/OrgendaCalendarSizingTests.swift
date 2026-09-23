import XCTest
@testable import Orgenda

final class OrgendaCalendarSizingTests: XCTestCase {
    func testResizeSnapshotPreservesDatesAndInvalidatesWhenInputsChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22)))
        let monthStart = try XCTUnwrap(calendar.dateInterval(of: .month, for: selected)?.start)
        let marked: Set<String> = [selected.orgendaDayKey]
        let snapshot = OrgendaCalendarResizeSnapshot(month: selected, selectedDate: selected, markedDates: marked, calendar: calendar)
        XCTAssertEqual(snapshot.months.count, 12)
        XCTAssertTrue(snapshot.months.allSatisfy { $0.days.count == 42 })
        XCTAssertEqual(snapshot.monthData.days.filter(\.inMonth).count, 30)
        XCTAssertEqual(snapshot.monthData.days.filter(\.isSelected).map(\.number), ["22"])
        XCTAssertTrue(snapshot.monthData.days.first { $0.isSelected }!.isMarked)
        XCTAssertTrue(snapshot.matches(month: monthStart, selectedDate: selected, markedDates: marked, calendar: calendar))
        XCTAssertFalse(snapshot.matches(month: selected, selectedDate: selected, markedDates: [], calendar: calendar))
        XCTAssertFalse(snapshot.matches(month: selected, selectedDate: selected.addingTimeInterval(86400), markedDates: marked, calendar: calendar))
        XCTAssertFalse(snapshot.matches(month: calendar.date(byAdding: .month, value: 1, to: selected)!, selectedDate: selected, markedDates: marked, calendar: calendar))
        calendar.firstWeekday = 2
        XCTAssertFalse(snapshot.matches(month: selected, selectedDate: selected, markedDates: marked, calendar: calendar))
    }

    func testMonthYearTransitionMatchesAcceptedBrowserSamples() {
        // Reference samples from the exported JavaScript curves, including the
        // 66% S-curve midpoint and blur that persists through the second half.
        let samples: [(CGFloat, Double, CGFloat)] = [
            (0, 1, 5),
            (0.25, 0.6653125, 4.955313752051177),
            (0.5, 0.66, 4.0570051743037965),
            (0.75, 0.6496875, 1.4001145442412677),
            (0.7867, 0.6365420494089715, 1.0021306661561296),
            (1, 0, 0)
        ]
        for (progress, opacity, blur) in samples {
            XCTAssertEqual(OrgendaCalendarTransition.veilOpacity(at: progress), opacity, accuracy: 1e-9)
            XCTAssertEqual(OrgendaCalendarTransition.blurRadius(at: progress), blur, accuracy: 1e-9)
            XCTAssertEqual(OrgendaCalendarTransition.morphProgress(at: progress), progress, accuracy: 1e-9)
        }
        // Spring overshoot must never produce negative opacity or blur.
        XCTAssertEqual(OrgendaCalendarTransition.veilOpacity(at: -0.1), 1)
        XCTAssertEqual(OrgendaCalendarTransition.veilOpacity(at: 1.1), 0)
        XCTAssertEqual(OrgendaCalendarTransition.blurRadius(at: -0.1), 5)
        XCTAssertEqual(OrgendaCalendarTransition.blurRadius(at: 1.1), 0)
        XCTAssertEqual(OrgendaCalendarTransition.snapDuration, 0.32)
    }

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
