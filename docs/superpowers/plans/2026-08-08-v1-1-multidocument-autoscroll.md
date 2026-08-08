# Connection Prompter V1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a native macOS V1.1 that makes the presenter background genuinely transparent, adds smooth speed-controlled automatic scrolling, and stores multiple scripts in an Apple Notes-style library.

**Architecture:** Migrate the persisted single-document session to a versioned `DocumentLibrary` while keeping the selected document exposed through `AppState`. Isolate background rendering and auto-scroll mathematics into pure, testable value types; SwiftUI owns animation and presentation while AppKit continues to own the transparent `NSPanel`. The editor becomes a two-column `NavigationSplitView` whose list selects, creates, searches, and deletes documents.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, TextKit, XCTest, XCUITest, Xcode 26.6, macOS 14+, Apple Silicon only.

## Global Constraints

- Product name remains `Connection Prompter`; UI copy is Simplified Chinese.
- Bundle ID remains `com.connectionprompter.app`.
- Minimum supported system is macOS 14; architecture is Apple Silicon only.
- Keep App Sandbox enabled and request no network, microphone, camera, or Accessibility permissions.
- Transparency means 0% is fully opaque and 100% fully reveals applications behind the presenter while text and controls remain legible.
- Auto-scroll speed range is 0.1–3.0 lines per second, default 0.5, with start/pause/reset controls.
- Preserve atomic autosave, one backup, corrupted-file preservation, global hotkeys, click-through, People View, and cross-Space/full-screen panel behavior.
- The final source repository must be private on GitHub.

---

### Task 1: Versioned Multi-Document Session Model and Migration

**Files:**
- Modify: `ConnectionPrompter/SessionModels.swift`
- Modify: `ConnectionPrompter/SessionStore.swift`
- Modify: `ConnectionPrompterTests/SessionStoreTests.swift`
- Create: `ConnectionPrompterTests/DocumentLibraryTests.swift`

**Interfaces:**
- Produces: `ScriptDocument.id: UUID`.
- Produces: `DocumentLibrary.documents: [ScriptDocument]`, `selectedDocumentID: UUID`, `selectedDocument`, `create(now:)`, `select(_:)`, `delete(_:, now:)`, and `filtered(by:)`.
- Produces: `RestorableSession.library`, `currentPage`, `scrollOffset`, `panelFrame`, `preferences`, and `presenterVisible`.
- Produces: `FileSessionStore` schema-version 2 encoder and schema-version 1 decoder migration.

- [ ] **Step 1: Write failing model and migration tests**

```swift
func testNewLibraryAlwaysHasOneSelectedBlankDocument() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let library = DocumentLibrary.initial(now: now)

    XCTAssertEqual(library.documents.count, 1)
    XCTAssertEqual(library.selectedDocument?.title, "未命名文稿")
    XCTAssertEqual(library.selectedDocumentID, library.documents[0].id)
}

func testDeletingSelectedDocumentSelectsNearestRemainingDocument() {
    var library = DocumentLibrary.initial(now: Date(timeIntervalSince1970: 1))
    let firstID = library.selectedDocumentID
    let secondID = library.create(now: Date(timeIntervalSince1970: 2))

    library.delete(secondID, now: Date(timeIntervalSince1970: 3))

    XCTAssertEqual(library.selectedDocumentID, firstID)
    XCTAssertEqual(library.documents.count, 1)
}

func testLoadsVersionOneSingleDocumentAsVersionTwoLibrary() throws {
    let legacyJSON = legacyFixtureJSON(title: "旧主持稿", opacity: 0.70)
    try legacyJSON.write(to: FileSessionStore(directoryURL: directoryURL).primaryURL)

    let restored = try FileSessionStore(directoryURL: directoryURL).load()

    XCTAssertEqual(restored?.library.documents.map(\.title), ["旧主持稿"])
    XCTAssertEqual(restored?.preferences.backgroundTransparency, 0.30, accuracy: 0.0001)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -only-testing:ConnectionPrompterTests/DocumentLibraryTests -only-testing:ConnectionPrompterTests/SessionStoreTests test
```

Expected: compilation fails because `DocumentLibrary`, document IDs, `scrollOffset`, and `backgroundTransparency` do not exist.

- [ ] **Step 3: Add UUID identity and the library behavior**

```swift
struct ScriptDocument: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    static func blank(now: Date = Date()) -> ScriptDocument {
        ScriptDocument(id: UUID(), title: "未命名文稿", content: "", createdAt: now, updatedAt: now)
    }
}

struct DocumentLibrary: Codable, Equatable, Sendable {
    var documents: [ScriptDocument]
    var selectedDocumentID: UUID

    var selectedDocument: ScriptDocument? {
        documents.first { $0.id == selectedDocumentID }
    }

    static func initial(now: Date = Date()) -> DocumentLibrary {
        let document = ScriptDocument.blank(now: now)
        return DocumentLibrary(documents: [document], selectedDocumentID: document.id)
    }
}
```

Implement mutations so documents are ordered by `updatedAt` descending, deleting the last document creates a new blank document, and a missing selection is repaired to the first document.

- [ ] **Step 4: Implement explicit schema 1 → schema 2 decoding**

Decode the top-level `schemaVersion` first. For version 1, decode legacy structs without UUID or auto-scroll fields, assign one stable UUID during migration, map `backgroundTransparency = 1 - backgroundOpacity`, set `scrollOffset = 0`, `autoScrollSpeed = 0.5`, and `autoScrollRunning = false`. Encode only schema version 2.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the command from Step 2. Expected: all `DocumentLibraryTests` and `SessionStoreTests` pass.

- [ ] **Step 6: Commit the model migration**

```bash
git add ConnectionPrompter/SessionModels.swift ConnectionPrompter/SessionStore.swift ConnectionPrompterTests/SessionStoreTests.swift ConnectionPrompterTests/DocumentLibraryTests.swift
git commit -m "feat: migrate sessions to a document library"
```

### Task 2: App State for Selection, Search, Creation, and Deletion

**Files:**
- Modify: `ConnectionPrompter/AppState.swift`
- Modify: `ConnectionPrompterTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `DocumentLibrary` and schema-version 2 `RestorableSession` from Task 1.
- Produces: `AppState.library`, computed selected `document`, `searchQuery`, `visibleDocuments`, `selectDocument(_:)`, `createDocument()`, and `deleteSelectedDocument()`.
- Preserves: `updateTitle(_:)`, `updateContent(_:)`, page rebuilding, 350 ms autosave, and safe page clamping.

- [ ] **Step 1: Write failing state behavior tests**

```swift
@MainActor
func testEditingSelectedDocumentUpdatesOnlyThatDocumentAndMovesItFirst() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
    let firstID = state.document.id
    let secondID = state.createDocument()

    state.updateTitle("第二份主持稿")

    XCTAssertEqual(state.library.documents.first?.id, secondID)
    XCTAssertEqual(state.library.documents.first?.title, "第二份主持稿")
    XCTAssertEqual(state.library.documents.first(where: { $0.id == firstID })?.title, "未命名文稿")
}

@MainActor
func testSearchMatchesTitleAndBodyCaseInsensitively() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
    state.updateTitle("Weekly Demo")
    state.updateContent("客户会议")

    state.searchQuery = "weekly"
    XCTAssertEqual(state.visibleDocuments.map(\.id), [state.document.id])

    state.searchQuery = "客户"
    XCTAssertEqual(state.visibleDocuments.map(\.id), [state.document.id])
}

@MainActor
func testSelectingDocumentResetsNavigationAndRebuildsItsPages() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
    state.updateContent("第一段\n\n第二段")
    state.nextPage()
    let firstID = state.document.id
    let secondID = state.createDocument()
    state.updateContent("另一份")

    state.selectDocument(firstID)

    XCTAssertEqual(state.currentPage, 0)
    XCTAssertEqual(state.pages.count, 2)
    XCTAssertNotEqual(secondID, state.document.id)
}
```

- [ ] **Step 2: Run `AppStateTests` and verify RED**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -only-testing:ConnectionPrompterTests/AppStateTests test
```

Expected: compilation fails because library operations and search do not exist.

- [ ] **Step 3: Replace the stored single document with selected-document accessors**

Store `library` as the source of truth. Use an index lookup for mutations and update only the selected document. After a title/content edit, set `updatedAt`, sort descending, rebuild pages for content changes, and debounce-save the complete library.

- [ ] **Step 4: Add selection, creation, deletion, and search**

`createDocument()` returns the new UUID and selects it. `deleteSelectedDocument()` delegates to `DocumentLibrary`, rebuilds pages, resets `currentPage` and `scrollOffset`, and saves. `visibleDocuments` trims the query and matches localized case-insensitively against title or content.

- [ ] **Step 5: Run focused and full unit tests**

Run the Step 2 command, then:

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -only-testing:ConnectionPrompterTests test
```

Expected: all unit tests pass.

- [ ] **Step 6: Commit state management**

```bash
git add ConnectionPrompter/AppState.swift ConnectionPrompterTests/AppStateTests.swift
git commit -m "feat: manage multiple scripts in app state"
```

### Task 3: True Presenter Background Transparency

**Files:**
- Create: `ConnectionPrompter/PresenterBackgroundStyle.swift`
- Create: `ConnectionPrompterTests/PresenterBackgroundStyleTests.swift`
- Modify: `ConnectionPrompter/SessionModels.swift`
- Modify: `ConnectionPrompter/PresenterView.swift`
- Modify: `ConnectionPrompter/EditorView.swift`
- Modify: `ConnectionPrompter/AppCoordinator.swift`
- Modify: `ConnectionPrompterTests/PrompterPreferencesTests.swift`

**Interfaces:**
- Produces: `PrompterPreferences.backgroundTransparency: Double` in `0...1`.
- Produces: `PresenterBackgroundStyle(transparency:reduceTransparency:blurEnabled:)` with `materialOpacity`, `blackFillOpacity`, `chromeOpacity`.
- Changes: `AppCoordinator.adjustTransparency(by:)` replaces opacity adjustment.

- [ ] **Step 1: Write failing rendering-value tests**

```swift
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

func testZeroPercentTransparencyIsOpaque() {
    let style = PresenterBackgroundStyle(
        transparency: 0,
        reduceTransparency: false,
        blurEnabled: true
    )

    XCTAssertEqual(style.materialOpacity, 1)
    XCTAssertEqual(style.blackFillOpacity, 0.72, accuracy: 0.0001)
}

func testReducedTransparencyDoesNotForceAnOpaqueBackground() {
    let style = PresenterBackgroundStyle(
        transparency: 0.8,
        reduceTransparency: true,
        blurEnabled: true
    )

    XCTAssertEqual(style.materialOpacity, 0)
    XCTAssertEqual(style.blackFillOpacity, 0.2, accuracy: 0.0001)
}
```

- [ ] **Step 2: Run the style tests and verify RED**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -only-testing:ConnectionPrompterTests/PresenterBackgroundStyleTests test
```

Expected: compilation fails because `PresenterBackgroundStyle` and `backgroundTransparency` do not exist.

- [ ] **Step 3: Implement clamped background-layer values**

```swift
struct PresenterBackgroundStyle: Equatable, Sendable {
    let materialOpacity: Double
    let blackFillOpacity: Double
    let chromeOpacity: Double

    init(transparency: Double, reduceTransparency: Bool, blurEnabled: Bool) {
        let visibility = 1 - min(max(transparency, 0), 1)
        materialOpacity = blurEnabled && !reduceTransparency ? visibility : 0
        blackFillOpacity = visibility * (reduceTransparency || !blurEnabled ? 1 : 0.72)
        chromeOpacity = visibility
    }
}
```

- [ ] **Step 4: Wire the presenter to a genuinely clear panel background**

Keep `NSPanel.isOpaque = false` and `.backgroundColor = .clear`. Render material, black fill, border, and shadow with `PresenterBackgroundStyle`; do not apply opacity to `pageContent` or the control capsule. At 100%, the panel background, border, and shadow are invisible while text and controls remain visible.

- [ ] **Step 5: Replace the slider and panel buttons with 0–100% transparency semantics**

Bind the settings slider to `backgroundTransparency` over `0...1` with `0.01` steps and display `Int(value * 100)%`. Presenter controls call `adjustTransparency(by: ±0.05)`. People View uses a temporary 55% transparency and restores the normal value on exit.

- [ ] **Step 6: Run transparency and preference tests**

Run the Step 2 command plus `PrompterPreferencesTests`. Expected: all pass.

- [ ] **Step 7: Commit the transparency fix**

```bash
git add ConnectionPrompter/PresenterBackgroundStyle.swift ConnectionPrompter/SessionModels.swift ConnectionPrompter/PresenterView.swift ConnectionPrompter/EditorView.swift ConnectionPrompter/AppCoordinator.swift ConnectionPrompterTests/PresenterBackgroundStyleTests.swift ConnectionPrompterTests/PrompterPreferencesTests.swift
git commit -m "fix: make presenter background truly transparent"
```

### Task 4: Smooth Automatic Scrolling Engine and State

**Files:**
- Create: `ConnectionPrompter/AutoScrollEngine.swift`
- Create: `ConnectionPrompterTests/AutoScrollEngineTests.swift`
- Modify: `ConnectionPrompter/SessionModels.swift`
- Modify: `ConnectionPrompter/AppState.swift`
- Modify: `ConnectionPrompterTests/AppStateTests.swift`

**Interfaces:**
- Produces: `AutoScrollEngine.advance(offset:elapsed:linesPerSecond:lineHeight:maximumOffset:) -> AutoScrollAdvance`.
- Produces: `AutoScrollAdvance.offset` and `reachedEnd`.
- Produces: preferences `autoScrollSpeed: Double` and restorable state `scrollOffset: Double`, `autoScrollRunning: Bool`.
- Produces: `AppState.startAutoScroll()`, `pauseAutoScroll()`, `toggleAutoScroll()`, `resetAutoScroll()`, `advanceAutoScroll(elapsed:)`, and `manualScroll(by:)`.

- [ ] **Step 1: Write failing pure engine tests**

```swift
func testAdvancesByLinesPerSecondTimesLineHeight() {
    let result = AutoScrollEngine.advance(
        offset: 12,
        elapsed: 2,
        linesPerSecond: 0.5,
        lineHeight: 40,
        maximumOffset: 500
    )

    XCTAssertEqual(result.offset, 52, accuracy: 0.0001)
    XCTAssertFalse(result.reachedEnd)
}

func testClampsAtEndAndReportsCompletion() {
    let result = AutoScrollEngine.advance(
        offset: 90,
        elapsed: 1,
        linesPerSecond: 1,
        lineHeight: 20,
        maximumOffset: 100
    )

    XCTAssertEqual(result.offset, 100)
    XCTAssertTrue(result.reachedEnd)
}

func testNegativeElapsedAndSpeedNeverMoveBackward() {
    XCTAssertEqual(
        AutoScrollEngine.advance(offset: 30, elapsed: -1, linesPerSecond: -2, lineHeight: 40, maximumOffset: 100).offset,
        30
    )
}
```

- [ ] **Step 2: Run engine tests and verify RED**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' -only-testing:ConnectionPrompterTests/AutoScrollEngineTests test
```

Expected: compilation fails because the engine does not exist.

- [ ] **Step 3: Implement the pure engine**

Clamp elapsed and speed to nonnegative values, speed to `0.1...3.0` at the preference boundary, line height to nonnegative, and result to `0...maximumOffset`. `reachedEnd` is true only when the maximum offset is positive and the new value reaches it.

- [ ] **Step 4: Add failing `AppState` start/pause/reset/end tests**

```swift
@MainActor
func testAutoScrollStopsWhenItReachesTheEnd() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
    state.updateContent(String(repeating: "滚动内容 ", count: 200))
    state.setScrollMetrics(lineHeight: 40, maximumOffset: 100)
    state.startAutoScroll()

    state.advanceAutoScroll(elapsed: 20)

    XCTAssertEqual(state.scrollOffset, 100)
    XCTAssertFalse(state.autoScrollRunning)
}

@MainActor
func testResetAutoScrollPausesAndReturnsToTop() {
    let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
    state.setScrollMetrics(lineHeight: 40, maximumOffset: 500)
    state.startAutoScroll()
    state.advanceAutoScroll(elapsed: 1)

    state.resetAutoScroll()

    XCTAssertEqual(state.scrollOffset, 0)
    XCTAssertFalse(state.autoScrollRunning)
}
```

- [ ] **Step 5: Run state tests and verify RED, then add minimal state transitions**

Manual scroll and page navigation pause automatic scrolling before changing position. Starting at the end resets to zero. Changing the selected document resets offset and pauses. Persist speed and offset, but always restore `autoScrollRunning` as false after relaunch for safety.

- [ ] **Step 6: Run focused and full unit tests**

Run `AutoScrollEngineTests`, `AppStateTests`, and then all unit tests. Expected: all pass.

- [ ] **Step 7: Commit the scrolling engine**

```bash
git add ConnectionPrompter/AutoScrollEngine.swift ConnectionPrompter/SessionModels.swift ConnectionPrompter/AppState.swift ConnectionPrompterTests/AutoScrollEngineTests.swift ConnectionPrompterTests/AppStateTests.swift
git commit -m "feat: add persistent smooth auto-scroll state"
```

### Task 5: Continuous Presenter Track and Auto-Scroll Controls

**Files:**
- Modify: `ConnectionPrompter/PresenterView.swift`
- Modify: `ConnectionPrompter/PresenterPanelController.swift`
- Modify: `ConnectionPrompter/EditorView.swift`
- Modify: `ConnectionPrompter/AppCoordinator.swift`
- Modify: `ConnectionPrompter/PrompterPagination.swift`

**Interfaces:**
- Consumes: auto-scroll state and engine from Task 4.
- Produces: flattened presenter lines suitable for a continuously offset vertical track.
- Produces: presenter play/pause/reset buttons and settings speed slider.

- [ ] **Step 1: Add a failing pagination test for flattened display lines**

```swift
func testFlattenedTrackKeepsCueOnItsOwnLineAndAllTextInOrder() {
    let pages = composer.compose(
        blocks: [.text("第一段"), .cue(.pause), .text("第二段")],
        layout: PrompterLayout(width: 500, fontSize: 32, lineHeight: 1.35, maximumLines: 3)
    )

    XCTAssertEqual(PrompterTrack(pages: pages).lines.map(\.text), ["第一段", "⏸ 停", "第二段"])
}
```

- [ ] **Step 2: Run `PageComposerTests` and verify RED**

Expected: compilation fails because `PrompterTrack` does not exist.

- [ ] **Step 3: Add `PrompterTrack` with ordered, de-duplicated lines**

Build the track from source blocks/line-breaking output rather than concatenating page context lines, because pages repeat low-weight previous/next lines. Each semantic text line appears once and each cue is exactly one line.

- [ ] **Step 4: Render a clipped vertical track driven by a timeline**

Use `TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !state.autoScrollRunning))`. Track elapsed time between ticks, call `advanceAutoScroll(elapsed:)`, and apply `.offset(y: -state.scrollOffset)`. Measure line height and content height using geometry preferences; update `setScrollMetrics(lineHeight:maximumOffset:)`. Ensure the first line begins inside the visible panel and the last line can reach the reading position.

- [ ] **Step 5: Connect manual wheel/key/page input to the same position**

`PresenterPanelController` forwards high-resolution wheel delta to `coordinator.manualScroll(by:)` and pauses auto-scroll. Up/down/Space move one line-equivalent and pause. Keep threshold/cooldown only for discrete non-precise wheels; trackpads use their precise deltas.

- [ ] **Step 6: Add visible presenter and settings controls**

Add play/pause and reset buttons to the capsule. Add `自动滚动速度` slider (`0.1...3.0`, step `0.1`) displaying one decimal place plus `行/秒`. The start action remains available when Click Through is off; global navigation remains available when Click Through is on.

- [ ] **Step 7: Run all unit tests and build Debug**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' test
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

Expected: tests and build succeed without new warnings.

- [ ] **Step 8: Commit presenter scrolling UI**

```bash
git add ConnectionPrompter/PresenterView.swift ConnectionPrompter/PresenterPanelController.swift ConnectionPrompter/EditorView.swift ConnectionPrompter/AppCoordinator.swift ConnectionPrompter/PrompterPagination.swift ConnectionPrompterTests/PageComposerTests.swift
git commit -m "feat: add smooth presenter auto-scroll controls"
```

### Task 6: Apple Notes-Style Document Library UI

**Files:**
- Create: `ConnectionPrompter/DocumentListView.swift`
- Create: `ConnectionPrompter/DocumentGrouping.swift`
- Create: `ConnectionPrompterTests/DocumentGroupingTests.swift`
- Modify: `ConnectionPrompter/EditorView.swift`
- Modify: `ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift`

**Interfaces:**
- Consumes: library operations and `visibleDocuments` from Task 2.
- Produces: `DocumentDayGroup` (`today`, `yesterday`, `earlier`) and deterministic grouping by calendar/day.
- Produces: Notes-style sidebar with search, date sections, preview rows, create, delete, and selection.

- [ ] **Step 1: Write failing grouping tests**

```swift
func testGroupsDocumentsIntoTodayYesterdayAndEarlier() {
    let now = date(2026, 8, 8, 12)
    let documents = [
        document("今天", updatedAt: date(2026, 8, 8, 8)),
        document("昨天", updatedAt: date(2026, 8, 7, 18)),
        document("更早", updatedAt: date(2026, 8, 1, 10))
    ]

    let groups = DocumentGrouping.group(documents, now: now, calendar: calendar)

    XCTAssertEqual(groups.map(\.title), ["今天", "昨天", "更早"])
    XCTAssertEqual(groups.flatMap(\.documents).map(\.title), ["今天", "昨天", "更早"])
}
```

- [ ] **Step 2: Run grouping tests and verify RED**

Expected: compilation fails because grouping types do not exist.

- [ ] **Step 3: Implement deterministic date grouping**

Use `Calendar.isDateInToday`, `isDateInYesterday`, and an `earlier` fallback. Omit empty sections and preserve `updatedAt` descending within each section.

- [ ] **Step 4: Build the Notes-style sidebar**

Use `NavigationSplitView` with a 280 pt default sidebar. Top area: sidebar title `文稿`, count, search field, and new-document button. Rows show bold title, localized update time, and a one-line normalized content preview; selected rows use the system accent selection background. Bottom toolbar contains create and delete buttons. Deletion uses a confirmation dialog naming the selected script.

- [ ] **Step 5: Place the existing editor in the detail column**

Retain the narrow centered editor, toolbar, cue insertion, statistics, warning, settings, and `进入主持`. Remove the redundant product name from inside the document canvas; the window title/toolbar provides product identity. When search has no results, show `没有找到文稿` without deleting or changing selection.

- [ ] **Step 6: Update UI tests for create, select, edit, and restore**

Use accessibility identifiers `文稿列表`, `新建文稿`, `删除文稿`, `搜索文稿`, `文稿标题`, and `文稿正文`. Add a launch argument that points persistence to an isolated test directory. Test creating a second document, editing both titles, selecting the first again, and verifying its title/body are restored.

- [ ] **Step 7: Run unit and UI tests**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' test
```

Expected: all unit and UI tests pass.

- [ ] **Step 8: Commit the Notes-style library**

```bash
git add ConnectionPrompter/DocumentListView.swift ConnectionPrompter/DocumentGrouping.swift ConnectionPrompter/EditorView.swift ConnectionPrompterTests/DocumentGroupingTests.swift ConnectionPrompterUITests/ConnectionPrompterLaunchTests.swift
git commit -m "feat: add Notes-style script library"
```

### Task 7: Accessibility, Visual QA, Release Build, and Delivery

**Files:**
- Modify: `README.md`
- Modify: files identified by visual/accessibility verification only when a visible defect is reproduced.

**Interfaces:**
- Consumes: completed V1.1 app from Tasks 1–6.
- Produces: tested Release `.app`, private GitHub repository, and user-facing download/source paths.

- [ ] **Step 1: Update the README with V1.1 behavior**

Document multi-document autosave, transparency semantics, speed range, play/pause/reset controls, keyboard/global shortcuts, click-through recovery, local data location, and macOS 14/Apple Silicon requirements.

- [ ] **Step 2: Run the complete verification suite**

```bash
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -destination 'platform=macOS,arch=arm64' clean test
xcodebuild -project ConnectionPrompter.xcodeproj -scheme ConnectionPrompter -configuration Release -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
```

Expected: all tests pass, Release build succeeds, and no newly introduced compiler warnings appear.

- [ ] **Step 3: Inspect the built app visually**

Launch the Release app and compare the library layout against the supplied Apple Notes screenshot at the same window size. Verify list width, selected-row treatment, title/preview hierarchy, editor whitespace, toolbar density, clipping, margins, and rounded corners. Open the presenter over another application and verify 0%, 50%, and 100% transparency, text legibility, start/pause/reset, speed changes, People View restoration, click-through, and manual-scroll pause.

- [ ] **Step 4: Verify accessibility and window behavior**

Check Reduce Transparency, Reduce Motion, VoiceOver labels/order, keyboard navigation, multiple Spaces, full-screen auxiliary behavior, and off-screen panel recovery. Confirm 100% transparency still reveals the application behind the panel under Reduce Transparency.

- [ ] **Step 5: Package the new app**

Copy the verified Release product to `dist/Connection Prompter.app`, preserve its local signature, and confirm `codesign --verify --deep --strict` succeeds.

- [ ] **Step 6: Commit release documentation and final fixes**

```bash
git add README.md ConnectionPrompter ConnectionPrompterTests ConnectionPrompterUITests
git commit -m "release: prepare Connection Prompter 1.1"
```

- [ ] **Step 7: Create and push the private GitHub repository**

Create `GPT4Copilot/connection-prompter` with private visibility, add it as `origin`, push the feature branch and final `main` history, and verify repository visibility is private through the GitHub connector before returning its URL.

- [ ] **Step 8: Report delivery paths**

Return clickable paths for `dist/Connection Prompter.app` and this implementation plan, plus the private GitHub repository URL. State the exact unit/UI test count and Release build/signature result from Step 2 and Step 5.
