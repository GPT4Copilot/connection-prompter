import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var library: DocumentLibrary
    var searchQuery = ""
    var preferences: PrompterPreferences
    private(set) var pages: [PrompterPage]
    private(set) var currentPage: Int
    private(set) var scrollOffset: Double
    private(set) var autoScrollRunning: Bool
    var panelFrame: WindowFrame
    private(set) var presenterVisible: Bool
    var bannerMessage: String?

    private let store: any SessionStoring
    private let parser: ScriptParser
    private let pageComposer: PageComposer<TextKitLineBreaker>
    private var autosaveTask: Task<Void, Never>?
    private var autoScrollLineHeight: Double = 1
    private var maximumScrollOffset: Double = 0

    init(
        store: any SessionStoring,
        parser: ScriptParser = ScriptParser(),
        pageComposer: PageComposer<TextKitLineBreaker> = PageComposer(
            lineBreaker: TextKitLineBreaker()
        )
    ) {
        self.store = store
        self.parser = parser
        self.pageComposer = pageComposer

        let restored: RestorableSession
        do {
            restored = try store.load() ?? .initial()
        } catch {
            restored = .initial()
            bannerMessage = "上次文稿无法读取，已打开空白文稿；原文件仍保留在本机。"
        }

        library = restored.library
        preferences = restored.preferences
        currentPage = restored.currentPage
        scrollOffset = max(restored.scrollOffset, 0)
        autoScrollRunning = false
        panelFrame = restored.panelFrame
        presenterVisible = restored.presenterVisible
        pages = []
        rebuildPages()
    }

    var currentPrompterPage: PrompterPage? {
        guard pages.indices.contains(currentPage) else { return nil }
        return pages[currentPage]
    }

    var document: ScriptDocument {
        library.selectedDocument ?? .blank()
    }

    var visibleDocuments: [ScriptDocument] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.documents }
        return library.documents.filter { document in
            document.title.localizedCaseInsensitiveContains(query)
                || document.content.localizedCaseInsensitiveContains(query)
        }
    }

    var segmentCount: Int {
        parser.parse(document.content).count
    }

    var characterCount: Int {
        document.content.count
    }

    var longParagraphCount: Int {
        parser.parse(document.content).reduce(into: 0) { count, block in
            if case let .text(text) = block, text.count > 180 {
                count += 1
            }
        }
    }

    func updateTitle(_ title: String) {
        updateSelectedDocument { document in
            document.title = title
        }
    }

    func updateContent(_ content: String) {
        updateSelectedDocument { document in
            document.content = content
        }
        rebuildPages()
        resetScrollPosition()
    }

    @discardableResult
    func createDocument() -> UUID {
        let id = library.create(now: nextDocumentTimestamp())
        currentPage = 0
        rebuildPages()
        resetScrollPosition()
        scheduleAutosave()
        return id
    }

    func selectDocument(_ id: UUID) {
        guard id != library.selectedDocumentID, library.select(id) else { return }
        currentPage = 0
        rebuildPages()
        resetScrollPosition()
        scheduleAutosave()
    }

    func deleteSelectedDocument() {
        library.delete(library.selectedDocumentID, now: nextDocumentTimestamp())
        currentPage = 0
        rebuildPages()
        resetScrollPosition()
        scheduleAutosave()
    }

    func updatePreferences(_ update: (inout PrompterPreferences) -> Void) {
        update(&preferences)
        preferences.autoScrollSpeed = min(max(preferences.autoScrollSpeed, 0.1), 3)
        preferences.backgroundTransparency = min(
            max(preferences.backgroundTransparency, 0),
            1
        )
        rebuildPages()
        scheduleAutosave()
    }

    func nextPage() {
        pauseAutoScroll()
        currentPage = PageNavigation.next(from: currentPage, pageCount: pages.count)
        scheduleAutosave()
    }

    func previousPage() {
        pauseAutoScroll()
        currentPage = PageNavigation.previous(from: currentPage, pageCount: pages.count)
        scheduleAutosave()
    }

    func showPresenter() {
        presenterVisible = true
        scheduleAutosave()
    }

    func hidePresenter() {
        presenterVisible = false
        scheduleAutosave()
    }

    func togglePresenter() {
        presenterVisible.toggle()
        scheduleAutosave()
    }

    func setPanelFrame(_ frame: WindowFrame) {
        panelFrame = frame
        if !preferences.peopleView {
            rebuildPages()
        }
        scheduleAutosave()
    }

    func setScrollMetrics(lineHeight: Double, maximumOffset: Double) {
        autoScrollLineHeight = max(lineHeight, 0)
        maximumScrollOffset = max(maximumOffset, 0)
        scrollOffset = min(max(scrollOffset, 0), maximumScrollOffset)
        if maximumScrollOffset > 0, scrollOffset >= maximumScrollOffset {
            autoScrollRunning = false
        }
    }

    func startAutoScroll() {
        guard !document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              maximumScrollOffset > 0 else {
            autoScrollRunning = false
            return
        }
        if scrollOffset >= maximumScrollOffset {
            scrollOffset = 0
        }
        autoScrollRunning = true
        scheduleAutosave()
    }

    func pauseAutoScroll() {
        guard autoScrollRunning else { return }
        autoScrollRunning = false
        scheduleAutosave()
    }

    func toggleAutoScroll() {
        autoScrollRunning ? pauseAutoScroll() : startAutoScroll()
    }

    func resetAutoScroll() {
        autoScrollRunning = false
        scrollOffset = 0
        scheduleAutosave()
    }

    func advanceAutoScroll(elapsed: TimeInterval) {
        guard autoScrollRunning else { return }
        let advance = AutoScrollEngine.advance(
            offset: scrollOffset,
            elapsed: elapsed,
            linesPerSecond: preferences.autoScrollSpeed,
            lineHeight: autoScrollLineHeight,
            maximumOffset: maximumScrollOffset
        )
        scrollOffset = advance.offset
        if advance.reachedEnd {
            autoScrollRunning = false
            scheduleAutosave()
        }
    }

    func manualScroll(by distance: Double) {
        pauseAutoScroll()
        scrollOffset = min(
            max(scrollOffset + distance, 0),
            maximumScrollOffset
        )
        scheduleAutosave()
    }

    func saveImmediately() {
        autosaveTask?.cancel()
        do {
            try store.save(makeSession())
        } catch {
            bannerMessage = "自动保存失败，请检查磁盘空间后重试。"
        }
    }

    func dismissBanner() {
        bannerMessage = nil
    }

    private func updateSelectedDocument(_ update: (inout ScriptDocument) -> Void) {
        let timestamp = nextDocumentTimestamp()
        library.updateSelected { document in
            update(&document)
            document.updatedAt = timestamp
        }
        scheduleAutosave()
    }

    private func nextDocumentTimestamp() -> Date {
        let now = Date()
        guard let latest = library.documents.map(\.updatedAt).max(), now <= latest else {
            return now
        }
        return latest.addingTimeInterval(0.001)
    }

    private func rebuildPages() {
        let style = preferences.effectiveStyle
        let panelWidth = preferences.peopleView ? style.panelWidth : panelFrame.width
        let layout = PrompterLayout(
            width: max(panelWidth - 72, 1),
            fontSize: preferences.fontSize,
            lineHeight: preferences.lineDensity.multiplier,
            maximumLines: style.maximumLines
        )
        pages = pageComposer.compose(
            blocks: parser.parse(document.content),
            layout: layout
        )
        currentPage = PageNavigation.clamp(currentPage, pageCount: pages.count)
    }

    private func resetScrollPosition() {
        scrollOffset = 0
        autoScrollRunning = false
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func makeSession() -> RestorableSession {
        RestorableSession(
            library: library,
            currentPage: currentPage,
            scrollOffset: scrollOffset,
            autoScrollRunning: autoScrollRunning,
            panelFrame: panelFrame,
            preferences: preferences,
            presenterVisible: presenterVisible
        )
    }
}
