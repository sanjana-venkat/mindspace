import AppKit
import Carbon
import SwiftUI

/// The six things you can trigger from anywhere.
enum HotkeyAction: String, CaseIterable, Identifiable {
    case captureRail, region, page, selectedText, voice, meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureRail: return "Capture rail"
        case .region: return "Grab a region"
        case .page: return "Grab this window"
        case .selectedText: return "Keep the text I've selected"
        case .voice: return "Voice note"
        case .meeting: return "Meeting note"
        }
    }

    var detail: String {
        switch self {
        case .captureRail: return "Your floating sidebar — click to capture, record audio, and the rest"
        case .region: return "Drag a box around anything"
        case .page: return "Whatever window you're looking at"
        case .selectedText: return "Just the bit you've highlighted"
        case .voice: return "Talk straight into the note"
        case .meeting: return "You and the room, transcribed"
        }
    }

    var defaultKeyCode: UInt32 {
        switch self {
        case .captureRail: return UInt32(kVK_ANSI_K)
        case .region: return UInt32(kVK_ANSI_G)
        case .page: return UInt32(kVK_ANSI_P)
        case .selectedText: return UInt32(kVK_ANSI_T)
        case .voice: return UInt32(kVK_ANSI_A)
        case .meeting: return UInt32(kVK_ANSI_M)
        }
    }

    /// ⌘⇧ by default — rare enough to be free, common enough to be memorable.
    static let defaultModifiers = UInt32(cmdKey | shiftKey)
}

struct HotkeyBinding: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier mask

    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + HotkeyBindings.name(for: keyCode)
    }
}

enum HotkeyBindings {
    private static func key(_ action: HotkeyAction) -> String { "mindspace.hotkey.\(action.rawValue)" }

    static func binding(for action: HotkeyAction) -> HotkeyBinding {
        let defaults = UserDefaults.standard
        let stored = defaults.dictionary(forKey: key(action))
        if let code = stored?["keyCode"] as? Int, let mods = stored?["modifiers"] as? Int {
            return HotkeyBinding(keyCode: UInt32(code), modifiers: UInt32(mods))
        }
        return HotkeyBinding(keyCode: action.defaultKeyCode, modifiers: HotkeyAction.defaultModifiers)
    }

    static func set(_ binding: HotkeyBinding, for action: HotkeyAction) {
        UserDefaults.standard.set(["keyCode": Int(binding.keyCode), "modifiers": Int(binding.modifiers)],
                                  forKey: key(action))
    }

    static func resetAll() {
        for action in HotkeyAction.allCases { UserDefaults.standard.removeObject(forKey: key(action)) }
    }

    static func label(for action: HotkeyAction) -> String { binding(for: action).label }

    /// Another action already answering to this combination.
    static func conflict(for binding: HotkeyBinding, excluding action: HotkeyAction) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != action && self.binding(for: $0) == binding }
    }

    /// Carbon modifier mask from an AppKit event.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    static func name(for keyCode: UInt32) -> String {
        let named: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "esc", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6"
        ]
        if let name = named[keyCode] { return name }

        // Ask the current keyboard layout what this key prints, so the label
        // matches the user's actual keyboard rather than a hard-coded US map.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return errSecAllocate
            }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

/// Listens for one key combination and hands it back. Uses an AppKit monitor
/// rather than SwiftUI's key handling so modifiers arrive with the key, and
/// swallows the event so recording ⌘S doesn't also save something.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var onCapture: ((HotkeyBinding) -> Void)?

    func start(_ onCapture: @escaping (HotkeyBinding) -> Void) {
        stop()
        self.onCapture = onCapture
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            // Escape leaves the binding alone.
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in self.stop() }
                return nil
            }
            let modifiers = HotkeyBindings.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return nil }   // a bare key would fire while typing
            let binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            Task { @MainActor in
                self.onCapture?(binding)
                self.stop()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onCapture = nil
    }
}
