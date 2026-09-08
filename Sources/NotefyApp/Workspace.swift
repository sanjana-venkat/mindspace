import Foundation

/// A user-created folder for organizing notes. Folders can nest (parentID),
/// but notes only ever live in the workspace's flat session directory —
/// folder membership is metadata, not a real filesystem move.
struct NoteFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?
    /// Where the folder sits on the infinite canvas. Optional so workspace
    /// files written before the canvas existed still decode; folders without
    /// a point get laid out on a grid the first time they are shown.
    var x: Double?
    var y: Double?

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, x: Double? = nil, y: Double? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.x = x
        self.y = y
    }
}

/// Per-note metadata that isn't part of the note's own content: which folder
/// it's filed under, whether it's pinned, and when it was last opened (for
/// the default "most recent" sort).
struct NoteMeta: Codable {
    var folderID: UUID?
    var pinned: Bool = false
    var lastOpenedAt: Date = Date()
    /// Optional so existing workspace files decode without migration.
    var canvasPosition: Int?
}

struct Workspace: Codable {
    var folders: [NoteFolder] = []
    var noteMeta: [String: NoteMeta] = [:] // keyed by the note file's lastPathComponent

    static func load(from url: URL) -> Workspace {
        guard let data = try? Data(contentsOf: url),
              let workspace = try? JSONDecoder().decode(Workspace.self, from: data) else {
            return Workspace()
        }
        return workspace
    }

    func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
