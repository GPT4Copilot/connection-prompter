import AppKit
import Observation

@MainActor
@Observable
final class AppCoordinator {
    let state: AppState

    @ObservationIgnored private var panelController: PresenterPanelController?
    @ObservationIgnored private var hotkeyManager: GlobalHotkeyManager?
    @ObservationIgnored private var connected = false

    init(state: AppState) {
        self.state = state
    }

    func connectIfNeeded() {
        guard !connected else { return }
        connected = true
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
        }
    }

    func showPresenter() {
        connectIfNeeded()
        state.showPresenter()
        panelController?.show()
    }

    func hidePresenter() {
        state.hidePresenter()
        panelController?.hide()
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
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first(where: { !($0 is NSPanel) })?
            .makeKeyAndOrderFront(nil)
    }
}
