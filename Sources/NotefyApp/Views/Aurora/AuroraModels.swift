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
    case name, size
    var label: String { self == .size ? "Notes" : rawValue.capitalized }
}

enum AuroraFilter: String, CaseIterable, Identifiable {
    case all, recent
    var id: String { rawValue }
    var label: String { self == .all ? "All folders" : "Recent" }
}
