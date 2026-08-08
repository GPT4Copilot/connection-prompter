import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var document: ScriptDocument
    var preferences: PrompterPreferences
    private(set) var pages: [PrompterPage]
    private(set) var currentPage: Int
    var panelFrame: WindowFrame
    private(set) var presenterVisible: Bool
    var bannerMessage: String?

    private let store: any SessionStoring
    private let parser: ScriptParser
    private let pageComposer: PageComposer<TextKitLineBreaker>
    private var autosaveTask: Task<Void, Never>?

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

        document = restored.document
        preferences = restored.preferences
        currentPage = restored.currentPage
        panelFrame = restored.panelFrame
        presenterVisible = restored.presenterVisible
        pages = []
        rebuildPages()
    }

    var currentPrompterPage: PrompterPage? {
        guard pages.indices.contains(currentPage) else { return nil }
        return pages[currentPage]
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
        document.title = title
        markDocumentUpdated()
    }

    func updateContent(_ content: String) {
        document.content = content
        markDocumentUpdated()
        rebuildPages()
    }

    func updatePreferences(_ update: (inout PrompterPreferences) -> Void) {
        update(&preferences)
        rebuildPages()
        scheduleAutosave()
    }

    func nextPage() {
        currentPage = PageNavigation.next(from: currentPage, pageCount: pages.count)
        scheduleAutosave()
    }

    func previousPage() {
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

    private func markDocumentUpdated() {
        document.updatedAt = Date()
        scheduleAutosave()
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
            document: document,
            currentPage: currentPage,
            panelFrame: panelFrame,
            preferences: preferences,
            presenterVisible: presenterVisible
        )
    }
}
