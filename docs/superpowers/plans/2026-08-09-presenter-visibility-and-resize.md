# Presenter Visibility and Resize Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore live transparency in People View, show resize cursors on the presenter perimeter, add a default-on “hide editor while presenting” checkbox, and ship Connection Prompter 1.2.2.

**Architecture:** Keep one transparency source in `PrompterPreferences` and remove only People View's fixed opacity override. Reuse the existing six-point resize perimeter for non-overlapping AppKit cursor rectangles. Persist a compact optional scene preference whose missing value means `true`, and let `AppCoordinator` restore only an editor window it automatically hid.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`, `NSCursor`, `NSWindow`), Observation, Codable JSON sessions, XCTest/XCUITest, Xcode 26 command-line tools.

## Global Constraints

- Support macOS 14.0 and later on arm64 only.
- Keep one 0%...100% background-transparency value for standard and People View modes.
- Preserve the current background-blur, Reduce Transparency, text-shadow, click-through, speed, keyboard, drag, and resize behavior.
- Keep the top 50-point toolbar interaction band and six-point resize perimeter unchanged.
- Place one standard checkbox labeled `主持时隐藏编辑页` immediately after `自动保存`; default it to enabled for new and upgraded sessions.
- A scene-setting change made while presenting takes effect the next time presentation starts.
- Restore the editor automatically only when this presentation flow hid it; the explicit `返回编辑器` action always restores it.
- Package version `1.2.2`, build `5`, without overwriting 1.2.1 artifacts.

---

## File Structure

- Modify `ConnectionPrompter/SessionModels.swift`: share transparency across display modes and store the scene preference with an upgrade-safe default.
- Modify `ConnectionPrompter/PresenterPanelController.swift`: define/test resize cursor rectangles and register system cursors.
- Modify `ConnectionPrompter/EditorView.swift`: add the compact persisted checkbox beside the autosave label.
- Modify `ConnectionPrompter/AppCoordinator.swift`: hide and restore the editor window around presentation.
- Modify `ConnectionPrompterTests/PrompterPreferencesTests.swift`: cover People View transparency and the scene default.
- Create `ConnectionPrompterTests/PresenterResizeRegionTests.swift`: cover all edge/corner cursor rectangles and the untouched interior.
- Modify `ConnectionPrompterTests/SessionStoreTests.swift`: cover missing-field migration and a persisted disabled choice.
- Modify `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`: cover checkbox UI, editor hiding/restoration, keep-visible mode, and People View visual evidence.
- Modify `ConnectionPrompter.xcodeproj/project.pbxproj`: set version 1.2.2 and build 5.
- Modify `README.md`: document the fixes, checkbox, and artifact paths.

### Task 1: Make People View Respect Background Transparency

**Files:**
- Modify: `ConnectionPrompter/SessionModels.swift:175-189`
- Modify: `ConnectionPrompterTests/PrompterPreferencesTests.swift:5-21`
- Modify: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift:103-120`

**Interfaces:**
- Consumes: `PrompterPreferences.backgroundTransparency` in `0...1` and `peopleView`.
- Produces: `EffectivePrompterStyle.backgroundTransparency` equal to the stored setting in both display modes.

- [ ] **Step 1: Change the People View regression expectation before production code**

Replace the existing People View preference test with:

```swift
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
```

In `testPresenterSupportsFullTransparency`, replace the final presenter assertions with:

```swift
        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["完全透明时文字仍然清楚"].exists)
        attachScreenScreenshot(named: "fully-transparent-presenter")

        presenter.hover()
        let peopleViewButton = presenter.buttons["People View"]
        XCTAssertTrue(peopleViewButton.waitForExistence(timeout: 2))
        peopleViewButton.click()
        XCTAssertEqual(presenter.frame.width, 520, accuracy: 2)
        attachScreenScreenshot(named: "fully-transparent-presenter-people-view")
```

- [ ] **Step 2: Run the focused preference test and verify RED**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PeopleViewTransparencyRed.xcresult -only-testing:ConnectionPrompterTests/PrompterPreferencesTests/testPeopleViewOverridesLayoutWithoutChangingBackgroundTransparency test
```

Expected: FAIL because People View returns `0.55` instead of the hand-derived `0.82`.

- [ ] **Step 3: Remove the fixed People View opacity**

In the People View branch of `effectiveStyle`, replace the fixed opacity with the same clamped expression used by the standard branch:

```swift
            return EffectivePrompterStyle(
                panelWidth: 520,
                panelHeight: 140,
                maximumLines: 2,
                backgroundOpacity: 1 - min(max(backgroundTransparency, 0), 1)
            )
```

Do not change `PresenterBackgroundStyle`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PeopleViewTransparencyGreen.xcresult -only-testing:ConnectionPrompterTests/PrompterPreferencesTests/testPeopleViewOverridesLayoutWithoutChangingBackgroundTransparency -only-testing:ConnectionPrompterTests/PresenterBackgroundStyleTests -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterSupportsFullTransparency test
```

Expected: all selected tests PASS. Export the two transparency screenshots and confirm that 100% transparency removes the presenter background before and after People View is enabled.

- [ ] **Step 5: Check and commit the transparency fix**

```bash
git diff --check
git diff -- ConnectionPrompter/SessionModels.swift ConnectionPrompterTests/PrompterPreferencesTests.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git add ConnectionPrompter/SessionModels.swift ConnectionPrompterTests/PrompterPreferencesTests.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git commit -m "fix: keep transparency active in People View"
```

### Task 2: Show Resize Cursors on Every Presenter Edge and Corner

**Files:**
- Modify: `ConnectionPrompter/PresenterPanelController.swift:1-24,213-233`
- Create: `ConnectionPrompterTests/PresenterResizeRegionTests.swift`

**Interfaces:**
- Consumes: an `NSRect` view bounds and the existing `6`-point resize inset.
- Produces: `PresenterResizeCursorRegion.regions(in:inset:) -> [PresenterResizeCursorRegion]` and system cursor registration that does not consume mouse events.

- [ ] **Step 1: Add failing geometry coverage**

Create `ConnectionPrompterTests/PresenterResizeRegionTests.swift`:

```swift
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
```

This test fails if a side overlaps a corner, an edge is missing, the inset differs from six points, or the interior becomes a cursor region.

- [ ] **Step 2: Run the new test and verify RED**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PresenterResizeCursorRed.xcresult -only-testing:ConnectionPrompterTests/PresenterResizeRegionTests test
```

Expected: build/test failure because `PresenterResizeCursorRegion` and `PresenterResizeEdge` do not exist.

- [ ] **Step 3: Add the minimal region model and cursor mapping**

Before `PresenterPanel`, add these internal types and replace the panel's private inset with the shared constant:

```swift
private let presenterResizeHandleInset: CGFloat = 6

enum PresenterResizeEdge: Equatable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(
                position: frameResizePosition,
                directions: .all
            )
        }
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .resizeLeftRight
        }
    }

    @available(macOS 15.0, *)
    private var frameResizePosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .left: .left
        case .right: .right
        case .bottomLeft: .bottomLeft
        case .bottom: .bottom
        case .bottomRight: .bottomRight
        }
    }
}

struct PresenterResizeCursorRegion: Equatable {
    let edge: PresenterResizeEdge
    let rect: NSRect

    static func regions(in bounds: NSRect, inset: CGFloat) -> [Self] {
        let horizontalLength = max(bounds.width - inset * 2, 0)
        let verticalLength = max(bounds.height - inset * 2, 0)
        return [
            Self(
                edge: .topLeft,
                rect: NSRect(x: bounds.minX, y: bounds.minY, width: inset, height: inset)
            ),
            Self(
                edge: .top,
                rect: NSRect(
                    x: bounds.minX + inset,
                    y: bounds.minY,
                    width: horizontalLength,
                    height: inset
                )
            ),
            Self(
                edge: .topRight,
                rect: NSRect(
                    x: bounds.maxX - inset,
                    y: bounds.minY,
                    width: inset,
                    height: inset
                )
            ),
            Self(
                edge: .left,
                rect: NSRect(
                    x: bounds.minX,
                    y: bounds.minY + inset,
                    width: inset,
                    height: verticalLength
                )
            ),
            Self(
                edge: .right,
                rect: NSRect(
                    x: bounds.maxX - inset,
                    y: bounds.minY + inset,
                    width: inset,
                    height: verticalLength
                )
            ),
            Self(
                edge: .bottomLeft,
                rect: NSRect(
                    x: bounds.minX,
                    y: bounds.maxY - inset,
                    width: inset,
                    height: inset
                )
            ),
            Self(
                edge: .bottom,
                rect: NSRect(
                    x: bounds.minX + inset,
                    y: bounds.maxY - inset,
                    width: horizontalLength,
                    height: inset
                )
            ),
            Self(
                edge: .bottomRight,
                rect: NSRect(
                    x: bounds.maxX - inset,
                    y: bounds.maxY - inset,
                    width: inset,
                    height: inset
                )
            ),
        ]
    }
}
```

Use `presenterResizeHandleInset` in `PresenterPanel.sendEvent(_:)`.

- [ ] **Step 4: Register the cursor rectangles without changing hit testing**

Add to `PrompterHostingView`:

```swift
    override func resetCursorRects() {
        super.resetCursorRects()
        for region in PresenterResizeCursorRegion.regions(
            in: bounds,
            inset: presenterResizeHandleInset
        ) {
            addCursorRect(region.rect, cursor: region.edge.cursor)
        }
    }
```

Do not add tracking areas, overlays, gesture recognizers, or mouse handlers.

- [ ] **Step 5: Run the focused geometry and physical drag tests**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PresenterResizeCursorGreen.xcresult -only-testing:ConnectionPrompterTests/PresenterResizeRegionTests -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterProvidesDraggableAutoScrollSpeedControl test
```

Expected: PASS. The geometry is exact, the speed slider still does not move the window, and the content/background drag still moves it.

- [ ] **Step 6: Check and commit the cursor feedback**

```bash
git diff --check
git diff -- ConnectionPrompter/PresenterPanelController.swift ConnectionPrompterTests/PresenterResizeRegionTests.swift
git add ConnectionPrompter/PresenterPanelController.swift ConnectionPrompterTests/PresenterResizeRegionTests.swift
git commit -m "feat: show presenter resize cursors"
```

### Task 3: Persist the Default-On Scene Checkbox

**Files:**
- Modify: `ConnectionPrompter/SessionModels.swift:150-193`
- Modify: `ConnectionPrompter/SessionStore.swift:113-136`
- Modify: `ConnectionPrompter/EditorView.swift:69-81,190-286`
- Modify: `ConnectionPrompterTests/PrompterPreferencesTests.swift`
- Modify: `ConnectionPrompterTests/SessionStoreTests.swift`
- Modify: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`

**Interfaces:**
- Consumes: schema 2 JSON that may omit `hideEditorWhenPresenting`.
- Produces: stored `PrompterPreferences.hideEditorWhenPresenting: Bool?`, computed `shouldHideEditorWhenPresenting: Bool`, and a checkbox bound through `AppCoordinator.updatePreferences(_:)`.

- [ ] **Step 1: Add failing default and persistence tests**

Add to `PrompterPreferencesTests`:

```swift
    func testMissingScenePreferenceDefaultsToHidingTheEditor() {
        var preferences = PrompterPreferences.standard
        XCTAssertEqual(preferences.hideEditorWhenPresenting, true)

        preferences.hideEditorWhenPresenting = nil

        XCTAssertTrue(preferences.shouldHideEditorWhenPresenting)

        preferences.shouldHideEditorWhenPresenting = false

        XCTAssertFalse(preferences.shouldHideEditorWhenPresenting)
        XCTAssertEqual(preferences.hideEditorWhenPresenting, false)
    }
```

Add these tests to `SessionStoreTests`:

```swift
    func testVersionTwoSessionWithoutScenePreferenceDefaultsToHidingEditor() throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        try store.save(fixtureSession(title: "旧版会话", currentPage: 0))
        let data = try Data(contentsOf: store.primaryURL)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var session = try XCTUnwrap(root["session"] as? [String: Any])
        var preferences = try XCTUnwrap(session["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "hideEditorWhenPresenting")
        session["preferences"] = preferences
        root["session"] = session
        try JSONSerialization.data(withJSONObject: root).write(to: store.primaryURL)

        let restored = try XCTUnwrap(store.load())

        XCTAssertTrue(restored.preferences.shouldHideEditorWhenPresenting)
    }

    func testDisabledScenePreferenceRoundTrips() throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        var session = fixtureSession(title: "保留编辑页", currentPage: 0)
        session.preferences.shouldHideEditorWhenPresenting = false

        try store.save(session)

        XCTAssertFalse(
            try XCTUnwrap(store.load()).preferences.shouldHideEditorWhenPresenting
        )
    }
```

Also add this assertion to the existing
`testLoadsVersionOneSingleDocumentAsVersionTwoLibrary` test:

```swift
        XCTAssertTrue(
            restored?.preferences.shouldHideEditorWhenPresenting ?? false
        )
```

Add this UI test before the private helpers:

```swift
    func testSceneSettingDefaultsToHideEditor() {
        let app = makeApp()
        app.launch()
        app.activate()

        let setting = app.checkBoxes["主持时隐藏编辑页"]
        XCTAssertTrue(setting.waitForExistence(timeout: 3))
        XCTAssertEqual((setting.value as? NSNumber)?.intValue, 1)

        setting.click()
        XCTAssertEqual((setting.value as? NSNumber)?.intValue, 0)
        Thread.sleep(forTimeInterval: 0.6)
        app.terminate()

        app.launch()
        let restoredSetting = app.checkBoxes["主持时隐藏编辑页"]
        XCTAssertTrue(restoredSetting.waitForExistence(timeout: 3))
        XCTAssertEqual((restoredSetting.value as? NSNumber)?.intValue, 0)
    }
```

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PresenterScenePreferenceRed.xcresult -only-testing:ConnectionPrompterTests/PrompterPreferencesTests/testMissingScenePreferenceDefaultsToHidingTheEditor -only-testing:ConnectionPrompterTests/SessionStoreTests/testVersionTwoSessionWithoutScenePreferenceDefaultsToHidingEditor -only-testing:ConnectionPrompterTests/SessionStoreTests/testDisabledScenePreferenceRoundTrips -only-testing:ConnectionPrompterTests/SessionStoreTests/testLoadsVersionOneSingleDocumentAsVersionTwoLibrary -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testSceneSettingDefaultsToHideEditor test
```

Expected: build/test failure because the model properties and checkbox do not exist.

- [ ] **Step 3: Add the upgrade-safe preference**

Append the raw stored property to `PrompterPreferences`, include `true` in `.standard`, and expose one computed non-optional value:

```swift
    var hideEditorWhenPresenting: Bool? = true

    var shouldHideEditorWhenPresenting: Bool {
        get { hideEditorWhenPresenting ?? true }
        set { hideEditorWhenPresenting = newValue }
    }
```

In the schema 1 migration initializer, pass:

```swift
                hideEditorWhenPresenting: true
```

The optional raw property lets synthesized schema 2 decoding accept a missing key; do not bump the session schema.

- [ ] **Step 4: Add the compact checkbox beside autosave**

In the bottom status `HStack`, place this immediately after the autosave label:

```swift
                        Toggle(
                            "主持时隐藏编辑页",
                            isOn: hideEditorWhenPresentingBinding
                        )
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .accessibilityIdentifier("主持时隐藏编辑页")
```

Add to `EditorView`:

```swift
    private var hideEditorWhenPresentingBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.shouldHideEditorWhenPresenting },
            set: { value in
                coordinator.updatePreferences {
                    $0.shouldHideEditorWhenPresenting = value
                }
            }
        )
    }
```

- [ ] **Step 5: Run the focused preference and UI tests GREEN**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PresenterScenePreferenceGreen.xcresult -only-testing:ConnectionPrompterTests/PrompterPreferencesTests/testMissingScenePreferenceDefaultsToHidingTheEditor -only-testing:ConnectionPrompterTests/SessionStoreTests/testVersionTwoSessionWithoutScenePreferenceDefaultsToHidingEditor -only-testing:ConnectionPrompterTests/SessionStoreTests/testDisabledScenePreferenceRoundTrips -only-testing:ConnectionPrompterTests/SessionStoreTests/testLoadsVersionOneSingleDocumentAsVersionTwoLibrary -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testSceneSettingDefaultsToHideEditor test
```

Expected: all five selected tests PASS; schema 1 and schema 2 upgrades default to hiding, and the checkbox appears after autosave and defaults to checked.

- [ ] **Step 6: Check and commit the scene setting**

```bash
git diff --check
git diff -- ConnectionPrompter/SessionModels.swift ConnectionPrompter/SessionStore.swift ConnectionPrompter/EditorView.swift ConnectionPrompterTests/PrompterPreferencesTests.swift ConnectionPrompterTests/SessionStoreTests.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git add ConnectionPrompter/SessionModels.swift ConnectionPrompter/SessionStore.swift ConnectionPrompter/EditorView.swift ConnectionPrompterTests/PrompterPreferencesTests.swift ConnectionPrompterTests/SessionStoreTests.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git commit -m "feat: add presenter scene setting"
```

### Task 4: Hide and Restore Only the Editor Window Owned by Presentation

**Files:**
- Modify: `ConnectionPrompter/AppCoordinator.swift:7-113`
- Modify: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`

**Interfaces:**
- Consumes: `state.preferences.shouldHideEditorWhenPresenting`, the main non-panel `NSWindow`, and existing show/hide/return presenter paths.
- Produces: idempotent editor hiding and restoration tracked by `editorHiddenForPresentation: Bool`.

- [ ] **Step 1: Add a failing end-to-end scene behavior test**

Add this test before the UI test helpers:

```swift
    func testSceneSettingControlsEditorVisibilityDuringPresentation() {
        let app = makeApp()
        app.launch()
        app.activate()

        let editor = app.textViews["文稿正文"]
        let setting = app.checkBoxes["主持时隐藏编辑页"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(setting.waitForExistence(timeout: 2))
        XCTAssertEqual((setting.value as? NSNumber)?.intValue, 1)

        app.buttons["进入主持"].click()

        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        presenter.hover()
        let returnButton = presenter.buttons["返回编辑器"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 2))
        returnButton.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))

        setting.click()
        XCTAssertEqual((setting.value as? NSNumber)?.intValue, 0)
        app.buttons["进入主持"].click()

        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        XCTAssertTrue(editor.exists)
    }
```

- [ ] **Step 2: Run the behavior test and verify RED**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PresenterSceneBehaviorRed.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testSceneSettingControlsEditorVisibilityDuringPresentation test
```

Expected: FAIL because entering presentation leaves the editor visible.

- [ ] **Step 3: Track the editor window and whether presentation hid it**

Add these ignored properties to `AppCoordinator`:

```swift
    @ObservationIgnored private weak var editorWindow: NSWindow?
    @ObservationIgnored private var editorHiddenForPresentation = false
```

At the start of `connectIfNeeded()`, before the presenter panel is created, capture the editor:

```swift
        editorWindow = locateEditorWindow()
```

After both explicit `panelController?.show()` and the restored-presenter `controller.show()`, call:

```swift
        hideEditorForPresentationIfNeeded()
```

After `panelController?.hide()` in `hidePresenter()`, call:

```swift
        restoreEditorIfPresentationHidIt()
```

- [ ] **Step 4: Add the minimal idempotent window helpers**

Add these private methods to `AppCoordinator`:

```swift
    private func locateEditorWindow() -> NSWindow? {
        editorWindow ?? NSApplication.shared.windows.first { !($0 is NSPanel) }
    }

    private func hideEditorForPresentationIfNeeded() {
        guard state.preferences.shouldHideEditorWhenPresenting,
              !editorHiddenForPresentation,
              let window = locateEditorWindow(),
              window.isVisible,
              !window.isMiniaturized else {
            return
        }
        editorWindow = window
        window.orderOut(nil)
        editorHiddenForPresentation = true
    }

    private func restoreEditorIfPresentationHidIt() {
        guard editorHiddenForPresentation else { return }
        editorHiddenForPresentation = false
        showEditorWindow()
    }

    private func showEditorWindow() {
        guard let window = locateEditorWindow() else { return }
        editorWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
```

Replace `returnToEditor()`'s inline window lookup with:

```swift
    func returnToEditor() {
        hidePresenter()
        showEditorWindow()
    }
```

- [ ] **Step 5: Run scene behavior plus local-key regression tests GREEN**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/PresenterSceneBehaviorGreen.xcresult -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testSceneSettingControlsEditorVisibilityDuringPresentation -only-testing:ConnectionPrompterUITests/ConnectionPrompterLaunchTests/testPresenterArrowKeysAdjustSpeedAndNavigateText test
```

Expected: both tests PASS. The default path hides/restores the editor, keep-visible leaves it visible, and local arrow controls still work with the editor ordered out.

- [ ] **Step 6: Check and commit the presentation window lifecycle**

```bash
git diff --check
git diff -- ConnectionPrompter/AppCoordinator.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git add ConnectionPrompter/AppCoordinator.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git commit -m "feat: hide editor during presentation"
```

### Task 5: Prepare, Verify, and Package Connection Prompter 1.2.2

**Files:**
- Modify: `ConnectionPrompter.xcodeproj/project.pbxproj:322-360`
- Modify: `README.md`
- Verify: all production and test sources
- Create ignored artifacts: `dist/Connection Prompter 1.2.2.app`, `dist/Connection Prompter 1.2.2.zip`

**Interfaces:**
- Consumes: all completed 1.2.2 behavior.
- Produces: version `1.2.2`, build `5`, a signed sandboxed arm64 Release app, and a verified ZIP.

- [x] **Step 1: Update version metadata and documentation**

Set both app configurations to:

```text
CURRENT_PROJECT_VERSION = 5;
MARKETING_VERSION = 1.2.2;
```

Update the README title and direct-use path to 1.2.2. Add a V1.2.2 section documenting:

```markdown
## V1.2.2 修复与主持场景

- People View 现在会继续使用“背景透明度”设置。
- 鼠标移到主持浮窗的边缘或四角时，会显示窗口缩放光标。
- “主持时隐藏编辑页”默认开启；也可取消勾选，保持编辑窗口可见。
```

- [x] **Step 2: Check and commit release metadata**

```bash
git diff --check
git diff -- README.md ConnectionPrompter.xcodeproj/project.pbxproj
git add README.md ConnectionPrompter.xcodeproj/project.pbxproj
git commit -m "docs: prepare Connection Prompter 1.2.2"
```

- [ ] **Step 3: Run the complete Debug TestAction suite**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 -resultBundlePath build/ConnectionPrompter122Final.xcresult test
```

Expected: every unit and UI test PASS with 0 failures and 0 skips.

- [ ] **Step 4: Export and inspect final screenshots**

```bash
xcrun xcresulttool get test-results summary --path build/ConnectionPrompter122Final.xcresult
xcrun xcresulttool export attachments --path build/ConnectionPrompter122Final.xcresult --output-path build/ConnectionPrompter122Attachments
```

Inspect the standard/People View transparency screenshots, the editor status row, and the restored editor view. Confirm that controls are aligned, no text is clipped, and full transparency is visually evident in both presenter widths.

- [ ] **Step 5: Manually verify resize feedback on macOS 26**

Launch the Debug app:

```bash
open 'build/DerivedData-122/Build/Products/Debug/Connection Prompter.app'
```

Hover all four edges and all four corners. Confirm exact system frame-resize cursors on every region, no resize cursor in the content interior, speed-slider dragging does not move the window, and content/background dragging still does.

- [x] **Step 6: Produce a clean Release build**

```bash
xcodebuild -quiet -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-122 clean build
```

- [x] **Step 7: Copy and zip without overwriting 1.2.1**

First require both checks to exit 0:

```bash
test ! -e '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app'
test ! -e '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.zip'
```

Then create the artifacts:

```bash
ditto 'build/DerivedData-122/Build/Products/Release/Connection Prompter.app' '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app'
ditto -c -k --sequesterRsrc --keepParent '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app' '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.zip'
```

- [x] **Step 8: Verify every delivered artifact property**

```bash
codesign --verify --deep --strict --verbose=2 '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app'
codesign -d --entitlements :- '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app'
plutil -extract CFBundleShortVersionString raw '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app/Contents/Info.plist'
plutil -extract CFBundleVersion raw '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app/Contents/Info.plist'
lipo -info '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.app/Contents/MacOS/Connection Prompter'
unzip -t '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.zip'
shasum -a 256 '/Users/fois/Documents/ChatGPT/屏幕文字显示APP/dist/Connection Prompter 1.2.2.zip'
```

Expected: signature valid, `com.apple.security.app-sandbox = true`, version `1.2.2`, build `5`, architecture `arm64`, ZIP reports no errors, and SHA-256 is printed.

- [ ] **Step 9: Record verification and confirm clean source handoff**

Mark completed plan checkboxes, then run:

```bash
git diff --check
git status --short --branch
git log -10 --oneline --decorate
```

Commit only the completed verification record if the plan file changed:

```bash
git add docs/superpowers/plans/2026-08-09-presenter-visibility-and-resize.md
git commit -m "test: verify Connection Prompter 1.2.2 release"
```

Expected: clean `feature/v1-1` worktree with the 1.2.2 implementation and release commits above the approved design and plan commits.
