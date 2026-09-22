import XCTest
@testable import Orgenda

final class OrgCalendarDatesTests: XCTestCase {
    private func calendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMonthGridRespectsFirstWeekdayAndCoversLeapDay() throws {
        for firstWeekday in [1, 2, 7] {
            let calendar = calendar(firstWeekday: firstWeekday)
            let dates = OrgCalendarDates(calendar: calendar)
            let february = date(2024, 2, 1, in: calendar)
            let grid = dates.daysInMonthGrid(for: february)

            XCTAssertEqual(grid.count, 42)
            XCTAssertEqual(Set(grid).count, 42)
            XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(grid.first)), firstWeekday)
            XCTAssertTrue(grid.contains(date(2024, 2, 29, in: calendar)))
            XCTAssertTrue(Set(dates.daysInMonth(for: february)).isSubset(of: Set(grid)))
        }
    }

    func testPreferredDayClampsInFebruaryAndRecoversInMarch() {
        let calendar = calendar()
        let dates = OrgCalendarDates(calendar: calendar)
        for (year, lastDay) in [(2024, 29), (2025, 28)] {
            XCTAssertEqual(dates.date(in: date(year, 2, 1, in: calendar), day: 31),
                           date(year, 2, lastDay, in: calendar))
            XCTAssertEqual(dates.date(in: date(year, 3, 1, in: calendar), day: 31),
                           date(year, 3, 31, in: calendar))
        }
    }

    func testWeekRemainsSevenLocalMidnightsAcrossDaylightSavingChange() throws {
        let calendar = calendar()
        let days = OrgCalendarDates(calendar: calendar).daysInWeek(containing: date(2026, 3, 8, in: calendar))
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, date(2026, 3, 2, in: calendar))
        XCTAssertEqual(days.last, date(2026, 3, 8, in: calendar))
        for day in days {
            XCTAssertEqual(day, calendar.startOfDay(for: day))
        }
        let month = OrgCalendarDates(calendar: calendar).daysInMonth(for: date(2026, 3, 1, in: calendar))
        XCTAssertEqual(month.count, 31)
        for (first, second) in zip(month, month.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: first, to: second).day, 1)
            XCTAssertEqual(second, calendar.startOfDay(for: second))
        }
    }
}
