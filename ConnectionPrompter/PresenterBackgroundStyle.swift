import Foundation

struct PresenterBackgroundStyle: Equatable, Sendable {
    let materialOpacity: Double
    let blackFillOpacity: Double
    let chromeOpacity: Double

    init(
        transparency: Double,
        reduceTransparency: Bool,
        blurEnabled: Bool
    ) {
        let clampedTransparency = min(max(transparency, 0), 1)
        let visibility = 1 - clampedTransparency
        materialOpacity = blurEnabled && !reduceTransparency ? visibility : 0
        blackFillOpacity = visibility * (blurEnabled && !reduceTransparency ? 0.72 : 1)
        chromeOpacity = visibility
    }
}
