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
    /// A colour that was chosen rather than hashed from the id. Optional, so
    /// every workspace written before this existed still decodes unchanged.
    var tint: Int?

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil,
         x: Double? = nil, y: Double? = nil, tint: Int? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.x = x
        self.y = y
        self.tint = tint
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

/// What the bucket of not-yet-filed notes is called. It is not a folder, so it
/// has no record to rename; this is the name people chose for it instead.
enum UnfiledName {
    static let key = "aurora.unfiled.name"
    static let fallback = "Ungrouped"

    static var current: String {
        let saved = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? fallback : saved
    }

    static func set(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: key)
    }
}
