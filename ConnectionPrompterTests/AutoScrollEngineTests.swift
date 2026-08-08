import XCTest
@testable import ConnectionPrompter

final class AutoScrollEngineTests: XCTestCase {
    func testAdvancesByLinesPerSecondTimesLineHeight() {
        let result = AutoScrollEngine.advance(
            offset: 12,
            elapsed: 2,
            linesPerSecond: 0.5,
            lineHeight: 40,
            maximumOffset: 500
        )

        XCTAssertEqual(result.offset, 52, accuracy: 0.0001)
        XCTAssertFalse(result.reachedEnd)
    }

    func testClampsAtEndAndReportsCompletion() {
        let result = AutoScrollEngine.advance(
            offset: 90,
            elapsed: 1,
            linesPerSecond: 1,
            lineHeight: 20,
            maximumOffset: 100
        )

        XCTAssertEqual(result.offset, 100)
        XCTAssertTrue(result.reachedEnd)
    }

    func testNegativeElapsedAndSpeedNeverMoveBackward() {
        let result = AutoScrollEngine.advance(
            offset: 30,
            elapsed: -1,
            linesPerSecond: -2,
            lineHeight: 40,
            maximumOffset: 100
        )

        XCTAssertEqual(result.offset, 30)
        XCTAssertFalse(result.reachedEnd)
    }

    func testZeroLengthTrackDoesNotReportCompletion() {
        let result = AutoScrollEngine.advance(
            offset: 0,
            elapsed: 1,
            linesPerSecond: 1,
            lineHeight: 40,
            maximumOffset: 0
        )

        XCTAssertEqual(result.offset, 0)
        XCTAssertFalse(result.reachedEnd)
    }
}
