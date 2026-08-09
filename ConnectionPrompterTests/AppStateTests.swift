import XCTest
@testable import ConnectionPrompter

final class AppStateTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @MainActor
    func testContentEditRebuildsPagesAndClampsCurrentPosition() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        state.updateContent("第一段\n\n第二段\n\n第三段")
        state.nextPage()
        state.nextPage()
        XCTAssertEqual(state.currentPage, 2)

        state.updateContent("只剩一段")

        XCTAssertEqual(state.pages.count, 1)
        XCTAssertEqual(state.currentPage, 0)
    }

    @MainActor
    func testEditsAreAutosavedAfterDebounce() async throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        let state = AppState(store: store)

        state.updateTitle("读书会主持稿")
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(try store.load()?.document.title, "读书会主持稿")
    }

    @MainActor
    func testEditingSelectedDocumentUpdatesOnlyThatDocumentAndMovesItFirst() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        state.updateTitle("第一份")
        let firstID = state.document.id
        let secondID = state.createDocument()
        state.updateTitle("第二份")

        state.selectDocument(firstID)
        state.updateContent("第一份的新内容")

        XCTAssertEqual(state.library.documents.first?.id, firstID)
        XCTAssertEqual(state.library.documents.first?.content, "第一份的新内容")
        XCTAssertEqual(
            state.library.documents.first(where: { $0.id == secondID })?.title,
            "第二份"
        )
    }

    @MainActor
    func testSearchMatchesTitleAndBodyCaseInsensitively() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        state.updateTitle("Weekly Demo")
        state.updateContent("客户会议")
        let matchingID = state.document.id
        state.createDocument()
        state.updateTitle("其他内容")

        state.searchQuery = "weekly"
        XCTAssertEqual(state.visibleDocuments.map(\.id), [matchingID])

        state.searchQuery = "客户"
        XCTAssertEqual(state.visibleDocuments.map(\.id), [matchingID])
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

    @MainActor
    func testDeletingSelectedDocumentKeepsAUsableSelection() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        let originalID = state.document.id
        let secondID = state.createDocument()

        state.deleteSelectedDocument()

        XCTAssertEqual(state.document.id, originalID)
        XCTAssertFalse(state.library.documents.contains(where: { $0.id == secondID }))
    }

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
        state.updateContent("可以滚动的内容")
        state.setScrollMetrics(lineHeight: 40, maximumOffset: 500)
        state.startAutoScroll()
        state.advanceAutoScroll(elapsed: 1)

        state.resetAutoScroll()

        XCTAssertEqual(state.scrollOffset, 0)
        XCTAssertFalse(state.autoScrollRunning)
    }

    @MainActor
    func testManualScrollPausesAutomaticScrollingAndClampsPosition() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        state.updateContent("可以滚动的内容")
        state.setScrollMetrics(lineHeight: 40, maximumOffset: 100)
        state.startAutoScroll()

        state.manualScroll(by: 200)

        XCTAssertEqual(state.scrollOffset, 100)
        XCTAssertFalse(state.autoScrollRunning)
    }

    @MainActor
    func testChangingDocumentResetsScrollPositionAndPauses() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        state.updateContent("第一份内容")
        let firstID = state.document.id
        state.setScrollMetrics(lineHeight: 40, maximumOffset: 100)
        state.startAutoScroll()
        state.advanceAutoScroll(elapsed: 1)
        state.createDocument()

        state.selectDocument(firstID)

        XCTAssertEqual(state.scrollOffset, 0)
        XCTAssertFalse(state.autoScrollRunning)
    }

    @MainActor
    func testPageNavigationMovesContinuousTrackAndPausesAutomaticScrolling() {
        let state = AppState(store: FileSessionStore(directoryURL: directoryURL))
        state.updateContent("第一段\n\n第二段\n\n第三段")
        state.setScrollMetrics(lineHeight: 40, maximumOffset: 500)
        state.startAutoScroll()

        state.nextPage()

        XCTAssertEqual(state.scrollOffset, 120)
        XCTAssertFalse(state.autoScrollRunning)

        state.previousPage()
        XCTAssertEqual(state.scrollOffset, 0)
    }

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
}
