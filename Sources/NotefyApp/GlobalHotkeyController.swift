import Carbon
import Foundation

private var notefyHotkeyCallbacks: [UInt32: () -> Void] = [:]
private var notefyHotkeyEventHandler: EventHandlerRef?

private func notefyHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }
    DispatchQueue.main.async {
        notefyHotkeyCallbacks[hotkeyID.id]?()
    }
    return noErr
}

/// Carbon hotkeys work globally without requiring an event tap or Input
/// Monitoring permission.
final class GlobalHotkeyController {
    private var references: [EventHotKeyRef?] = []
    private var started = false
    private let onMeeting: () -> Void
    private let onSelectedText: () -> Void
    private let onPage: () -> Void
    private let onRegion: () -> Void
    private let onSessionAudio: () -> Void
    private let onCaptureRail: () -> Void

    init(
        onMeeting: @escaping () -> Void,
        onSelectedText: @escaping () -> Void,
        onPage: @escaping () -> Void,
        onRegion: @escaping () -> Void,
        onSessionAudio: @escaping () -> Void,
        onCaptureRail: @escaping () -> Void
    ) {
        self.onMeeting = onMeeting
        self.onSelectedText = onSelectedText
        self.onPage = onPage
        self.onRegion = onRegion
        self.onSessionAudio = onSessionAudio
        self.onCaptureRail = onCaptureRail
    }

    func start() {
        guard !started else { return }
        started = true
        Self.installHandlerIfNeeded()

        // Key and modifiers both come from the user's own bindings now.
        failures = []
        let pairs: [(UInt32, HotkeyAction, () -> Void)] = [
            (2, .meeting, onMeeting),
            (3, .selectedText, onSelectedText),
            (4, .page, onPage),
            (5, .region, onRegion),
            (6, .voice, onSessionAudio),
            (7, .captureRail, onCaptureRail)
        ]
        for (id, action, callback) in pairs {
            let binding = HotkeyBindings.binding(for: action)
            if !register(id: id, keyCode: binding.keyCode, modifiers: binding.modifiers, callback: callback) {
                failures.append(action)
            }
        }
    }

    /// Combinations macOS refused — almost always because the system already
    /// owns them (⌘⇧5 belongs to Screenshot until you free it in Settings).
    private(set) var failures: [HotkeyAction] = []

    /// Re-registers everything after a binding changes, and reports what macOS
    /// would not give up.
    @discardableResult
    func restart() -> [HotkeyAction] {
        for case let reference? in references {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        for id in 1...7 { notefyHotkeyCallbacks[UInt32(id)] = nil }
        started = false
        start()
        return failures
    }

    deinit {
        for reference in references {
            if let reference { UnregisterEventHotKey(reference) }
        }
        for id in 1...7 { notefyHotkeyCallbacks[UInt32(id)] = nil }
    }

    @discardableResult
    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                          callback: @escaping () -> Void) -> Bool {
        let signature = FourCharCode(0x4E_54_46_59) // "NTFY"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            notefyHotkeyCallbacks[id] = callback
            references.append(reference)
            return true
        }
        fputs("[hotkey] Could not register hotkey \(id): \(status)\n", stderr)
        return false
    }

    private static func installHandlerIfNeeded() {
        guard notefyHotkeyEventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            notefyHotkeyHandler,
            1,
            &eventType,
            nil,
            &notefyHotkeyEventHandler
        )
    }
}
