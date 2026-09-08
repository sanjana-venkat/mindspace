import Carbon
import SwiftUI

/// The six things you can trigger from anywhere. Modifiers are fixed at ⌘⇧ —
/// that pair is rarely taken and keeps every Mindspace shortcut recognisable —
/// so a binding is just the letter.
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
        case .captureRail: return "Everything, in one place"
        case .region: return "Drag a box around anything"
        case .page: return "The window in front of you"
        case .selectedText: return "Only the passage you highlighted"
        case .voice: return "Think out loud into the note"
        case .meeting: return "You and the room, transcribed"
        }
    }

    var defaultLetter: String {
        switch self {
        case .captureRail: return "K"
        case .region: return "G"
        case .page: return "P"
        case .selectedText: return "T"
        case .voice: return "A"
        case .meeting: return "M"
        }
    }
}

enum HotkeyBindings {
    private static func storageKey(_ action: HotkeyAction) -> String {
        "mindspace.hotkey.\(action.rawValue)"
    }

    static func letter(for action: HotkeyAction) -> String {
        let stored = UserDefaults.standard.string(forKey: storageKey(action))
        guard let stored, keyCode(for: stored) != nil else { return action.defaultLetter }
        return stored
    }

    static func set(_ letter: String, for action: HotkeyAction) {
        let upper = letter.uppercased()
        guard keyCode(for: upper) != nil, !isTaken(upper, excluding: action) else { return }
        UserDefaults.standard.set(upper, forKey: storageKey(action))
    }

    static func resetAll() {
        for action in HotkeyAction.allCases {
            UserDefaults.standard.removeObject(forKey: storageKey(action))
        }
    }

    /// Two actions can't share a letter — the second registration would just
    /// fail silently at the Carbon layer.
    static func isTaken(_ letter: String, excluding action: HotkeyAction) -> Bool {
        HotkeyAction.allCases.contains { $0 != action && self.letter(for: $0) == letter.uppercased() }
    }

    static func label(for action: HotkeyAction) -> String { "⌘⇧\(letter(for: action))" }

    static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    static func keyCode(for letter: String) -> UInt32? {
        let map: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
            "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
            "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
            "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
            "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z
        ]
        guard let code = map[letter.uppercased()] else { return nil }
        return UInt32(code)
    }
}
