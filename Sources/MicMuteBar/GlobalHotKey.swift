import Carbon
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "InstallEventHandler failed (\(status))."
        case .register(let status):
            return "RegisterEventHotKey failed (\(status))."
        }
    }
}

@MainActor
final class GlobalHotKey {
    fileprivate static var nextID: UInt32 = 1
    fileprivate static var eventHandlerRef: EventHandlerRef?
    fileprivate static var callbacks = [UInt32: () -> Void]()

    private var hotKeyRef: EventHotKeyRef?
    private var callbackID: UInt32?

    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) throws {
        unregister()
        try Self.installHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID &+= 1
        Self.callbacks[id] = onPress
        callbackID = id

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4D4252), id: id) // "MMBR"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            Self.callbacks[id] = nil
            callbackID = nil
            throw GlobalHotKeyError.register(status)
        }

        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let callbackID {
            Self.callbacks[callbackID] = nil
            self.callbackID = nil
        }
    }
    private static func installHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        guard status == noErr, let handlerRef else {
            throw GlobalHotKeyError.installHandler(status)
        }

        eventHandlerRef = handlerRef
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, _ in
    guard let eventRef else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        return status
    }

    Task { @MainActor in
        GlobalHotKey.callbacks[hotKeyID.id]?()
    }
    return noErr
}
