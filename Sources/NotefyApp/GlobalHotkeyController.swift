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

        // ⌘⇧M: start/stop meeting notes
        register(id: 2, keyCode: UInt32(kVK_ANSI_M), callback: onMeeting)
        // Manual session capture hotkeys.
        register(id: 3, keyCode: UInt32(kVK_ANSI_T), callback: onSelectedText)
        register(id: 4, keyCode: UInt32(kVK_ANSI_P), callback: onPage)
        register(id: 5, keyCode: UInt32(kVK_ANSI_G), callback: onRegion)
        register(id: 6, keyCode: UInt32(kVK_ANSI_A), callback: onSessionAudio)
        // ⌘⇧K: summon/dismiss Kami's capture rail.
        register(id: 7, keyCode: UInt32(kVK_ANSI_K), callback: onCaptureRail)
    }

    deinit {
        for reference in references {
            if let reference { UnregisterEventHotKey(reference) }
        }
        for id in 1...7 { notefyHotkeyCallbacks[UInt32(id)] = nil }
    }

    private func register(id: UInt32, keyCode: UInt32, callback: @escaping () -> Void) {
        let signature = FourCharCode(0x4E_54_46_59) // "NTFY"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            notefyHotkeyCallbacks[id] = callback
            references.append(reference)
        } else {
            fputs("[hotkey] Could not register hotkey \(id): \(status)\n", stderr)
        }
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
