import Foundation

struct ScriptDocument: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func blank(now: Date = Date()) -> ScriptDocument {
        ScriptDocument(
            id: UUID(),
            title: "未命名文稿",
            content: "",
            createdAt: now,
            updatedAt: now
        )
    }
}

struct DocumentLibrary: Codable, Equatable, Sendable {
    var documents: [ScriptDocument]
    var selectedDocumentID: UUID

    var selectedDocument: ScriptDocument? {
        documents.first { $0.id == selectedDocumentID }
    }

    static func initial(now: Date = Date()) -> DocumentLibrary {
        single(.blank(now: now))
    }

    static func single(_ document: ScriptDocument) -> DocumentLibrary {
        DocumentLibrary(documents: [document], selectedDocumentID: document.id)
    }

    @discardableResult
    mutating func create(now: Date = Date()) -> UUID {
        let document = ScriptDocument.blank(now: now)
        documents.insert(document, at: 0)
        selectedDocumentID = document.id
        return document.id
    }

    @discardableResult
    mutating func select(_ id: UUID) -> Bool {
        guard documents.contains(where: { $0.id == id }) else { return false }
        selectedDocumentID = id
        return true
    }

    mutating func delete(_ id: UUID, now: Date = Date()) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedDocumentID == id
        documents.remove(at: index)

        if documents.isEmpty {
            self = .initial(now: now)
        } else if wasSelected {
            selectedDocumentID = documents[min(index, documents.count - 1)].id
        }
        sortByRecentUpdate()
    }

    mutating func repairSelection(now: Date = Date()) {
        if documents.isEmpty {
            self = .initial(now: now)
            return
        }
        sortByRecentUpdate()
        if !documents.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = documents[0].id
        }
    }

    mutating func updateSelected(_ update: (inout ScriptDocument) -> Void) {
        guard let index = documents.firstIndex(where: { $0.id == selectedDocumentID }) else {
            return
        }
        update(&documents[index])
        sortByRecentUpdate()
    }

    private mutating func sortByRecentUpdate() {
        documents.sort { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

enum LineDensity: String, Codable, CaseIterable, Sendable {
    case compact
    case normal
    case relaxed

    var multiplier: Double {
        switch self {
        case .compact: 1.15
        case .normal: 1.35
        case .relaxed: 1.55
        }
    }

    var label: String {
        switch self {
        case .compact: "紧凑"
        case .normal: "标准"
        case .relaxed: "舒展"
        }
    }
}

enum TextAlignmentSetting: String, Codable, CaseIterable, Sendable {
    case center
    case left

    var label: String {
        switch self {
        case .center: "居中"
        case .left: "左对齐"
        }
    }
}

struct EffectivePrompterStyle: Equatable, Sendable {
    var panelWidth: Double
    var panelHeight: Double
    var maximumLines: Int
    var backgroundOpacity: Double
    var backgroundTransparency: Double { 1 - backgroundOpacity }
}

struct PrompterPreferences: Codable, Equatable, Sendable {
    var fontSize: Double
    var lineDensity: LineDensity
    var alignment: TextAlignmentSetting
    var maximumLines: Int
    var backgroundTransparency: Double
    var autoScrollSpeed: Double
    var blurEnabled: Bool
    var alwaysOnTop: Bool
    var clickThrough: Bool
    var peopleView: Bool

    static let standard = PrompterPreferences(
        fontSize: 32,
        lineDensity: .normal,
        alignment: .center,
        maximumLines: 3,
        backgroundTransparency: 0.30,
        autoScrollSpeed: 0.5,
        blurEnabled: true,
        alwaysOnTop: true,
        clickThrough: false,
        peopleView: false
    )

    var effectiveStyle: EffectivePrompterStyle {
        if peopleView {
            return EffectivePrompterStyle(
                panelWidth: 520,
                panelHeight: 140,
                maximumLines: 2,
                backgroundOpacity: 1 - min(max(backgroundTransparency, 0), 1)
            )
        }
        return EffectivePrompterStyle(
            panelWidth: 640,
            panelHeight: 180,
            maximumLines: min(max(maximumLines, 2), 4),
            backgroundOpacity: 1 - min(max(backgroundTransparency, 0), 1)
        )
    }

    var backgroundOpacity: Double {
        get { 1 - backgroundTransparency }
        set { backgroundTransparency = 1 - min(max(newValue, 0), 1) }
    }
}

struct WindowFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let standardPanel = WindowFrame(x: 0, y: 0, width: 640, height: 180)
}

enum PanelFrameSanitizer {
    static func sanitize(
        _ frame: WindowFrame,
        visibleScreens: [WindowFrame]
    ) -> WindowFrame {
        guard let primary = visibleScreens.first else { return frame }
        if visibleScreens.contains(where: { visibleArea(of: frame, in: $0) }) {
            return frame
        }

        let width = min(max(frame.width, 500), min(800, primary.width))
        let height = min(max(frame.height, 120), min(220, primary.height))
        return WindowFrame(
            x: primary.x + (primary.width - width) / 2,
            y: primary.y + primary.height - height - 12,
            width: width,
            height: height
        )
    }

    private static func visibleArea(of frame: WindowFrame, in screen: WindowFrame) -> Bool {
        let overlapWidth = max(
            0,
            min(frame.x + frame.width, screen.x + screen.width) - max(frame.x, screen.x)
        )
        let overlapHeight = max(
            0,
            min(frame.y + frame.height, screen.y + screen.height) - max(frame.y, screen.y)
        )
        return overlapWidth >= 64 && overlapHeight >= 32
    }
}

struct RestorableSession: Codable, Equatable, Sendable {
    var library: DocumentLibrary
    var currentPage: Int
    var scrollOffset: Double
    var autoScrollRunning: Bool
    var panelFrame: WindowFrame
    var preferences: PrompterPreferences
    var presenterVisible: Bool

    init(
        library: DocumentLibrary,
        currentPage: Int,
        scrollOffset: Double,
        autoScrollRunning: Bool,
        panelFrame: WindowFrame,
        preferences: PrompterPreferences,
        presenterVisible: Bool
    ) {
        self.library = library
        self.currentPage = currentPage
        self.scrollOffset = scrollOffset
        self.autoScrollRunning = autoScrollRunning
        self.panelFrame = panelFrame
        self.preferences = preferences
        self.presenterVisible = presenterVisible
    }

    init(
        document: ScriptDocument,
        currentPage: Int,
        panelFrame: WindowFrame,
        preferences: PrompterPreferences,
        presenterVisible: Bool
    ) {
        self.init(
            library: .single(document),
            currentPage: currentPage,
            scrollOffset: 0,
            autoScrollRunning: false,
            panelFrame: panelFrame,
            preferences: preferences,
            presenterVisible: presenterVisible
        )
    }

    var document: ScriptDocument {
        get { library.selectedDocument ?? .blank() }
        set { library = .single(newValue) }
    }

    static func initial(now: Date = Date()) -> RestorableSession {
        RestorableSession(
            library: .initial(now: now),
            currentPage: 0,
            scrollOffset: 0,
            autoScrollRunning: false,
            panelFrame: .standardPanel,
            preferences: .standard,
            presenterVisible: false
        )
    }
}
