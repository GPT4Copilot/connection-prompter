import Foundation

struct DocumentDayGroup: Identifiable, Equatable, Sendable {
    enum Kind: Int, CaseIterable, Sendable {
        case today
        case yesterday
        case earlier
    }

    var kind: Kind
    var documents: [ScriptDocument]

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .today: "今天"
        case .yesterday: "昨天"
        case .earlier: "更早"
        }
    }
}

enum DocumentGrouping {
    static func group(
        _ documents: [ScriptDocument],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DocumentDayGroup] {
        var buckets: [DocumentDayGroup.Kind: [ScriptDocument]] = [:]

        for document in documents {
            let kind: DocumentDayGroup.Kind
            if calendar.isDate(document.updatedAt, inSameDayAs: now) {
                kind = .today
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                      calendar.isDate(document.updatedAt, inSameDayAs: yesterday) {
                kind = .yesterday
            } else {
                kind = .earlier
            }
            buckets[kind, default: []].append(document)
        }

        return DocumentDayGroup.Kind.allCases.compactMap { kind in
            guard var groupedDocuments = buckets[kind], !groupedDocuments.isEmpty else {
                return nil
            }
            groupedDocuments.sort { $0.updatedAt > $1.updatedAt }
            return DocumentDayGroup(kind: kind, documents: groupedDocuments)
        }
    }
}
