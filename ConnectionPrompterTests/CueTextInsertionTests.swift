import XCTest
@testable import ConnectionPrompter

final class CueTextInsertionTests: XCTestCase {
    func testCueInsertedIntoEmptyDocumentHasNoExtraBlankLines() {
        XCTAssertEqual(
            CueTextInsertion.inserting(.lookCamera, into: "", selectedRange: NSRange(location: 0, length: 0)),
            CueInsertionResult(text: "👁 看镜头", selectionLocation: 6)
        )
    }

    func testCueInsertedBetweenParagraphsKeepsOneBlankLineOnEachSide() {
        XCTAssertEqual(
            CueTextInsertion.inserting(.pause, into: "第一段\n\n第二段", selectedRange: NSRange(location: 5, length: 0)),
            CueInsertionResult(text: "第一段\n\n⏸ 停\n\n第二段", selectionLocation: 8)
        )
    }
}
