import XCTest
@testable import ConnectionPrompter

final class PresenterBackgroundStyleTests: XCTestCase {
    func testOneHundredPercentTransparencyRemovesEveryBackgroundLayer() {
        let style = PresenterBackgroundStyle(
            transparency: 1,
            reduceTransparency: false,
            blurEnabled: true
        )

        XCTAssertEqual(style.materialOpacity, 0)
        XCTAssertEqual(style.blackFillOpacity, 0)
        XCTAssertEqual(style.chromeOpacity, 0)
    }

    func testFullTransparencyStrengthensTextContrastWithoutRestoringBackground() {
        let style = PresenterBackgroundStyle(
            transparency: 1,
            reduceTransparency: false,
            blurEnabled: true
        )

        XCTAssertGreaterThanOrEqual(style.textShadowOpacity, 0.8)
        XCTAssertGreaterThanOrEqual(style.textShadowRadius, 3)
        XCTAssertEqual(style.blackFillOpacity, 0)
    }

    func testZeroPercentTransparencyIsOpaque() {
        let style = PresenterBackgroundStyle(
            transparency: 0,
            reduceTransparency: false,
            blurEnabled: true
        )

        XCTAssertEqual(style.materialOpacity, 1)
        XCTAssertEqual(style.blackFillOpacity, 0.72, accuracy: 0.0001)
        XCTAssertEqual(style.chromeOpacity, 1)
    }

    func testReducedTransparencyDoesNotForceAnOpaqueBackground() {
        let style = PresenterBackgroundStyle(
            transparency: 0.8,
            reduceTransparency: true,
            blurEnabled: true
        )

        XCTAssertEqual(style.materialOpacity, 0)
        XCTAssertEqual(style.blackFillOpacity, 0.2, accuracy: 0.0001)
        XCTAssertEqual(style.chromeOpacity, 0.2, accuracy: 0.0001)
    }

    func testTransparencyIsClampedToZeroThroughOne() {
        XCTAssertEqual(
            PresenterBackgroundStyle(
                transparency: -1,
                reduceTransparency: false,
                blurEnabled: false
            ).blackFillOpacity,
            1
        )
        XCTAssertEqual(
            PresenterBackgroundStyle(
                transparency: 2,
                reduceTransparency: false,
                blurEnabled: false
            ).blackFillOpacity,
            0
        )
    }
}
