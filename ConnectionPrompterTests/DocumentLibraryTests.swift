import XCTest
@testable import ConnectionPrompter

final class DocumentLibraryTests: XCTestCase {
    func testDeleteConfirmationTitleCompactsAndLimitsLongMultilineTitle() {
        let longTitle = "2026-10-20 早读共建\n" + String(repeating: "主持稿完整内容 ", count: 100)

        let prompt = DocumentDeletionPrompt.title(for: longTitle)

        XCTAssertFalse(prompt.contains("\n"))
        XCTAssertLessThanOrEqual(prompt.count, 42)
        XCTAssertTrue(prompt.hasPrefix("删除“2026-10-20 早读共建"))
        XCTAssertTrue(prompt.hasSuffix("…”？"))
    }

    func testDeleteConfirmationTitleUsesFallbackForWhitespaceOnlyTitle() {
        XCTAssertEqual(
            DocumentDeletionPrompt.title(for: " \n\t "),
            "删除“未命名文稿”？"
        )
    }

    func testNewLibraryAlwaysHasOneSelectedBlankDocument() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let library = DocumentLibrary.initial(now: now)

        XCTAssertEqual(library.documents.count, 1)
        XCTAssertEqual(library.selectedDocument?.title, "未命名文稿")
        XCTAssertEqual(library.selectedDocumentID, library.documents[0].id)
    }

    func testCreateSelectsNewDocumentAndPlacesItFirst() {
        var library = DocumentLibrary.initial(now: Date(timeIntervalSince1970: 1))
        let originalID = library.selectedDocumentID

        let createdID = library.create(now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(library.selectedDocumentID, createdID)
        XCTAssertEqual(library.documents.map(\.id), [createdID, originalID])
    }

    func testDeletingSelectedDocumentSelectsNearestRemainingDocument() {
        var library = DocumentLibrary.initial(now: Date(timeIntervalSince1970: 1))
        let firstID = library.selectedDocumentID
        let secondID = library.create(now: Date(timeIntervalSince1970: 2))

        library.delete(secondID, now: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(library.selectedDocumentID, firstID)
        XCTAssertEqual(library.documents.count, 1)
    }

    func testDeletingLastDocumentCreatesAndSelectsBlankReplacement() {
        var library = DocumentLibrary.initial(now: Date(timeIntervalSince1970: 1))
        let deletedID = library.selectedDocumentID

        library.delete(deletedID, now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(library.documents.count, 1)
        XCTAssertNotEqual(library.selectedDocumentID, deletedID)
        XCTAssertEqual(library.selectedDocument?.title, "未命名文稿")
    }

    func testRepairSelectionFallsBackToMostRecentlyUpdatedDocument() {
        let old = ScriptDocument(
            id: UUID(),
            title: "旧稿",
            content: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let recent = ScriptDocument(
            id: UUID(),
            title: "新稿",
            content: "",
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        var library = DocumentLibrary(
            documents: [old, recent],
            selectedDocumentID: UUID()
        )

        library.repairSelection(now: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(library.selectedDocumentID, recent.id)
        XCTAssertEqual(library.documents.map(\.id), [recent.id, old.id])
    }
}
