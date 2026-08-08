import Foundation

protocol SessionStoring: Sendable {
    func load() throws -> RestorableSession?
    func save(_ session: RestorableSession) throws
}

enum SessionStoreError: Error {
    case unreadablePrimaryAndBackup(primary: Error, backup: Error?)
}

struct FileSessionStore: SessionStoring, Sendable {
    let directoryURL: URL

    var primaryURL: URL {
        directoryURL.appendingPathComponent("session.json")
    }

    var backupURL: URL {
        directoryURL.appendingPathComponent("session.backup.json")
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func load() throws -> RestorableSession? {
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            return nil
        }

        do {
            return try decodeSession(at: primaryURL)
        } catch {
            let primaryError = error
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                throw SessionStoreError.unreadablePrimaryAndBackup(
                    primary: primaryError,
                    backup: nil
                )
            }
            do {
                return try decodeSession(at: backupURL)
            } catch {
                throw SessionStoreError.unreadablePrimaryAndBackup(
                    primary: primaryError,
                    backup: error
                )
            }
        }
    }

    func save(_ session: RestorableSession) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: primaryURL.path) {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: primaryURL, to: backupURL)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(PersistedSessionV2(schemaVersion: 2, session: session))
        try data.write(to: primaryURL, options: .atomic)
    }

    private func decodeSession(at url: URL) throws -> RestorableSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        let version = try decoder.decode(SessionVersionEnvelope.self, from: data).schemaVersion
        switch version {
        case 1:
            return try decoder.decode(PersistedSessionV1.self, from: data).migratedSession
        case 2:
            var session = try decoder.decode(PersistedSessionV2.self, from: data).session
            session.library.repairSelection()
            session.autoScrollRunning = false
            return session
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported session schema version: \(version)"
                )
            )
        }
    }
}

private struct SessionVersionEnvelope: Decodable {
    var schemaVersion: Int
}

private struct PersistedSessionV2: Codable {
    var schemaVersion: Int
    var session: RestorableSession
}

private struct PersistedSessionV1: Decodable {
    var schemaVersion: Int
    var session: LegacySession

    var migratedSession: RestorableSession {
        let document = ScriptDocument(
            title: session.document.title,
            content: session.document.content,
            createdAt: session.document.createdAt,
            updatedAt: session.document.updatedAt
        )
        return RestorableSession(
            library: .single(document),
            currentPage: session.currentPage,
            scrollOffset: 0,
            autoScrollRunning: false,
            panelFrame: session.panelFrame,
            preferences: PrompterPreferences(
                fontSize: session.preferences.fontSize,
                lineDensity: session.preferences.lineDensity,
                alignment: session.preferences.alignment,
                maximumLines: session.preferences.maximumLines,
                backgroundTransparency: 1 - min(max(session.preferences.backgroundOpacity, 0), 1),
                autoScrollSpeed: 0.5,
                blurEnabled: session.preferences.blurEnabled,
                alwaysOnTop: session.preferences.alwaysOnTop,
                clickThrough: session.preferences.clickThrough,
                peopleView: session.preferences.peopleView
            ),
            presenterVisible: session.presenterVisible
        )
    }
}

private struct LegacySession: Decodable {
    var document: LegacyDocument
    var currentPage: Int
    var panelFrame: WindowFrame
    var preferences: LegacyPreferences
    var presenterVisible: Bool
}

private struct LegacyDocument: Decodable {
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
}

private struct LegacyPreferences: Decodable {
    var fontSize: Double
    var lineDensity: LineDensity
    var alignment: TextAlignmentSetting
    var maximumLines: Int
    var backgroundOpacity: Double
    var blurEnabled: Bool
    var alwaysOnTop: Bool
    var clickThrough: Bool
    var peopleView: Bool
}
