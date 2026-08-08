import Foundation

protocol ScriptParsing: Sendable {
    func parse(_ content: String) -> [ScriptBlock]
}

struct ScriptParser: ScriptParsing {
    func parse(_ content: String) -> [ScriptBlock] {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var rawBlocks: [String] = []
        var currentLines: [String] = []

        func flushCurrentLines() {
            guard !currentLines.isEmpty else { return }
            rawBlocks.append(currentLines.joined(separator: "\n"))
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushCurrentLines()
            } else {
                currentLines.append(trimmed)
            }
        }
        flushCurrentLines()

        return rawBlocks.map { block in
            if let cue = CueKind(source: block) {
                return .cue(cue)
            }
            return .text(block)
        }
    }
}
