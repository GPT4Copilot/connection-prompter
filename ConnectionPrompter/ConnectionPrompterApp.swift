import AppKit
import SwiftUI

@main
struct ConnectionPrompterApp: App {
    @State private var coordinator: AppCoordinator

    init() {
        let store = FileSessionStore(directoryURL: Self.sessionDirectory)
        let state = AppState(store: store)
        _coordinator = State(initialValue: AppCoordinator(state: state))
    }

    var body: some Scene {
        WindowGroup {
            EditorView(coordinator: coordinator)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    coordinator.state.saveImmediately()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandMenu("主持") {
                Button("显示或隐藏主持浮窗") {
                    coordinator.togglePresenter()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                Button("上一页") { coordinator.previousPage() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("下一页") { coordinator.nextPage() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("切换鼠标穿透") { coordinator.toggleClickThrough() }
                    .keyboardShortcut("x", modifiers: [.command, .option])
            }
        }
    }

    private static var sessionDirectory: URL {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let sessionName = ProcessInfo.processInfo.environment["CONNECTION_PROMPTER_UI_TEST_SESSION"]
                ?? String(ProcessInfo.processInfo.processIdentifier)
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("ConnectionPrompterUITest-\(sessionName)")
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("ConnectionPrompter", isDirectory: true)
    }
}
