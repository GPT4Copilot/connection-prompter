import XCTest
@testable import ConnectionPrompter

final class PrompterPreferencesTests: XCTestCase {
    func testPeopleViewOverridesLayoutWithoutChangingBackgroundTransparency() {
        var preferences = PrompterPreferences.standard
        preferences.backgroundTransparency = 0.82
        preferences.maximumLines = 4
        preferences.peopleView = true

        XCTAssertEqual(preferences.effectiveStyle.panelWidth, 520)
        XCTAssertEqual(preferences.effectiveStyle.panelHeight, 140)
        XCTAssertEqual(preferences.effectiveStyle.maximumLines, 2)
        XCTAssertEqual(
            preferences.effectiveStyle.backgroundTransparency,
            0.82,
            accuracy: 0.0001
        )

        preferences.peopleView = false

        XCTAssertEqual(
            preferences.effectiveStyle.backgroundTransparency,
            0.82,
            accuracy: 0.0001
        )
        XCTAssertEqual(preferences.effectiveStyle.maximumLines, 4)
    }

    func testOffscreenPanelFrameReturnsToTopCenterOfPrimaryScreen() {
        let offscreen = WindowFrame(x: 3_000, y: 2_000, width: 640, height: 180)
        let primary = WindowFrame(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(
            PanelFrameSanitizer.sanitize(offscreen, visibleScreens: [primary]),
            WindowFrame(x: 400, y: 708, width: 640, height: 180)
        )
    }

    func testVisiblePanelFrameIsPreserved() {
        let frame = WindowFrame(x: 120, y: 650, width: 620, height: 170)
        let screen = WindowFrame(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(PanelFrameSanitizer.sanitize(frame, visibleScreens: [screen]), frame)
    }
}
