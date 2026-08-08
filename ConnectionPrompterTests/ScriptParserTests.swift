import XCTest
@testable import ConnectionPrompter

final class ScriptParserTests: XCTestCase {
    func testParsesCRLFParagraphsAndCanonicalCue() {
        let content = "第一段\r\n继续说明\r\n\r\n[PAUSE]\r\n\r\n最后一段"

        let blocks = ScriptParser().parse(content)

        XCTAssertEqual(
            blocks,
            [
                .text("第一段\n继续说明"),
                .cue(.pause),
                .text("最后一段")
            ]
        )
    }

    func testRecognizesEveryCueFromChineseLabelsAndCanonicalMarkers() {
        let fixtures: [(String, CueKind)] = [
            ("👁 看镜头", .lookCamera),
            ("[LOOK_CAMERA]", .lookCamera),
            ("⏸ 停", .pause),
            ("[PAUSE]", .pause),
            ("🙂 笑", .smile),
            ("[SMILE]", .smile),
            ("🙋 邀请回应", .inviteResponse),
            ("[INVITE_RESPONSE]", .inviteResponse),
            ("❤️ 看大家", .watchPeople),
            ("[WATCH_PEOPLE]", .watchPeople)
        ]

        for (source, expectedCue) in fixtures {
            XCTAssertEqual(ScriptParser().parse(source), [.cue(expectedCue)], source)
        }
    }

    func testTreatsWhitespaceOnlyLinesAsParagraphBreaks() {
        let content = "  第一段  \n   \n\n第二段\n第三行  "

        XCTAssertEqual(
            ScriptParser().parse(content),
            [.text("第一段"), .text("第二段\n第三行")]
        )
    }

    func testWhitespaceOnlyDocumentHasNoBlocks() {
        XCTAssertEqual(ScriptParser().parse(" \n\t\n "), [])
    }
}
