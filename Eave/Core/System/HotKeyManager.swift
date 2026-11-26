import Carbon
import Foundation

/// Global keyboard shortcut manager built directly on Carbon's RegisterEventHotKey.
/// Zero third-party dependencies and fully safe under Swift 6 concurrency.
@MainActor
final class HotKeyManager {
    private static let signature: OSType = 0x45415645 // "EAVE"

    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeys: [UInt32: (action: HotKeyAction, ref: EventHotKeyRef)] = [:]
    private var actionToID: [HotKeyAction: UInt32] = [:]
    private var nextID: UInt32 = 1

    var onTrigger: ((HotKeyAction) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        // Event handler cleanup is performed via tearDown() before release.
    }

    func tearDown() {
        for entry in registeredHotKeys.values {
            UnregisterEventHotKey(entry.ref)
        }
        registeredHotKeys.removeAll()
        actionToID.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    func register(settings: EaveSettings) {
        for action in HotKeyAction.allCases {
            register(action: action, combo: settings.hotKey(for: action))
        }
    }

    /// Registers (or clears, when `combo` is nil) the global shortcut for `action`.
    /// Returns false when the system refused the combo (typically already taken by another app).
    @discardableResult
    func register(action: HotKeyAction, combo: KeyCombo?) -> Bool {
        // Unregister existing binding for this action first.
        if let oldID = actionToID.removeValue(forKey: action),
           let existing = registeredHotKeys.removeValue(forKey: oldID) {
            UnregisterEventHotKey(existing.ref)
        }

        guard let combo else { return true }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            registeredHotKeys[id] = (action: action, ref: ref)
            actionToID[action] = id
            return true
        }
        return false
    }

    /// Temporarily releases every registered shortcut (e.g. while the recorder captures a new combo,
    /// so pressing the current shortcut records it instead of firing it).
    func suspendAll() {
        for entry in registeredHotKeys.values {
            UnregisterEventHotKey(entry.ref)
        }
        registeredHotKeys.removeAll()
        actionToID.removeAll()
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr, hotKeyID.signature == HotKeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let pressedID = hotKeyID.id
            Task { @MainActor in
                manager.handlePressed(id: pressedID)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
    }

    private func handlePressed(id: UInt32) {
        guard let entry = registeredHotKeys[id] else { return }
        onTrigger?(entry.action)
    }
}
