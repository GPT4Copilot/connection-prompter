import Carbon
import Foundation

enum GlobalHotkeyAction: UInt32, Equatable, Sendable {
    case previousPage = 1
    case nextPage = 2
    case toggleClickThrough = 3
    case togglePresenter = 4
    case decreaseAutoScrollSpeed = 5
    case increaseAutoScrollSpeed = 6
}

struct HotkeyDescriptor: Equatable, Sendable {
    let action: GlobalHotkeyAction
    let identifier: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let defaults: [HotkeyDescriptor] = [
        HotkeyDescriptor(
            action: .previousPage,
            identifier: GlobalHotkeyAction.previousPage.rawValue,
            keyCode: UInt32(kVK_UpArrow),
            modifiers: UInt32(cmdKey | optionKey),
            displayName: "⌥⌘↑"
        ),
        HotkeyDescriptor(
            action: .nextPage,
            identifier: GlobalHotkeyAction.nextPage.rawValue,
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(cmdKey | optionKey),
            displayName: "⌥⌘↓"
        ),
        HotkeyDescriptor(
            action: .decreaseAutoScrollSpeed,
            identifier: GlobalHotkeyAction.decreaseAutoScrollSpeed.rawValue,
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(cmdKey | optionKey),
            displayName: "⌥⌘←"
        ),
        HotkeyDescriptor(
            action: .increaseAutoScrollSpeed,
            identifier: GlobalHotkeyAction.increaseAutoScrollSpeed.rawValue,
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(cmdKey | optionKey),
            displayName: "⌥⌘→"
        ),
        HotkeyDescriptor(
            action: .toggleClickThrough,
            identifier: GlobalHotkeyAction.toggleClickThrough.rawValue,
            keyCode: UInt32(kVK_ANSI_X),
            modifiers: UInt32(cmdKey | optionKey),
            displayName: "⌥⌘X"
        ),
        HotkeyDescriptor(
            action: .togglePresenter,
            identifier: GlobalHotkeyAction.togglePresenter.rawValue,
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | optionKey),
            displayName: "⌥⌘P"
        )
    ]
}

@MainActor
protocol HotkeyRegistering: AnyObject {
    func registerDefaultHotkeys() -> [HotkeyDescriptor]
}

@MainActor
final class GlobalHotkeyManager: HotkeyRegistering {
    private static let signature: OSType = 0x4350524D

    private unowned let coordinator: AppCoordinator
    private var handlerReference: EventHandlerRef?
    private var hotkeyReferences: [EventHotKeyRef] = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func registerDefaultHotkeys() -> [HotkeyDescriptor] {
        installHandlerIfNeeded()
        guard handlerReference != nil else { return HotkeyDescriptor.defaults }

        var failures: [HotkeyDescriptor] = []
        for descriptor in HotkeyDescriptor.defaults {
            var reference: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(
                signature: Self.signature,
                id: descriptor.identifier
            )
            let status = RegisterEventHotKey(
                descriptor.keyCode,
                descriptor.modifiers,
                hotkeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )

            if status == noErr, let reference {
                hotkeyReferences.append(reference)
            } else {
                failures.append(descriptor)
            }
        }
        return failures
    }

    private func installHandlerIfNeeded() {
        guard handlerReference == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotkeyID = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard readStatus == noErr,
                      hotkeyID.signature == GlobalHotkeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.perform(actionID: hotkeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerReference
        )
        if status != noErr {
            handlerReference = nil
        }
    }

    private func perform(actionID: UInt32) {
        guard let action = GlobalHotkeyAction(rawValue: actionID) else { return }
        switch action {
        case .previousPage:
            coordinator.previousPage()
        case .nextPage:
            coordinator.nextPage()
        case .decreaseAutoScrollSpeed:
            coordinator.adjustAutoScrollSpeed(by: -0.1)
        case .increaseAutoScrollSpeed:
            coordinator.adjustAutoScrollSpeed(by: 0.1)
        case .toggleClickThrough:
            coordinator.toggleClickThrough()
        case .togglePresenter:
            coordinator.togglePresenter()
        }
    }
}
