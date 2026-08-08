import XCTest
@testable import ConnectionPrompter

final class PageComposerTests: XCTestCase {
    func testLongBlockIsPaginatedWithoutExceedingLineLimit() {
        let breaker = FixtureLineBreaker(linesByText: [
            "长段": ["第一行", "第二行", "第三行", "第四行", "第五行"]
        ])
        let layout = PrompterLayout(width: 560, fontSize: 32, lineHeight: 1.35, maximumLines: 3)

        let pages = PageComposer(lineBreaker: breaker).compose(
            blocks: [.text("长段")],
            layout: layout
        )

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].lines.map(\.text), ["第一行", "第二行", "第三行"])
        XCTAssertEqual(pages[1].lines.map(\.text), ["第四行", "第五行"])
        XCTAssertTrue(pages.allSatisfy { $0.lines.count <= 3 })
    }

    func testShortCurrentBlockUsesPreviousAndNextContext() {
        let breaker = FixtureLineBreaker(linesByText: [
            "上一段": ["上一段"],
            "当前段": ["当前段"],
            "下一段": ["下一段"]
        ])
        let layout = PrompterLayout(width: 560, fontSize: 32, lineHeight: 1.35, maximumLines: 3)

        let pages = PageComposer(lineBreaker: breaker).compose(
            blocks: [.text("上一段"), .text("当前段"), .text("下一段")],
            layout: layout
        )
        let currentPage = try! XCTUnwrap(pages.first(where: { $0.blockIndex == 1 }))

        XCTAssertEqual(
            currentPage.lines,
            [
                PrompterLine(text: "上一段", role: .previous),
                PrompterLine(text: "当前段", role: .current),
                PrompterLine(text: "下一段", role: .next)
            ]
        )
    }

    func testCueAlwaysOccupiesAStandalonePage() {
        let layout = PrompterLayout(width: 560, fontSize: 32, lineHeight: 1.35, maximumLines: 3)

        let pages = PageComposer(lineBreaker: FixtureLineBreaker(linesByText: [:])).compose(
            blocks: [.cue(.lookCamera)],
            layout: layout
        )

        XCTAssertEqual(
            pages,
            [PrompterPage(blockIndex: 0, pageInBlock: 0, lines: [
                PrompterLine(text: "👁 看镜头", role: .cue)
            ])]
        )
    }

    func testNavigationStopsAtFirstAndLastPage() {
        XCTAssertEqual(PageNavigation.previous(from: 0, pageCount: 3), 0)
        XCTAssertEqual(PageNavigation.next(from: 0, pageCount: 3), 1)
        XCTAssertEqual(PageNavigation.next(from: 2, pageCount: 3), 2)
        XCTAssertEqual(PageNavigation.clamp(8, pageCount: 3), 2)
        XCTAssertEqual(PageNavigation.clamp(2, pageCount: 0), 0)
    }

    func testContinuousTrackKeepsCueStandaloneAndTextInSourceOrder() {
        let breaker = FixtureLineBreaker(linesByText: [
            "第一段": ["第一行", "第二行"],
            "第二段": ["第三行"]
        ])
        let layout = PrompterLayout(
            width: 560,
            fontSize: 32,
            lineHeight: 1.35,
            maximumLines: 3
        )

        let track = PrompterTrackComposer(lineBreaker: breaker).compose(
            blocks: [.text("第一段"), .cue(.pause), .text("第二段")],
            layout: layout
        )

        XCTAssertEqual(track.lines.map(\.text), ["第一行", "第二行", "⏸ 停", "第三行"])
        XCTAssertEqual(track.lines.map(\.role), [.current, .current, .cue, .current])
    }
}

private struct FixtureLineBreaker: TextLineBreaking {
    let linesByText: [String: [String]]

    func lines(for text: String, layout: PrompterLayout) -> [String] {
        linesByText[text, default: [text]]
    }
}
