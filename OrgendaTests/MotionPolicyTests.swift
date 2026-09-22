import XCTest
@testable import Orgenda

final class MotionPolicyTests: XCTestCase {
    func testDayKeysUseTheDisplayedCalendarDayInsteadOfUTC() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12)))
        let afternoon = try XCTUnwrap(calendar.date(byAdding: .hour, value: 14, to: midnight))
        XCTAssertEqual(midnight.orgendaDayKey(in: calendar), "2026-09-12")
        XCTAssertEqual(afternoon.orgendaDayKey(in: calendar), midnight.orgendaDayKey(in: calendar))

        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(midnight.orgendaDayKey(in: calendar), "2026-09-11")
    }

    func testContextualDatePresentationOmitsOnlyTheReferenceYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        let locale = Locale(identifier: "en_US")
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12)))
        let sameYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 30)))
        let otherYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 2, hour: 9, minute: 30)))

        let sameYearDate = OrgendaDatePresentation.date(
            sameYear, relativeTo: reference, locale: locale, calendar: calendar
        )
        let otherYearDate = OrgendaDatePresentation.date(
            otherYear, relativeTo: reference, locale: locale, calendar: calendar
        )
        XCTAssertFalse(sameYearDate.contains("2026"))
        XCTAssertTrue(otherYearDate.contains("2027"))
    }

    func testMonthHeadingAlwaysPlacesYearAfterLocalizedMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        for year in [2026, 2027] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: 9, day: 21)))
            for (language, month) in [("en_US", "Sep"), ("zh_CN", "9月"), ("zh_TW", "9月")] {
                XCTAssertEqual(OrgendaDatePresentation.monthHeading(
                    date, locale: Locale(identifier: language), calendar: calendar
                ), "\(month) \(year)")
            }
        }
    }

    func testContextualDatePresentationUsesNearbyDayNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        let locale = Locale(identifier: "en_US")
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12)))

        XCTAssertEqual(OrgendaDatePresentation.relativeDayName(
            for: today.adding(days: -1), relativeTo: today, locale: locale, calendar: calendar
        ), "Yesterday")
        XCTAssertEqual(OrgendaDatePresentation.relativeDayName(
            for: today, relativeTo: today, locale: locale, calendar: calendar
        ), "Today")
        XCTAssertEqual(OrgendaDatePresentation.relativeDayName(
            for: today.adding(days: 1), relativeTo: today, locale: locale, calendar: calendar
        ), "Tomorrow")
        XCTAssertNil(OrgendaDatePresentation.relativeDayName(
            for: today.adding(days: 2), relativeTo: today, locale: locale, calendar: calendar
        ))
    }

}
