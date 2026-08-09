import Carbon
import XCTest
@testable import ConnectionPrompter

final class GlobalHotkeyTests: XCTestCase {
    func testDefaultHotkeysRemainIndependentlyAddressable() {
        XCTAssertEqual(
            HotkeyDescriptor.defaults.map(\.displayName),
            ["⌥⌘↑", "⌥⌘↓", "⌥⌘←", "⌥⌘→", "⌥⌘X", "⌥⌘P"]
        )
        XCTAssertEqual(Set(HotkeyDescriptor.defaults.map(\.identifier)).count, 6)
    }

    func testSpeedHotkeysUseHorizontalArrowKeys() {
        let descriptors = HotkeyDescriptor.defaults.filter {
            $0.displayName == "⌥⌘←" || $0.displayName == "⌥⌘→"
        }

        XCTAssertEqual(
            descriptors.map(\.keyCode),
            [UInt32(kVK_LeftArrow), UInt32(kVK_RightArrow)]
        )
        XCTAssertTrue(descriptors.allSatisfy {
            $0.modifiers == UInt32(cmdKey | optionKey)
        })
    }
}
