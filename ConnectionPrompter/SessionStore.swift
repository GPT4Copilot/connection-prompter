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
        let data = try encoder.encode(PersistedSession(schemaVersion: 1, session: session))
        try data.write(to: primaryURL, options: .atomic)
    }

    private func decodeSession(at url: URL) throws -> RestorableSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedSession.self, from: Data(contentsOf: url)).session
    }
}

private struct PersistedSession: Codable {
    var schemaVersion: Int
    var session: RestorableSession
}
