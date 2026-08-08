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
}
