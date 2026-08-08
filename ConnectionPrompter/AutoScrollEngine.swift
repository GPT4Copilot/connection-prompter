import Foundation

struct AutoScrollAdvance: Equatable, Sendable {
    var offset: Double
    var reachedEnd: Bool
}

enum AutoScrollEngine {
    static func advance(
        offset: Double,
        elapsed: TimeInterval,
        linesPerSecond: Double,
        lineHeight: Double,
        maximumOffset: Double
    ) -> AutoScrollAdvance {
        let maximum = max(maximumOffset, 0)
        let current = min(max(offset, 0), maximum)
        let distance = max(elapsed, 0) * max(linesPerSecond, 0) * max(lineHeight, 0)
        let next = min(current + distance, maximum)
        return AutoScrollAdvance(
            offset: next,
            reachedEnd: maximum > 0 && next >= maximum
        )
    }
}
