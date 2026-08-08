import XCTest
@testable import ConnectionPrompter

final class DocumentGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testGroupsDocumentsIntoTodayYesterdayAndEarlier() {
        let now = date(2026, 8, 8, 12)
        let documents = [
            document("今天", updatedAt: date(2026, 8, 8, 8)),
            document("昨天", updatedAt: date(2026, 8, 7, 18)),
            document("更早", updatedAt: date(2026, 8, 1, 10))
        ]

        let groups = DocumentGrouping.group(
            documents,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["今天", "昨天", "更早"])
        XCTAssertEqual(groups.flatMap(\.documents).map(\.title), ["今天", "昨天", "更早"])
    }

    func testOmitsEmptyGroupsAndSortsEachGroupByMostRecentFirst() {
        let documents = [
            document("较早", updatedAt: date(2026, 8, 8, 8)),
            document("较新", updatedAt: date(2026, 8, 8, 10))
        ]

        let groups = DocumentGrouping.group(
            documents,
            now: date(2026, 8, 8, 12),
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["今天"])
        XCTAssertEqual(groups[0].documents.map(\.title), ["较新", "较早"])
    }

    private func document(_ title: String, updatedAt: Date) -> ScriptDocument {
        ScriptDocument(
            title: title,
            content: "正文",
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
