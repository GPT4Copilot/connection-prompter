import AppKit
import Observation

@MainActor
@Observable
final class AppCoordinator {
    let state: AppState

    @ObservationIgnored private var panelController: PresenterPanelController?
    @ObservationIgnored private var hotkeyManager: GlobalHotkeyManager?
    @ObservationIgnored private weak var editorWindow: NSWindow?
    @ObservationIgnored private weak var editorWindowHiddenForPresentation: NSWindow?
    @ObservationIgnored private var editorHiddenForPresentation = false
    @ObservationIgnored private var connected = false

    init(state: AppState, editorWindow: NSWindow? = nil) {
        self.state = state
        self.editorWindow = editorWindow
    }

    func connectIfNeeded() {
        guard !connected else { return }
        connected = true
        editorWindow = locateEditorWindow()
        let controller = PresenterPanelController(coordinator: self)
        panelController = controller
        controller.syncConfiguration()

        let hotkeys = GlobalHotkeyManager(coordinator: self)
        hotkeyManager = hotkeys
        let failures = hotkeys.registerDefaultHotkeys()
        if !failures.isEmpty {
            state.bannerMessage = "快捷键 \(failures.map(\.displayName).joined(separator: "、")) 已被其他应用占用，其余快捷键仍可使用。"
        }
        if state.presenterVisible {
            controller.show()
            hideEditorForPresentationIfNeeded()
        }
    }

    func showPresenter() {
        let wasPresenterVisible = state.presenterVisible
        connectIfNeeded()
        state.showPresenter()
        panelController?.show()
        if !wasPresenterVisible {
            hideEditorForPresentationIfNeeded()
        }
    }

    func hidePresenter() {
        state.hidePresenter()
        panelController?.hide()
        restoreEditorIfPresentationHidIt()
    }

    func togglePresenter() {
        state.presenterVisible ? hidePresenter() : showPresenter()
    }

    func nextPage() {
        state.nextPage()
    }

    func previousPage() {
        state.previousPage()
    }

    func toggleAutoScroll() {
        state.toggleAutoScroll()
    }

    func resetAutoScroll() {
        state.resetAutoScroll()
    }

    func setAutoScrollSpeed(_ speed: Double) {
        state.setAutoScrollSpeed(speed)
    }

    func adjustAutoScrollSpeed(by amount: Double) {
        state.adjustAutoScrollSpeed(by: amount)
    }

    func manualScroll(by distance: Double) {
        state.manualScroll(by: distance)
    }

    func updatePreferences(_ update: (inout PrompterPreferences) -> Void) {
        state.updatePreferences(update)
        panelController?.syncConfiguration()
    }

    func togglePeopleView() {
        updatePreferences { $0.peopleView.toggle() }
    }

    func toggleClickThrough() {
        updatePreferences { $0.clickThrough.toggle() }
    }

    func adjustFontSize(by amount: Double) {
        updatePreferences {
            $0.fontSize = min(max($0.fontSize + amount, 24), 48)
        }
    }

    func adjustTransparency(by amount: Double) {
        updatePreferences {
            $0.backgroundTransparency = min(
                max($0.backgroundTransparency + amount, 0),
                1
            )
        }
    }

    func returnToEditor() {
        hidePresenter()
        showEditorWindow()
    }

    private func locateEditorWindow() -> NSWindow? {
        if let editorWindow,
           NSApplication.shared.windows.contains(where: { $0 === editorWindow }) {
            return editorWindow
        }
        return NSApplication.shared.windows.first { !($0 is NSPanel) }
    }

    private func hideEditorForPresentationIfNeeded() {
        guard state.preferences.shouldHideEditorWhenPresenting,
              !editorHiddenForPresentation,
              let window = locateEditorWindow(),
              window.isVisible,
              !window.isMiniaturized else {
            return
        }
        editorWindow = window
        window.orderOut(nil)
        editorWindowHiddenForPresentation = window
        editorHiddenForPresentation = true
    }

    private func restoreEditorIfPresentationHidIt() {
        guard editorHiddenForPresentation else { return }
        let window = editorWindowHiddenForPresentation
        editorHiddenForPresentation = false
        editorWindowHiddenForPresentation = nil
        guard let window,
              NSApplication.shared.windows.contains(where: { $0 === window }) else {
            return
        }
        showEditorWindow(window)
    }

    private func showEditorWindow() {
        guard let window = locateEditorWindow() else { return }
        showEditorWindow(window)
    }

    private func showEditorWindow(_ window: NSWindow) {
        editorWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
