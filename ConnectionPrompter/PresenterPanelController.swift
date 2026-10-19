import AppKit
import SwiftUI

private let presenterResizeHandleInset: CGFloat = 6

enum PresenterResizeEdge: Equatable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(
                position: frameResizePosition,
                directions: .all
            )
        }
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .resizeLeftRight
        }
    }

    @available(macOS 15.0, *)
    private var frameResizePosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .left: .left
        case .right: .right
        case .bottomLeft: .bottomLeft
        case .bottom: .bottom
        case .bottomRight: .bottomRight
        }
    }
}

struct PresenterResizeCursorRegion: Equatable {
    let edge: PresenterResizeEdge
    let rect: NSRect

    static func regions(in bounds: NSRect, inset: CGFloat) -> [Self] {
        let horizontalLength = max(bounds.width - inset * 2, 0)
        let verticalLength = max(bounds.height - inset * 2, 0)
        return [
            Self(
                edge: .topLeft,
                rect: NSRect(x: bounds.minX, y: bounds.minY, width: inset, height: inset)
            ),
            Self(
                edge: .top,
                rect: NSRect(
                    x: bounds.minX + inset,
                    y: bounds.minY,
                    width: horizontalLength,
                    height: inset
                )
            ),
            Self(
                edge: .topRight,
                rect: NSRect(
                    x: bounds.maxX - inset,
                    y: bounds.minY,
                    width: inset,
                    height: inset
                )
            ),
            Self(
                edge: .left,
                rect: NSRect(
                    x: bounds.minX,
                    y: bounds.minY + inset,
                    width: inset,
                    height: verticalLength
                )
            ),
            Self(
                edge: .right,
                rect: NSRect(
                    x: bounds.maxX - inset,
                    y: bounds.minY + inset,
                    width: inset,
                    height: verticalLength
                )
            ),
            Self(
                edge: .bottomLeft,
                rect: NSRect(
                    x: bounds.minX,
                    y: bounds.maxY - inset,
                    width: inset,
                    height: inset
                )
            ),
            Self(
                edge: .bottom,
                rect: NSRect(
                    x: bounds.minX + inset,
                    y: bounds.maxY - inset,
                    width: horizontalLength,
                    height: inset
                )
            ),
            Self(
                edge: .bottomRight,
                rect: NSRect(
                    x: bounds.maxX - inset,
                    y: bounds.maxY - inset,
                    width: inset,
                    height: inset
                )
            ),
        ]
    }
}

private final class PresenterPanel: NSPanel {
    private let toolbarInteractionHeight: CGFloat = 50

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView {
            let location = contentView.convert(event.locationInWindow, from: nil)
            let dragBounds = contentView.bounds.insetBy(
                dx: presenterResizeHandleInset,
                dy: presenterResizeHandleInset
            )
            if dragBounds.contains(location),
               location.y > toolbarInteractionHeight {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PresenterPanelController: NSObject, NSWindowDelegate {
    private let coordinator: AppCoordinator
    private let panel: NSPanel
    private var normalFrame: NSRect?
    private var peopleViewApplied = false
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollNavigation = Date.distantPast
    private var isApplyingFrame = false
    private var localKeyMonitor: Any?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        panel = PresenterPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 180),
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "主持浮窗"
        panel.setAccessibilityTitle("主持浮窗")
        panel.setAccessibilityIdentifier("主持浮窗")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 500, height: 120)
        panel.maxSize = NSSize(width: 800, height: 220)
        panel.delegate = self

        let hostingView = PrompterHostingView(rootView: PresenterView(coordinator: coordinator))
        hostingView.onScroll = { [weak self] delta, isPrecise in
            self?.handleScroll(delta, isPrecise: isPrecise)
        }
        hostingView.onNavigationKey = { [weak self] direction in
            if direction < 0 {
                self?.coordinator.previousPage()
            } else {
                self?.coordinator.nextPage()
            }
        }
        panel.contentView = hostingView
        installLocalKeyMonitor()

        let restoredFrame: NSRect
        if coordinator.state.panelFrame == .standardPanel,
           let primaryScreen = NSScreen.main ?? NSScreen.screens.first {
            let visible = primaryScreen.visibleFrame
            restoredFrame = NSRect(
                x: visible.midX - 320,
                y: visible.maxY - 192,
                width: 640,
                height: 180
            )
        } else {
            restoredFrame = sanitize(coordinator.state.panelFrame)
        }
        applyFrame(restoredFrame)
        coordinator.state.setPanelFrame(WindowFrame(restoredFrame))
    }

    func show() {
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        syncConfiguration()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func syncConfiguration() {
        let preferences = coordinator.state.preferences
        panel.level = preferences.alwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = preferences.clickThrough

        if preferences.peopleView, !peopleViewApplied {
            normalFrame = panel.frame
            peopleViewApplied = true
            let current = panel.frame
            let peopleFrame = NSRect(
                x: current.midX - 260,
                y: current.maxY - 140,
                width: 520,
                height: 140
            )
            applyFrame(sanitize(WindowFrame(peopleFrame)))
        } else if !preferences.peopleView, peopleViewApplied {
            peopleViewApplied = false
            if let normalFrame {
                applyFrame(sanitize(WindowFrame(normalFrame)))
            }
            normalFrame = nil
        }
    }

    func windowDidMove(_ notification: Notification) {
        recordPanelFrameIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        if !isApplyingFrame, coordinator.state.preferences.peopleView {
            coordinator.state.setPresenterViewportWidth(panel.frame.width)
        }
        recordPanelFrameIfNeeded()
    }

    private func recordPanelFrameIfNeeded() {
        guard !isApplyingFrame, !coordinator.state.preferences.peopleView else { return }
        coordinator.state.setPanelFrame(WindowFrame(panel.frame))
    }

    private func handleScroll(_ delta: CGFloat, isPrecise: Bool) {
        if isPrecise {
            coordinator.manualScroll(by: Double(-delta))
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastScrollNavigation) < 0.35 { return }
        scrollAccumulator += delta
        guard abs(scrollAccumulator) >= 24 else { return }

        if scrollAccumulator > 0 {
            coordinator.previousPage()
        } else {
            coordinator.nextPage()
        }
        scrollAccumulator = 0
        lastScrollNavigation = now
    }

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let userModifierFlags: NSEvent.ModifierFlags = [
                .command, .control, .option, .shift
            ]
            let hasModifiers = !event.modifierFlags
                .intersection(userModifierFlags)
                .isEmpty
            let handled = MainActor.assumeIsolated {
                self?.handleLocalNavigationKey(keyCode, hasModifiers: hasModifiers) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handleLocalNavigationKey(_ keyCode: UInt16, hasModifiers: Bool) -> Bool {
        guard coordinator.state.presenterVisible,
              !hasModifiers,
              !(NSApplication.shared.keyWindow?.firstResponder is NSTextView) else {
            return false
        }

        switch keyCode {
        case 123:
            coordinator.adjustAutoScrollSpeed(by: -0.1)
            return true
        case 124:
            coordinator.adjustAutoScrollSpeed(by: 0.1)
            return true
        case 126:
            coordinator.previousPage()
            return true
        case 125, 49:
            coordinator.nextPage()
            return true
        default:
            return false
        }
    }

    private func sanitize(_ frame: WindowFrame) -> NSRect {
        let screens = NSScreen.screens.map { WindowFrame($0.visibleFrame) }
        return NSRect(PanelFrameSanitizer.sanitize(frame, visibleScreens: screens))
    }

    private func applyFrame(_ frame: NSRect) {
        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        isApplyingFrame = false
        coordinator.state.setPresenterViewportWidth(frame.width)
    }
}

private final class PrompterHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((CGFloat, Bool) -> Void)?
    var onNavigationKey: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        for region in PresenterResizeCursorRegion.regions(
            in: bounds,
            inset: presenterResizeHandleInset
        ) {
            addCursorRect(region.rect, cursor: region.edge.cursor)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            onNavigationKey?(-1)
        case 125, 49:
            onNavigationKey?(1)
        default:
            super.keyDown(with: event)
        }
    }
}

private extension WindowFrame {
    init(_ rect: NSRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}

private extension NSRect {
    init(_ frame: WindowFrame) {
        self.init(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }
}
