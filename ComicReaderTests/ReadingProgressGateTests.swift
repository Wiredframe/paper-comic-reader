//
//  ReadingProgressGateTests.swift
//  ComicReaderTests
//
//  A comic opened on a bookmark (or "Comic" from the start) and closed again without turning a
//  page must not move the resume page or mark the comic read. Turning a page makes it progress.
//

import XCTest
@testable import ComicReader

@MainActor
final class ReadingProgressGateTests: XCTestCase {

    func testResumeOpenAlwaysCounts() {
        let gate = ReadingProgressGate()
        gate.opened(at: 39)
        XCTAssertTrue(gate.countsAsProgress(peek: false))
    }

    func testPeekWithoutMovingDoesNotCount() {
        let gate = ReadingProgressGate()
        gate.opened(at: 2)
        gate.reached(2)          // the reader's own first report of the opening page
        XCTAssertFalse(gate.countsAsProgress(peek: true))
    }

    func testPeekCountsOnceThePageChanges() {
        let gate = ReadingProgressGate()
        gate.opened(at: 2)
        gate.reached(3)
        XCTAssertTrue(gate.countsAsProgress(peek: true))
        gate.reached(2)          // turning back to the opening page is still a moved session
        XCTAssertTrue(gate.countsAsProgress(peek: true))
    }

    func testGridJumpCounts() {
        let gate = ReadingProgressGate()
        gate.opened(at: 0)
        gate.moved()
        XCTAssertTrue(gate.countsAsProgress(peek: true))
    }

    func testReportsBeforeTheOpenDoNotCount() {
        let gate = ReadingProgressGate()
        gate.reached(5)
        gate.opened(at: 5)
        XCTAssertFalse(gate.countsAsProgress(peek: true))
    }
}
