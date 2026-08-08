import XCTest
@testable import ConnectionPrompter

final class GlobalHotkeyTests: XCTestCase {
    func testDefaultHotkeysRemainIndependentlyAddressable() {
        XCTAssertEqual(
            HotkeyDescriptor.defaults.map(\.action),
            [.previousPage, .nextPage, .toggleClickThrough, .togglePresenter]
        )
        XCTAssertEqual(Set(HotkeyDescriptor.defaults.map(\.identifier)).count, 4)
    }
}
