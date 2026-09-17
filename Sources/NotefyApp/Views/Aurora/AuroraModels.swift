import SwiftUI

/// One folder as the canvas sees it: a name, a place, and the notes filed in it.
/// `folderID == nil` is the Unfiled tile — where a capture lands before it has
/// been put anywhere, so it has to be reachable from the canvas like any other.
struct AuroraFolderTile: Identifiable {
    let id: String
    let folderID: UUID?
    var name: String
    var point: CGPoint
    var notes: [CanvasNoteSnapshot]
    var tints: [Int]

    var captureCount: Int { notes.reduce(0) { $0 + $1.captureCount } }
    var isUnfiled: Bool { folderID == nil }

    /// Newest first. Opening a folder should put what you were last working on
    /// in front of you, not whatever happens to sort first.
    var notesByRecency: [CanvasNoteSnapshot] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    /// The note to mark as new, when it is recent enough to be worth marking.
    var freshNoteID: URL? {
        guard let newest = notesByRecency.first,
              newest.createdAt > Date().addingTimeInterval(-86_400) else { return nil }
        return newest.url
    }
}

/// Pan and zoom in a reference type, so the AppKit scroll monitor always reads
/// live values — including whether the canvas is still the thing on screen.
@MainActor
final class AuroraCanvasState: ObservableObject {
    @Published var pan: CGSize = .zero
    @Published var zoom: CGFloat = 1
    var enabled = true
    func reset() { pan = .zero; zoom = 1 }
}

enum AuroraViewMode: String { case map, feed }

enum AuroraSort: String, CaseIterable {
    case name, recent, size

    /// Says what the order is, rather than which field it sorts on.
    var label: String {
        switch self {
        case .name: return "A–Z"
        case .recent: return "Recent"
        case .size: return "Most notes"
        }
    }
}

enum AuroraFilter: String, CaseIterable, Identifiable {
    case all, recent
    var id: String { rawValue }
    var label: String { self == .all ? "All folders" : "Recent" }
}

/// Which input a session recording is listening to. The rail offers both.
enum SessionAudioSource: String {
    case systemAudio, microphone
}
