import Foundation

struct CueInsertionResult: Equatable {
    let text: String
    let selectionLocation: Int
}

enum CueTextInsertion {
    static func inserting(
        _ cue: CueKind,
        into text: String,
        selectedRange: NSRange
    ) -> CueInsertionResult {
        let source = text as NSString
        let location = min(max(selectedRange.location, 0), source.length)
        let maximumLength = source.length - location
        let length = min(max(selectedRange.length, 0), maximumLength)

        let before = source.substring(to: location)
        let after = source.substring(from: location + length)
        let cueText = cue.displayLabel
        let leadingSeparator = separatorBeforeCue(in: before)
        let trailingSeparator = separatorAfterCue(in: after)

        return CueInsertionResult(
            text: before + leadingSeparator + cueText + trailingSeparator + after,
            selectionLocation: before.utf16.count + leadingSeparator.utf16.count + cueText.utf16.count
        )
    }

    private static func separatorBeforeCue(in text: String) -> String {
        guard !text.isEmpty else { return "" }
        if text.hasSuffix("\n\n") { return "" }
        if text.hasSuffix("\n") { return "\n" }
        return "\n\n"
    }

    private static func separatorAfterCue(in text: String) -> String {
        guard !text.isEmpty else { return "" }
        if text.hasPrefix("\n\n") { return "" }
        if text.hasPrefix("\n") { return "\n" }
        return "\n\n"
    }
}
