# Presenter Scroll Speed Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a continuously draggable speed control to the presenter toolbar, add global speed shortcuts, verify the interaction, and deliver Connection Prompter 1.2 as an arm64 macOS App.

**Architecture:** Keep `PrompterPreferences.autoScrollSpeed` as the single persisted value. Add focused speed mutation methods to `AppState`, forward intentions through `AppCoordinator`, bind both sliders and the new hotkeys to those methods, and keep the existing auto-scroll engine unchanged. Extend the existing XCTest and XCUITest suites before production changes, then build and validate the Release bundle.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Carbon global hotkeys, Observation, XCTest, XCUITest, Xcode 26.6, macOS 14+, Apple Silicon arm64.

## Global Constraints

- Work only from the existing `feature/v1-1` worktree at `.worktrees/v1-1`; do not implement against the 1.0 `main` source.
- Product name and bundle identifier remain `Connection Prompter` and `com.connectionprompter.app`.
- Minimum supported system remains macOS 14; the Release App contains arm64 only.
- Keep App Sandbox and hardened runtime enabled and add no network, microphone, camera, or Accessibility permission.
- Speed remains persisted in `PrompterPreferences.autoScrollSpeed`, with range 0.1–3.0 lines per second, default 0.5, and 0.1 increments.
- The toolbar control is a continuous horizontal drag slider; do not add decrease/increase point-click buttons.
- Speed changes must not start, pause, reset, or reposition automatic scrolling.
- Keep the settings-popover speed slider, People View, click-through, document library, transparency, existing shortcuts, and schema version 2 session format working.
- Release version is 1.2 with build number 3; delivery includes an `.app` and `.zip` under the workspace-root `dist/` directory.

## File Structure

- `ConnectionPrompter/AppState.swift`: snap, clamp, persist, and adjust the shared speed without rebuilding pages.
- `ConnectionPrompter/AppCoordinator.swift`: forward slider, menu, and global-hotkey speed changes to state.
- `ConnectionPrompter/EditorView.swift`: route the existing settings slider through the focused speed setter.
- `ConnectionPrompter/GlobalHotkeyManager.swift`: register and dispatch `⌥⌘←` and `⌥⌘→`.
- `ConnectionPrompter/ConnectionPrompterApp.swift`: expose the speed shortcuts in the Host menu.
- `ConnectionPrompter/PresenterView.swift`: render the compact presenter-toolbar speed slider and live value.
- `ConnectionPrompterTests/AppStateTests.swift`: verify speed normalization and scroll continuity.
- `ConnectionPrompterTests/GlobalHotkeyTests.swift`: verify shortcut descriptors remain unique and use horizontal arrows.
- `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`: drag the presenter slider and verify visible value feedback.
- `README.md`: document direct presenter speed control and both shortcuts.
- `ConnectionPrompter.xcodeproj/project.pbxproj`: set marketing version 1.2 and build number 3.

---

### Task 1: Focused Auto-Scroll Speed State API

**Files:**
- Modify: `ConnectionPrompter/AppState.swift:133-142`
- Modify: `ConnectionPrompter/AppCoordinator.swift:58-73`
- Modify: `ConnectionPrompter/EditorView.swift:285-289`
- Test: `ConnectionPrompterTests/AppStateTests.swift:108-178`

**Interfaces:**
- Produces: `AppState.setAutoScrollSpeed(_ speed: Double)`.
- Produces: `AppState.adjustAutoScrollSpeed(by amount: Double)`.
- Produces: matching forwarding methods on `AppCoordinator`.
- Preserves: `scrollOffset`, `autoScrollRunning`, current document, and current page when speed changes.

- [ ] **Step 1: Write failing state tests for normalization and scroll continuity**

Append these tests to `AppStateTests`:

```swift
@MainActor
func testAutoScrollSpeedSnapsToTenthsAndClampsToSupportedRange() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))

    state.setAutoScrollSpeed(0.56)
    XCTAssertEqual(state.preferences.autoScrollSpeed, 0.6, accuracy: 0.0001)

    state.setAutoScrollSpeed(-10)
    XCTAssertEqual(state.preferences.autoScrollSpeed, 0.1, accuracy: 0.0001)

    state.adjustAutoScrollSpeed(by: -0.1)
    XCTAssertEqual(state.preferences.autoScrollSpeed, 0.1, accuracy: 0.0001)

    state.setAutoScrollSpeed(10)
    state.adjustAutoScrollSpeed(by: 0.1)
    XCTAssertEqual(state.preferences.autoScrollSpeed, 3.0, accuracy: 0.0001)
}

@MainActor
func testChangingAutoScrollSpeedPreservesRunningStateAndPosition() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
    state.updateContent(String(repeating: "滚动内容 ", count: 200))
    state.setScrollMetrics(lineHeight: 40, maximumOffset: 500)
    state.startAutoScroll()
    state.advanceAutoScroll(elapsed: 1)
    let offsetBeforeChange = state.scrollOffset
    let pageBeforeChange = state.currentPage

    state.adjustAutoScrollSpeed(by: 0.1)

    XCTAssertEqual(state.preferences.autoScrollSpeed, 0.6, accuracy: 0.0001)
    XCTAssertEqual(state.scrollOffset, offsetBeforeChange, accuracy: 0.0001)
    XCTAssertEqual(state.currentPage, pageBeforeChange)
    XCTAssertTrue(state.autoScrollRunning)
}

@MainActor
func testAutoScrollSpeedChangeIsAutosaved() async throws {
    let store = FileSessionStore(directoryURL: directoryURL)
    let state = AppState(store: store)

    state.setAutoScrollSpeed(1.7)
    try await Task.sleep(for: .milliseconds(500))

    XCTAssertEqual(
        try store.load()?.preferences.autoScrollSpeed ?? -1,
        1.7,
        accuracy: 0.0001
    )
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -only-testing:ConnectionPrompterTests/AppStateTests/testAutoScrollSpeedSnapsToTenthsAndClampsToSupportedRange -only-testing:ConnectionPrompterTests/AppStateTests/testChangingAutoScrollSpeedPreservesRunningStateAndPosition -only-testing:ConnectionPrompterTests/AppStateTests/testAutoScrollSpeedChangeIsAutosaved test
```

Expected: compilation fails because `AppState` has no `setAutoScrollSpeed` or `adjustAutoScrollSpeed` member.

- [ ] **Step 3: Implement minimal speed mutation in `AppState`**

Add after `updatePreferences(_:)`:

```swift
func setAutoScrollSpeed(_ speed: Double) {
    let clamped = min(max(speed, 0.1), 3)
    preferences.autoScrollSpeed = (clamped * 10).rounded() / 10
    scheduleAutosave()
}

func adjustAutoScrollSpeed(by amount: Double) {
    setAutoScrollSpeed(preferences.autoScrollSpeed + amount)
}
```

Do not call `rebuildPages()` from either method.

- [ ] **Step 4: Add coordinator forwarding methods**

Add after `resetAutoScroll()` in `AppCoordinator`:

```swift
func setAutoScrollSpeed(_ speed: Double) {
    state.setAutoScrollSpeed(speed)
}

func adjustAutoScrollSpeed(by amount: Double) {
    state.adjustAutoScrollSpeed(by: amount)
}
```

- [ ] **Step 5: Route the settings slider through the focused setter**

Replace `autoScrollSpeedBinding` in `EditorView` with:

```swift
private var autoScrollSpeedBinding: Binding<Double> {
    Binding(
        get: { state.preferences.autoScrollSpeed },
        set: { value in coordinator.setAutoScrollSpeed(value) }
    )
}
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run the Step 2 command again. Expected: all three selected tests pass with no warnings or failures.

- [ ] **Step 7: Run all `AppStateTests`**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -only-testing:ConnectionPrompterTests/AppStateTests test
```

Expected: every `AppStateTests` test passes.

- [ ] **Step 8: Commit the state API**

```bash
git add ConnectionPrompter/AppState.swift ConnectionPrompter/AppCoordinator.swift ConnectionPrompter/EditorView.swift ConnectionPrompterTests/AppStateTests.swift
git commit -m "feat: centralize auto-scroll speed adjustment"
```

### Task 2: Global Speed Shortcuts and Host Menu

**Files:**
- Modify: `ConnectionPrompter/GlobalHotkeyManager.swift:4-47,140-153`
- Modify: `ConnectionPrompter/ConnectionPrompterApp.swift:24-39`
- Test: `ConnectionPrompterTests/GlobalHotkeyTests.swift:4-11`

**Interfaces:**
- Consumes: `AppCoordinator.adjustAutoScrollSpeed(by:)` from Task 1.
- Produces: `GlobalHotkeyAction.decreaseAutoScrollSpeed` with identifier 5.
- Produces: `GlobalHotkeyAction.increaseAutoScrollSpeed` with identifier 6.
- Produces: default descriptors `⌥⌘←` and `⌥⌘→` using Carbon left/right arrow key codes.

- [ ] **Step 1: Write a failing descriptor test without referring to missing enum cases**

Replace `GlobalHotkeyTests` with:

```swift
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
```

- [ ] **Step 2: Run the descriptor tests and verify RED**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -only-testing:ConnectionPrompterTests/GlobalHotkeyTests test
```

Expected: `testDefaultHotkeysRemainIndependentlyAddressable` fails because only four descriptors exist; `testSpeedHotkeysUseHorizontalArrowKeys` fails because the filtered array is empty.

- [ ] **Step 3: Add the speed actions and descriptors**

Extend `GlobalHotkeyAction` without changing existing raw values:

```swift
enum GlobalHotkeyAction: UInt32, Equatable, Sendable {
    case previousPage = 1
    case nextPage = 2
    case toggleClickThrough = 3
    case togglePresenter = 4
    case decreaseAutoScrollSpeed = 5
    case increaseAutoScrollSpeed = 6
}
```

Insert these descriptors after `.nextPage` in `HotkeyDescriptor.defaults`:

```swift
HotkeyDescriptor(
    action: .decreaseAutoScrollSpeed,
    identifier: GlobalHotkeyAction.decreaseAutoScrollSpeed.rawValue,
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: UInt32(cmdKey | optionKey),
    displayName: "⌥⌘←"
),
HotkeyDescriptor(
    action: .increaseAutoScrollSpeed,
    identifier: GlobalHotkeyAction.increaseAutoScrollSpeed.rawValue,
    keyCode: UInt32(kVK_RightArrow),
    modifiers: UInt32(cmdKey | optionKey),
    displayName: "⌥⌘→"
),
```

Add dispatch cases to `perform(actionID:)`:

```swift
case .decreaseAutoScrollSpeed:
    coordinator.adjustAutoScrollSpeed(by: -0.1)
case .increaseAutoScrollSpeed:
    coordinator.adjustAutoScrollSpeed(by: 0.1)
```

- [ ] **Step 4: Add matching commands to the Host menu**

Insert after the next-page command in `ConnectionPrompterApp`:

```swift
Divider()

Button("减慢自动滚动") {
    coordinator.adjustAutoScrollSpeed(by: -0.1)
}
.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

Button("加快自动滚动") {
    coordinator.adjustAutoScrollSpeed(by: 0.1)
}
.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
```

- [ ] **Step 5: Run hotkey tests and verify GREEN**

Run the Step 2 command again. Expected: both hotkey tests pass.

- [ ] **Step 6: Run all unit tests**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -only-testing:ConnectionPrompterTests test
```

Expected: all unit tests pass.

- [ ] **Step 7: Commit the shortcut support**

```bash
git add ConnectionPrompter/GlobalHotkeyManager.swift ConnectionPrompter/ConnectionPrompterApp.swift ConnectionPrompterTests/GlobalHotkeyTests.swift
git commit -m "feat: add global auto-scroll speed shortcuts"
```

### Task 3: Presenter Toolbar Drag Slider

**Files:**
- Modify: `ConnectionPrompter/PresenterView.swift:139-216`
- Test: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift:123-146`

**Interfaces:**
- Consumes: `AppCoordinator.setAutoScrollSpeed(_:)` from Task 1.
- Produces: accessibility identifier `主持滚动速度` on the presenter slider.
- Produces: accessibility identifier `主持滚动速度数值` on its one-decimal live value.
- Preserves: existing presenter buttons and automatic control hiding.

- [ ] **Step 1: Write a failing UI test for direct drag adjustment**

Append before `makeApp()` in `ConnectionPrompterLaunchTests`:

```swift
func testPresenterProvidesDraggableAutoScrollSpeedControl() {
    let app = makeApp()
    app.launch()
    app.activate()

    replaceText(
        in: app.textViews["文稿正文"],
        with: (1...12).map { "速度测试第\($0)行" }.joined(separator: "\n")
    )
    app.buttons["进入主持"].click()

    let presenter = app.dialogs["主持浮窗"]
    XCTAssertTrue(presenter.waitForExistence(timeout: 3))
    presenter.hover()

    let speedSlider = presenter.sliders["主持滚动速度"]
    let speedValue = presenter.staticTexts["主持滚动速度数值"]
    XCTAssertTrue(speedSlider.waitForExistence(timeout: 2))
    XCTAssertEqual(speedValue.label, "0.5")

    speedSlider.adjust(toNormalizedSliderPosition: 1)

    let updatedValue = NSPredicate(format: "label == %@", "3.0")
    expectation(for: updatedValue, evaluatedWith: speedValue)
    waitForExpectations(timeout: 2)
    attachScreenshot(of: presenter, named: "presenter-speed-control")
}
```

- [ ] **Step 2: Run the focused UI test and verify RED**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -resultBundlePath build/PresenterSpeedRed.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterProvidesDraggableAutoScrollSpeedControl test
```

Expected: the test fails because the presenter has no slider identified as `主持滚动速度`.

- [ ] **Step 3: Insert the speed control into the presenter toolbar**

In `controls`, place `autoScrollSpeedControl` immediately after the “回到开头” button and before the following separator:

```swift
controlButton("回到开头", systemImage: "backward.end.fill", action: coordinator.resetAutoScroll)
autoScrollSpeedControl
separator
```

Add this view near `separator`:

```swift
private var autoScrollSpeedControl: some View {
    HStack(spacing: 4) {
        Image(systemName: "speedometer")
            .font(.system(size: 11, weight: .semibold))
            .accessibilityHidden(true)

        Slider(value: autoScrollSpeedBinding, in: 0.1...3, step: 0.1)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 68)
            .accessibilityLabel("自动滚动速度")
            .accessibilityValue(
                String(format: "%.1f 行/秒", state.preferences.autoScrollSpeed)
            )
            .accessibilityIdentifier("主持滚动速度")

        Text(String(format: "%.1f", state.preferences.autoScrollSpeed))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .frame(width: 22, alignment: .trailing)
            .accessibilityIdentifier("主持滚动速度数值")
    }
    .frame(height: 24)
    .help("自动滚动速度（⌥⌘← / ⌥⌘→）")
}
```

Add the shared binding near `textAlignment`:

```swift
private var autoScrollSpeedBinding: Binding<Double> {
    Binding(
        get: { state.preferences.autoScrollSpeed },
        set: { value in coordinator.setAutoScrollSpeed(value) }
    )
}
```

- [ ] **Step 4: Run the focused UI test and verify GREEN**

Use a new result path so Xcode does not reject an existing bundle:

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -resultBundlePath build/PresenterSpeedGreen.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterProvidesDraggableAutoScrollSpeedControl test
```

Expected: the test passes and records `presenter-speed-control`.

- [ ] **Step 5: Export and inspect the presenter screenshot**

```bash
xcrun xcresulttool export attachments --path build/PresenterSpeedGreen.xcresult --output-path build/PresenterSpeedAttachments
```

Open the exported `presenter-speed-control` PNG and verify the slider thumb, track, speedometer, and `3.0` value are visible; verify the existing page, play/reset, People View, font, transparency, click-through, and return controls do not overlap or clip.

- [ ] **Step 6: Extend the UI test to cover People View width**

After the first screenshot assertion, click the People View button, verify the presenter becomes 520 pt wide within a 2 pt automation tolerance, hover again, and attach a second screenshot:

```swift
let peopleViewButton = presenter.buttons["People View"]
XCTAssertTrue(peopleViewButton.waitForExistence(timeout: 2))
peopleViewButton.click()
XCTAssertEqual(presenter.frame.width, 520, accuracy: 2)
presenter.hover()
XCTAssertTrue(presenter.sliders["主持滚动速度"].waitForExistence(timeout: 2))
attachScreenshot(of: presenter, named: "presenter-speed-control-people-view")
```

- [ ] **Step 7: Re-run the focused UI test after the People View assertion**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -resultBundlePath build/PresenterSpeedPeopleView.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterProvidesDraggableAutoScrollSpeedControl test
```

Expected: the test passes at both 640 pt and 520 pt presenter widths. The toolbar’s fixed contents total less than the 500 pt minimum panel width; after inspecting both screenshots, temporarily resize the presenter to its 500 pt minimum during the final release smoke check and verify the same non-overlap condition.

- [ ] **Step 8: Commit the presenter interaction**

```bash
git add ConnectionPrompter/PresenterView.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git commit -m "feat: add presenter auto-scroll speed slider"
```

### Task 4: Documentation, Regression Verification, and Release Packaging

**Files:**
- Modify: `README.md:1-25,42`
- Modify: `ConnectionPrompter.xcodeproj/project.pbxproj:322-360`
- Create ignored artifact: workspace-root `dist/Connection Prompter 1.2.app`
- Create ignored artifact: workspace-root `dist/Connection Prompter 1.2.zip`

**Interfaces:**
- Consumes: completed speed API, hotkeys, and presenter control from Tasks 1–3.
- Produces: bundle short version `1.2`, bundle version `3`, arm64 Release App, and zip archive.

- [ ] **Step 1: Update README product and shortcut documentation**

Change the title and direct-use path:

```markdown
# Connection Prompter V1.2

双击 `dist/Connection Prompter 1.2.app`。左侧文稿库可以新建、搜索、切换和删除稿件；右侧编辑器会自动保存当前内容。用空行分段，然后点击“进入主持”。旧版单文稿会在首次启动时自动迁移到文稿库。
```

Add this section before the existing V1.1 features:

```markdown
## V1.2 新功能

- 主持浮窗控制条可直接拖拽调整 0.1–3.0 行/秒的自动滚动速度，并实时显示当前值。
- `⌥⌘←` 和 `⌥⌘→` 可在任意应用或鼠标穿透状态下减慢、加快自动滚动。
```

Add these entries under “快捷键”:

```markdown
- `⌥⌘←`：全局减慢自动滚动 0.1 行/秒
- `⌥⌘→`：全局加快自动滚动 0.1 行/秒
```

Change the real-meeting speed check to:

```markdown
- 在主持浮条拖动速度滑杆，并使用 `⌥⌘←`、`⌥⌘→`，确认滚动实时变速且不会暂停或复位。
```

- [ ] **Step 2: Bump both app build configurations**

In the app target’s Debug and Release build settings, replace:

```text
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 1.1;
```

with:

```text
CURRENT_PROJECT_VERSION = 3;
MARKETING_VERSION = 1.2;
```

- [ ] **Step 3: Commit release metadata**

```bash
git add README.md ConnectionPrompter.xcodeproj/project.pbxproj
git commit -m "docs: prepare Connection Prompter 1.2"
```

- [ ] **Step 4: Run the full unit test suite in Release configuration**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -resultBundlePath build/ConnectionPrompter12Unit.xcresult -only-testing:ConnectionPrompterTests test
```

Expected: all unit tests pass with zero failures.

- [ ] **Step 5: Run the full UI suite against the Release app**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl -resultBundlePath build/ConnectionPrompter12UI.xcresult -only-testing:ConnectionPrompterUITests test
```

Expected: all UI tests pass, including launch, multi-document, transparency, auto-scroll, and direct presenter speed control.

- [ ] **Step 6: Record test totals and export final visual evidence**

```bash
xcrun xcresulttool get test-results summary --path build/ConnectionPrompter12Unit.xcresult
xcrun xcresulttool get test-results summary --path build/ConnectionPrompter12UI.xcresult
xcrun xcresulttool export attachments --path build/ConnectionPrompter12UI.xcresult --output-path build/ConnectionPrompter12UIAttachments
```

Inspect `presenter-speed-control` and `presenter-speed-control-people-view` attachments. Confirm the 640 pt and 520 pt layouts are unclipped. During the Release UI run, drag the presenter’s resizable edge to its 500 pt minimum and confirm every control remains visible before returning it to 640 pt.

- [ ] **Step 7: Produce a clean Release build**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-SpeedControl clean build
```

Expected: `** BUILD SUCCEEDED **` and the product exists at `build/DerivedData-SpeedControl/Build/Products/Release/Connection Prompter.app`.

- [ ] **Step 8: Copy the App and create the zip without overwriting an existing 1.2 artifact**

First verify both delivery paths are free:

```bash
test ! -e '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app'
test ! -e '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.zip'
```

Then package:

```bash
ditto 'build/DerivedData-SpeedControl/Build/Products/Release/Connection Prompter.app' '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app'
ditto -c -k --sequesterRsrc --keepParent '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app' '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.zip'
```

- [ ] **Step 9: Verify signature, sandbox, version, architecture, and archive**

```bash
codesign --verify --deep --strict --verbose=2 '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app'
codesign -d --entitlements :- '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app'
lipo -info '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app/Contents/MacOS/Connection Prompter'
plutil -extract CFBundleShortVersionString raw '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app/Contents/Info.plist'
plutil -extract CFBundleVersion raw '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.app/Contents/Info.plist'
unzip -t '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.zip'
shasum -a 256 '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.zip'
```

Expected: code signature verification succeeds; entitlements include `com.apple.security.app-sandbox = true`; `lipo` reports arm64 only; versions are `1.2` and `3`; archive test reports no errors; SHA-256 is recorded for delivery.

- [ ] **Step 10: Confirm a clean source state and retain ignored deliverables**

```bash
git status --short --branch
git log -5 --oneline --decorate
```

Expected: source worktree is clean and contains the four implementation/release commits after the design and plan commits. The `.app`, `.zip`, DerivedData, result bundles, and screenshots remain ignored rather than committed.
