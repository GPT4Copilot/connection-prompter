import AppKit
import XCTest
@testable import ConnectionPrompter

final class PresenterResizeRegionTests: XCTestCase {
    func testResizeCursorRegionsCoverEveryEdgeAndCornerWithoutTheInterior() {
        let bounds = NSRect(x: 0, y: 0, width: 640, height: 180)

        let regions = PresenterResizeCursorRegion.regions(in: bounds, inset: 6)

        XCTAssertEqual(
            regions,
            [
                PresenterResizeCursorRegion(
                    edge: .topLeft,
                    rect: NSRect(x: 0, y: 0, width: 6, height: 6)
                ),
                PresenterResizeCursorRegion(
                    edge: .top,
                    rect: NSRect(x: 6, y: 0, width: 628, height: 6)
                ),
                PresenterResizeCursorRegion(
                    edge: .topRight,
                    rect: NSRect(x: 634, y: 0, width: 6, height: 6)
                ),
                PresenterResizeCursorRegion(
                    edge: .left,
                    rect: NSRect(x: 0, y: 6, width: 6, height: 168)
                ),
                PresenterResizeCursorRegion(
                    edge: .right,
                    rect: NSRect(x: 634, y: 6, width: 6, height: 168)
                ),
                PresenterResizeCursorRegion(
                    edge: .bottomLeft,
                    rect: NSRect(x: 0, y: 174, width: 6, height: 6)
                ),
                PresenterResizeCursorRegion(
                    edge: .bottom,
                    rect: NSRect(x: 6, y: 174, width: 628, height: 6)
                ),
                PresenterResizeCursorRegion(
                    edge: .bottomRight,
                    rect: NSRect(x: 634, y: 174, width: 6, height: 6)
                ),
            ]
        )
        XCTAssertFalse(
            regions.contains { $0.rect.contains(NSPoint(x: 320, y: 90)) }
        )
    }
}
