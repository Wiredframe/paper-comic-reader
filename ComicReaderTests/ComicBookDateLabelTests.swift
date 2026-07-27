//
//  ComicBookDateLabelTests.swift
//  ComicReaderTests
//
//  `dateLabel` promises that an out-of-range cover date is treated as absent rather than
//  trusted — but `Calendar.date(from:)` doesn't reject an invalid day, it silently rolls it
//  into the next month (30 February becomes 2 March). These tests pin the range check that
//  catches that before it reaches the label.
//
//  Expected strings are built with the same `.formatted()` calls `dateLabel` uses, rather than
//  hardcoded English text, so the tests hold regardless of the runner's locale.
//

import XCTest
@testable import ComicReader

final class ComicBookDateLabelTests: XCTestCase {

    private func book(year: Int?, month: Int? = nil, day: Int? = nil) -> ComicBook {
        let book = ComicBook(id: UUID(), title: "Test", fileName: "t.cbz", pageCount: 1, coverName: nil)
        book.year = year
        book.month = month
        book.day = day
        return book
    }

    private func dayLabel(_ year: Int, _ month: Int, _ day: Int) -> String {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
            .formatted(.dateTime.day().month(.wide).year())
    }

    private func monthLabel(_ year: Int, _ month: Int) -> String {
        Calendar.current.date(from: DateComponents(year: year, month: month))!
            .formatted(.dateTime.month(.wide).year())
    }

    func testFullDateFormats() {
        XCTAssertEqual(book(year: 1992, month: 4, day: 26).dateLabel, dayLabel(1992, 4, 26))
    }

    func testMonthOnlyFormats() {
        XCTAssertEqual(book(year: 1992, month: 4).dateLabel, monthLabel(1992, 4))
    }

    func testYearOnlyFormats() {
        XCTAssertEqual(book(year: 1992).dateLabel, "1992")
    }

    func testNoYearIsNil() {
        XCTAssertNil(book(year: nil, month: 4, day: 26).dateLabel)
    }

    func testOutOfRangeMonthFallsBackToYear() {
        XCTAssertEqual(book(year: 1992, month: 13, day: 1).dateLabel, "1992")
    }

    /// The bug this file exists to catch: day 30 in February isn't a real date, and must not
    /// silently become "2 March" — it should fall back to the month label instead.
    func testInvalidDayForMonthFallsBackToMonth() {
        XCTAssertEqual(book(year: 1993, month: 2, day: 30).dateLabel, monthLabel(1993, 2))
    }

    func testLeapYearFebruary29IsValid() {
        XCTAssertEqual(book(year: 1992, month: 2, day: 29).dateLabel, dayLabel(1992, 2, 29))
    }

    func testNonLeapYearFebruary29FallsBackToMonth() {
        XCTAssertEqual(book(year: 1993, month: 2, day: 29).dateLabel, monthLabel(1993, 2))
    }

    func testDayZeroFallsBackToMonth() {
        XCTAssertEqual(book(year: 1992, month: 4, day: 0).dateLabel, monthLabel(1992, 4))
    }
}
