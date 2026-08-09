# Presenter Slider Drag and Arrow Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the presenter speed slider from moving its window, add unmodified presenter-only arrow-key controls, and ship Connection Prompter 1.2.1.

**Architecture:** Disable AppKit's automatic background dragging and let a dedicated `PresenterPanel.sendEvent(_:)` call `NSWindow.performDrag(with:)` only below the top 50-point toolbar interaction band and outside the 6-point resize edge; the existing SwiftUI speed slider then receives its drag without moving the panel. Extend the existing local key monitor for unmodified left/right keys and reuse the existing coordinator methods, while leaving the global `⌥⌘` shortcuts unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`, `NSHostingView`), XCTest/XCUITest, Xcode 26 command-line build tools.

## Global Constraints

- Support macOS 14.0 and later on arm64 only.
- Preserve window movement from the presenter content/background while reserving the top 50 points for toolbar interaction.
- Keep the speed range at `0.1...3.0` with `0.1` increments.
- Unmodified arrow keys act only while the presenter is visible, the app receives keyboard input, no modifier is held, and a text editor is not the first responder.
- Preserve `Space` for next page and all six existing global `⌥⌘` hotkeys.
- Do not change toolbar layout, auto-scroll timing, document persistence, or click-through behavior.
- Package as version `1.2.1`, build `4`, without overwriting the 1.2 artifacts.

---

## File Structure

- Modify `ConnectionPrompter/PresenterPanelController.swift`: disable automatic background dragging, add explicit content/background dragging, and route unmodified left/right arrow keys.
- Modify `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`: physical pointer-drag and presenter arrow-key regression coverage.
- Modify `ConnectionPrompter.xcodeproj/project.pbxproj`: bump app marketing/build versions for 1.2.1.
- Modify `README.md`: describe the fixed slider behavior, local arrow keys, and new artifact path.

### Task 1: Keep Speed Slider Drag Inside the Control

**Files:**
- Modify: `ConnectionPrompter/PresenterPanelController.swift:33,164-190`
- Test: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift:147-182`

**Interfaces:**
- Consumes: `NSEvent.locationInWindow`, the existing 50-point toolbar layout, a 6-point resize edge, and `NSWindow.performDrag(with:)`.
- Produces: automatic background dragging disabled; explicit panel-level dragging below the toolbar and inside the resize edge; existing SwiftUI slider unchanged.

- [x] **Step 1: Replace the AX-only slider adjustment with a physical-drag regression test**

In `testPresenterProvidesDraggableAutoScrollSpeedControl`, replace the current `adjust(toNormalizedSliderPosition:)` block with a real pointer drag and frame assertions:

```swift
        let originalFrame = presenter.frame
        let dragStart = speedSlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
        )
        let dragEnd = speedSlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)
        )

        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

        let updatedValue = NSPredicate(format: "value != %@", "0.5")
        expectation(for: updatedValue, evaluatedWith: speedValue)
        waitForExpectations(timeout: 2)
        XCTAssertGreaterThan(Double(speedValue.value as? String ?? "") ?? 0, 0.5)
        XCTAssertEqual(presenter.frame.minX, originalFrame.minX, accuracy: 1)
        XCTAssertEqual(presenter.frame.minY, originalFrame.minY, accuracy: 1)
```

After the existing People View screenshot assertions, verify that a non-control presenter area still moves the window:

```swift
        let frameBeforeBackgroundDrag = presenter.frame
        let backgroundStart = presenter.coordinate(
            withNormalizedOffset: CGVector(dx: 0.90, dy: 0.82)
        )
        let backgroundEnd = presenter.coordinate(
            withNormalizedOffset: CGVector(dx: 0.80, dy: 0.82)
        )

        backgroundStart.press(forDuration: 0.1, thenDragTo: backgroundEnd)

        XCTAssertGreaterThan(
            abs(presenter.frame.minX - frameBeforeBackgroundDrag.minX),
            5
        )
```

- [x] **Step 2: Run the focused UI test and verify the red state**

Run:

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 -resultBundlePath build/PresenterSliderDragRed.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterProvidesDraggableAutoScrollSpeedControl test
```

Expected: FAIL because the physical speed-slider drag changes the presenter's `minX` and/or `minY`. The failure must be at a frame-equality assertion, not at launch or element lookup.

- [x] **Step 3: Replace automatic background dragging with an explicit content drag region**

In `PresenterPanelController.init`, set:

```swift
        panel.isMovableByWindowBackground = false
```

Add a dedicated panel subclass before `PresenterPanelController`:

```swift
private final class PresenterPanel: NSPanel {
    private let toolbarInteractionHeight: CGFloat = 50
    private let resizeHandleInset: CGFloat = 6

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView {
            let location = contentView.convert(event.locationInWindow, from: nil)
            let dragBounds = contentView.bounds.insetBy(
                dx: resizeHandleInset,
                dy: resizeHandleInset
            )
            if dragBounds.contains(location),
               location.y > toolbarInteractionHeight {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }
}
```

Construct `PresenterPanel` instead of `NSPanel`, and keep the existing SwiftUI slider unchanged.
`NSHostingView` uses a flipped coordinate system, so `location.y > 50` means the pointer is below the top toolbar.

- [x] **Step 4: Run the focused UI test and verify the green state**

Run:

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 -resultBundlePath build/PresenterSliderDragGreen.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterProvidesDraggableAutoScrollSpeedControl test
```

Expected: PASS. The speed value changes, the slider drag leaves the panel frame unchanged, People View still exposes the slider at 520 points, and the explicit content/background drag moves the panel.

- [x] **Step 5: Check the focused diff and commit**

```bash
git diff --check
git diff -- ConnectionPrompter/PresenterPanelController.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git add ConnectionPrompter/PresenterPanelController.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift docs/superpowers/specs/2026-08-09-presenter-slider-drag-and-arrow-shortcuts-design.md docs/superpowers/plans/2026-08-09-presenter-slider-drag-and-arrow-shortcuts.md
git commit -m "fix: keep presenter speed drag inside slider"
```

### Task 2: Add Presenter-Only Arrow Key Controls

**Files:**
- Modify: `ConnectionPrompter/PresenterPanelController.swift:131-151`
- Test: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`

**Interfaces:**
- Consumes: `AppCoordinator.adjustAutoScrollSpeed(by:)`, `previousPage()`, and `nextPage()`.
- Produces: local mappings `123 → -0.1`, `124 → +0.1`, `126 → previousPage`, and `125 → nextPage`; `49 → nextPage` remains unchanged.

- [ ] **Step 1: Add a failing end-to-end arrow-key test**

Add this UI test before the private helpers in `ConnectionPrompterLaunchTests`:

```swift
    func testPresenterArrowKeysAdjustSpeedAndNavigateText() {
        let app = makeApp()
        app.launch()
        app.activate()

        replaceText(
            in: app.textViews["文稿正文"],
            with: (1...12).map { "方向键测试第\($0)行" }.joined(separator: "\n")
        )
        app.buttons["进入主持"].click()

        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        presenter.hover()

        let speedValue = presenter.staticTexts["主持滚动速度数值"]
        XCTAssertEqual(speedValue.value as? String, "0.5")

        app.typeKey(.rightArrow, modifierFlags: [])
        let increased = NSPredicate(format: "value == %@", "0.6")
        expectation(for: increased, evaluatedWith: speedValue)
        waitForExpectations(timeout: 2)

        app.typeKey(.leftArrow, modifierFlags: [])
        let restoredSpeed = NSPredicate(format: "value == %@", "0.5")
        expectation(for: restoredSpeed, evaluatedWith: speedValue)
        waitForExpectations(timeout: 2)

        let firstLine = presenter.staticTexts["方向键测试第1行"]
        XCTAssertTrue(firstLine.waitForExistence(timeout: 2))
        let originalY = firstLine.frame.minY

        app.typeKey(.downArrow, modifierFlags: [])
        let movedUp = NSPredicate { _, _ in firstLine.frame.minY < originalY - 1 }
        expectation(for: movedUp, evaluatedWith: firstLine)
        waitForExpectations(timeout: 2)

        app.typeKey(.upArrow, modifierFlags: [])
        let returned = NSPredicate { _, _ in
            abs(firstLine.frame.minY - originalY) <= 2
        }
        expectation(for: returned, evaluatedWith: firstLine)
        waitForExpectations(timeout: 2)
    }
```

- [ ] **Step 2: Run the focused UI test and verify the red state**

Run:

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 -resultBundlePath build/PresenterArrowKeysRed.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterArrowKeysAdjustSpeedAndNavigateText test
```

Expected: FAIL while waiting for the speed value to become `0.6`, because key codes 123 and 124 are not handled yet. The existing up/down mappings are unchanged.

- [ ] **Step 3: Route left and right keys through the existing coordinator**

Update the switch in `PresenterPanelController.handleLocalNavigationKey`:

```swift
        switch keyCode {
        case 123:
            coordinator.adjustAutoScrollSpeed(by: -0.1)
            return true
        case 124:
            coordinator.adjustAutoScrollSpeed(by: 0.1)
            return true
        case 126:
            coordinator.previousPage()
            return true
        case 125, 49:
            coordinator.nextPage()
            return true
        default:
            return false
        }
```

Do not alter the existing presenter-visible, modifier, or text-responder guard.

- [ ] **Step 4: Run the focused UI test and verify the green state**

Run:

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 -resultBundlePath build/PresenterArrowKeysGreen.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterArrowKeysAdjustSpeedAndNavigateText test
```

Expected: PASS with speed `0.5 → 0.6 → 0.5`; down moves the first line upward and up restores its position.

- [ ] **Step 5: Run the existing speed-state unit tests**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 -resultBundlePath build/PresenterArrowStateGreen.xcresult -only-testing:ConnectionPrompterTests/AppStateTests/testAutoScrollSpeedSnapsToTenthsAndClampsToSupportedRange -only-testing:ConnectionPrompterTests/AppStateTests/testChangingAutoScrollSpeedPreservesRunningStateAndPosition test
```

Expected: both tests PASS, proving the new local key route keeps the existing clamp and no-reset behavior.

- [ ] **Step 6: Check the focused diff and commit**

```bash
git diff --check
git diff -- ConnectionPrompter/PresenterPanelController.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git add ConnectionPrompter/PresenterPanelController.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git commit -m "feat: add presenter arrow key controls"
```

### Task 3: Prepare and Verify Connection Prompter 1.2.1

**Files:**
- Modify: `ConnectionPrompter.xcodeproj/project.pbxproj:322-360`
- Modify: `README.md`
- Verify: all app, unit-test, and UI-test sources
- Create ignored artifacts: `dist/Connection Prompter 1.2.1.app`, `dist/Connection Prompter 1.2.1.zip`

**Interfaces:**
- Consumes: the completed slider and local-key behavior from Tasks 1 and 2.
- Produces: version `1.2.1`, build `4`, a verified arm64 Release app, and a tested ZIP archive.

- [ ] **Step 1: Update version metadata and user-facing documentation**

In both app build configurations in `ConnectionPrompter.xcodeproj/project.pbxproj`, set:

```text
CURRENT_PROJECT_VERSION = 4;
MARKETING_VERSION = 1.2.1;
```

Update the README title to `Connection Prompter V1.2.1`, the direct-use path to `dist/Connection Prompter 1.2.1.app`, and insert this section before V1.2:

```markdown
## V1.2.1 修复与快捷键

- 拖动主持浮窗的速度滑杆只会调整速度，不再带动整个窗口；拖动其他空白区域仍可移动浮窗。
- 主持状态下可用 `←`、`→` 每次减慢、加快 0.1 行/秒，并继续用 `↑`、`↓` 控制上一页、下一页。
```

Add these two entries before the global speed shortcuts in the shortcut list:

```markdown
- `←`：减慢自动滚动 0.1 行/秒（主持状态且未编辑文字时）
- `→`：加快自动滚动 0.1 行/秒（主持状态且未编辑文字时）
```

- [ ] **Step 2: Check and commit the release metadata**

```bash
git diff --check
git diff -- README.md ConnectionPrompter.xcodeproj/project.pbxproj
git add README.md ConnectionPrompter.xcodeproj/project.pbxproj
git commit -m "docs: prepare Connection Prompter 1.2.1"
```

- [ ] **Step 3: Run the complete Debug TestAction suite**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 -resultBundlePath build/ConnectionPrompter121Final.xcresult test
```

Expected: all unit and UI tests PASS with zero failures or skips.

- [ ] **Step 4: Read the exact final test summary and export screenshots**

```bash
xcrun xcresulttool get test-results summary --path build/ConnectionPrompter121Final.xcresult
xcrun xcresulttool export attachments --path build/ConnectionPrompter121Final.xcresult --output-path build/ConnectionPrompter121Attachments
```

Expected: result `Passed`, failed tests `0`, skipped tests `0`. Inspect the presenter speed screenshots and confirm the native slider remains aligned and unclipped at 640-point and 520-point toolbar widths.

- [ ] **Step 5: Produce a clean Release build**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-121 clean build
```

Expected: build exits 0 and creates `build/DerivedData-121/Build/Products/Release/Connection Prompter.app`.

- [ ] **Step 6: Copy and zip without overwriting 1.2**

First verify that neither destination exists:

```bash
test ! -e '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app'
test ! -e '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.zip'
```

Then create the artifacts:

```bash
ditto 'build/DerivedData-121/Build/Products/Release/Connection Prompter.app' '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app'
ditto -c -k --sequesterRsrc --keepParent '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app' '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.zip'
```

- [ ] **Step 7: Verify the delivered artifacts**

```bash
codesign --verify --deep --strict --verbose=2 '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app'
codesign -d --entitlements :- '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app'
plutil -extract CFBundleShortVersionString raw '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app/Contents/Info.plist'
plutil -extract CFBundleVersion raw '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app/Contents/Info.plist'
lipo -info '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.app/Contents/MacOS/Connection Prompter'
unzip -t '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.zip'
shasum -a 256 '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.1.zip'
```

Expected: code signature valid, sandbox entitlement present, version `1.2.1`, build `4`, architecture `arm64`, ZIP reports no errors, and a SHA-256 checksum is printed.

- [ ] **Step 8: Confirm the source handoff is clean**

```bash
git diff --check
git status --short --branch
git log -8 --oneline --decorate
```

Expected: the worktree is clean and the three implementation/release commits follow the design and plan commits. Build products, result bundles, and screenshots remain ignored.
