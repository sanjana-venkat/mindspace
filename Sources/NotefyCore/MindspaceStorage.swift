import Foundation

public enum MindspaceStorage {
    public static let directoryName = "Mindspace"
    public static let legacyDirectoryName = "Notefy_Sessions"

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let desktop = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        return resolveDirectory(in: desktop, fileManager: fileManager)
    }

    /// Moves the pre-Mindspace data folder when possible. If migration fails, the
    /// legacy folder remains active so an update can never make existing notes
    /// appear to disappear.
    public static func resolveDirectory(
        in parentDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let current = parentDirectory.appendingPathComponent(directoryName, isDirectory: true)
        let legacy = parentDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: current.path),
           fileManager.fileExists(atPath: legacy.path) {
            do {
                try fileManager.moveItem(at: legacy, to: current)
            } catch {
                return legacy
            }
        }

        do {
            try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
            return current
        } catch {
            return fileManager.fileExists(atPath: legacy.path) ? legacy : current
        }
    }
}
