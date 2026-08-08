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

    private func fixtureSession(title: String, currentPage: Int) -> RestorableSession {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return RestorableSession(
            document: ScriptDocument(
                title: title,
                content: "第一段\n\n⏸ 停",
                createdAt: date,
                updatedAt: date
            ),
            currentPage: currentPage,
            panelFrame: WindowFrame(x: 100, y: 700, width: 640, height: 180),
            preferences: .standard,
            presenterVisible: true
        )
    }
}
