import Foundation

struct ScriptDocument: Codable, Equatable, Sendable {
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    static func blank(now: Date = Date()) -> ScriptDocument {
        ScriptDocument(
            title: "未命名文稿",
            content: "",
            createdAt: now,
            updatedAt: now
        )
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
}

struct PrompterPreferences: Codable, Equatable, Sendable {
    var fontSize: Double
    var lineDensity: LineDensity
    var alignment: TextAlignmentSetting
    var maximumLines: Int
    var backgroundOpacity: Double
    var blurEnabled: Bool
    var alwaysOnTop: Bool
    var clickThrough: Bool
    var peopleView: Bool

    static let standard = PrompterPreferences(
        fontSize: 32,
        lineDensity: .normal,
        alignment: .center,
        maximumLines: 3,
        backgroundOpacity: 0.70,
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
                backgroundOpacity: 0.45
            )
        }
        return EffectivePrompterStyle(
            panelWidth: 640,
            panelHeight: 180,
            maximumLines: min(max(maximumLines, 2), 4),
            backgroundOpacity: min(max(backgroundOpacity, 0), 1)
        )
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
    var document: ScriptDocument
    var currentPage: Int
    var panelFrame: WindowFrame
    var preferences: PrompterPreferences
    var presenterVisible: Bool

    static func initial(now: Date = Date()) -> RestorableSession {
        RestorableSession(
            document: .blank(now: now),
            currentPage: 0,
            panelFrame: .standardPanel,
            preferences: .standard,
            presenterVisible: false
        )
    }
}
