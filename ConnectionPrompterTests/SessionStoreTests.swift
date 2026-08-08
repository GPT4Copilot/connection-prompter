import XCTest
@testable import ConnectionPrompter

final class SessionStoreTests: XCTestCase {
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

    func testRoundTripsCompleteSession() throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        let session = fixtureSession(title: "主持稿", currentPage: 3)

        try store.save(session)

        XCTAssertEqual(try store.load(), session)
    }

    func testLoadsBackupWhenPrimaryFileIsCorrupted() throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        let first = fixtureSession(title: "第一版", currentPage: 1)
        let second = fixtureSession(title: "第二版", currentPage: 2)
        try store.save(first)
        try store.save(second)
        try Data("broken".utf8).write(to: store.primaryURL)

        XCTAssertEqual(try store.load(), first)
    }

    func testCorruptedPrimaryAndBackupAreNotOverwritten() throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        let primary = Data("primary-broken".utf8)
        let backup = Data("backup-broken".utf8)
        try primary.write(to: store.primaryURL)
        try backup.write(to: store.backupURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.primaryURL), primary)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), backup)
    }

    func testMissingSessionReturnsNil() throws {
        XCTAssertNil(try FileSessionStore(directoryURL: directoryURL).load())
    }

    func testLoadsVersionOneSingleDocumentAsVersionTwoLibrary() throws {
        let store = FileSessionStore(directoryURL: directoryURL)
        try legacyVersionOneJSON().write(to: store.primaryURL)

        let restored = try store.load()

        XCTAssertEqual(restored?.library.documents.map(\.title), ["旧主持稿"])
        XCTAssertEqual(restored?.library.selectedDocument?.content, "第一段")
        XCTAssertEqual(restored?.preferences.backgroundTransparency ?? -1, 0.30, accuracy: 0.0001)
        XCTAssertEqual(restored?.preferences.autoScrollSpeed, 0.5)
        XCTAssertEqual(restored?.scrollOffset, 0)
        XCTAssertFalse(restored?.autoScrollRunning ?? true)
    }

    private func fixtureSession(title: String, currentPage: Int) -> RestorableSession {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return RestorableSession(
            library: DocumentLibrary.single(
                ScriptDocument(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: title,
                content: "第一段\n\n⏸ 停",
                createdAt: date,
                updatedAt: date
                )
            ),
            currentPage: currentPage,
            scrollOffset: 48,
            autoScrollRunning: false,
            panelFrame: WindowFrame(x: 100, y: 700, width: 640, height: 180),
            preferences: .standard,
            presenterVisible: true
        )
    }

    private func legacyVersionOneJSON() -> Data {
        Data(
            """
            {
              "schemaVersion" : 1,
              "session" : {
                "currentPage" : 2,
                "document" : {
                  "content" : "第一段",
                  "createdAt" : "2023-11-14T22:13:20Z",
                  "title" : "旧主持稿",
                  "updatedAt" : "2023-11-14T22:13:20Z"
                },
                "panelFrame" : {
                  "height" : 180,
                  "width" : 640,
                  "x" : 100,
                  "y" : 700
                },
                "preferences" : {
                  "alignment" : "center",
                  "alwaysOnTop" : true,
                  "backgroundOpacity" : 0.7,
                  "blurEnabled" : true,
                  "clickThrough" : false,
                  "fontSize" : 32,
                  "lineDensity" : "normal",
                  "maximumLines" : 3,
                  "peopleView" : false
                },
                "presenterVisible" : false
              }
            }
            """.utf8
        )
    }
}
