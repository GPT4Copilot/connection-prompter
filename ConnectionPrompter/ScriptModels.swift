import Foundation

enum CueKind: String, CaseIterable, Codable, Equatable, Sendable {
    case lookCamera = "LOOK_CAMERA"
    case pause = "PAUSE"
    case smile = "SMILE"
    case inviteResponse = "INVITE_RESPONSE"
    case watchPeople = "WATCH_PEOPLE"

    var displayLabel: String {
        switch self {
        case .lookCamera: "👁 看镜头"
        case .pause: "⏸ 停"
        case .smile: "🙂 笑"
        case .inviteResponse: "🙋 邀请回应"
        case .watchPeople: "❤️ 看大家"
        }
    }

    var menuTitle: String {
        switch self {
        case .lookCamera: "看镜头"
        case .pause: "停顿"
        case .smile: "微笑"
        case .inviteResponse: "邀请回应"
        case .watchPeople: "看大家"
        }
    }

    var canonicalMarker: String {
        "[\(rawValue)]"
    }

    init?(source: String) {
        guard let cue = Self.allCases.first(where: {
            source == $0.displayLabel || source == $0.canonicalMarker
        }) else {
            return nil
        }
        self = cue
    }
}

enum ScriptBlock: Equatable, Sendable {
    case text(String)
    case cue(CueKind)
}
