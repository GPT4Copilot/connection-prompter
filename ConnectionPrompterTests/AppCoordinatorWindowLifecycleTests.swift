import AppKit
import XCTest
@testable import ConnectionPrompter

final class AppCoordinatorWindowLifecycleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    @MainActor
    func testPresentationHidesAndRestoresVisibleEditorWindow() {
        let window = makeEditorWindow(visible: true)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: true)

        coordinator.showPresenter()
        XCTAssertFalse(window.isVisible)

        coordinator.hidePresenter()
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testKeepEditorVisibleSettingLeavesVisibleWindowUnchanged() {
        let window = makeEditorWindow(visible: true)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: false)

        coordinator.showPresenter()
        XCTAssertTrue(window.isVisible)

        coordinator.hidePresenter()
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testHidingPresenterDoesNotRestoreEditorHiddenOutsidePresentation() {
        let window = makeEditorWindow(visible: true)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: false)

        coordinator.showPresenter()
        window.orderOut(nil)
        coordinator.hidePresenter()

        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testReturnToEditorAlwaysShowsEditorWindow() {
        let window = makeEditorWindow(visible: false)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: false)

        coordinator.returnToEditor()

        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testInitiallyHiddenEditorIsNotRestoredWhenPresentationEnds() {
        let window = makeEditorWindow(visible: false)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: true)

        coordinator.showPresenter()
        coordinator.hidePresenter()

        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testRepeatedShowDoesNotResampleChangedHidePreference() {
        let window = makeEditorWindow(visible: true)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: false)

        coordinator.showPresenter()
        coordinator.state.preferences.shouldHideEditorWhenPresenting = true
        coordinator.showPresenter()

        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testChangedHidePreferenceAppliesToNextPresentation() {
        let window = makeEditorWindow(visible: true)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: false)

        coordinator.showPresenter()
        coordinator.state.preferences.shouldHideEditorWhenPresenting = true
        coordinator.hidePresenter()
        coordinator.showPresenter()

        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testEndingPresentationDoesNotRestoreReplacementForReleasedEditor() {
        var coordinator: AppCoordinator!
        autoreleasepool {
            let originalWindow = makeEditorWindow(
                visible: true,
                releasedWhenClosed: true
            )
            coordinator = makeCoordinator(
                editorWindow: originalWindow,
                hidesEditor: true
            )
            coordinator.showPresenter()
            originalWindow.close()
            XCTAssertFalse(
                NSApplication.shared.windows.contains { $0 === originalWindow }
            )
        }

        let existingReplacement = NSApplication.shared.windows.first {
            !($0 is NSPanel)
        }
        let replacement = existingReplacement ?? makeEditorWindow(visible: false)
        let replacementWasVisible = replacement.isVisible
        replacement.orderOut(nil)
        defer {
            if existingReplacement == nil {
                replacement.close()
            } else if replacementWasVisible {
                replacement.orderFront(nil)
            } else {
                replacement.orderOut(nil)
            }
        }

        coordinator.hidePresenter()
        XCTAssertFalse(replacement.isVisible)

        coordinator.returnToEditor()
        XCTAssertTrue(replacement.isVisible)
    }

    @MainActor
    func testRestoredVisiblePresentationHidesAndRestoresEditor() {
        let window = makeEditorWindow(visible: true)
        defer { window.close() }
        let coordinator = makeCoordinator(editorWindow: window, hidesEditor: true)
        coordinator.state.showPresenter()

        coordinator.connectIfNeeded()
        XCTAssertFalse(window.isVisible)

        coordinator.hidePresenter()
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    private func makeCoordinator(
        editorWindow: NSWindow,
        hidesEditor: Bool
    ) -> AppCoordinator {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        let state = AppState(store: FileSessionStore(directoryURL: directory))
        state.preferences.shouldHideEditorWhenPresenting = hidesEditor
        return AppCoordinator(state: state, editorWindow: editorWindow)
    }

    @MainActor
    private func makeEditorWindow(
        visible: Bool,
        releasedWhenClosed: Bool = false
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = releasedWhenClosed
        if visible {
            window.orderFront(nil)
        }
        return window
    }
}
