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
}
