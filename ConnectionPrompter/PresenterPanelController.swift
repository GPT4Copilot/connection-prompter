import AppKit
import SwiftUI

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
        panel = NSPanel(
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
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 500, height: 120)
        panel.maxSize = NSSize(width: 800, height: 220)
        panel.delegate = self

        let hostingView = PrompterHostingView(rootView: PresenterView(coordinator: coordinator))
        hostingView.onScroll = { [weak self] delta in
            self?.handleScroll(delta)
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
        recordPanelFrameIfNeeded()
    }

    private func recordPanelFrameIfNeeded() {
        guard !isApplyingFrame, !coordinator.state.preferences.peopleView else { return }
        coordinator.state.setPanelFrame(WindowFrame(panel.frame))
    }

    private func handleScroll(_ delta: CGFloat) {
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
            let hasModifiers = !event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
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
    }
}

private final class PrompterHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((CGFloat) -> Void)?
    var onNavigationKey: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
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
