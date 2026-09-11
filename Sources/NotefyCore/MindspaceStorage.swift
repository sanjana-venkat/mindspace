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

    /// Resolves an absolute asset reference written before the data directory
    /// was renamed. The folder migration moves the files, but JSON sidecars
    /// created by older versions contain absolute paths and therefore still
    /// point at `Notefy_Sessions`. Existing paths are never changed.
    public static func rebasedAssetPath(
        _ storedPath: String?,
        in currentDirectory: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard let storedPath, !storedPath.isEmpty else { return storedPath }
        if fileManager.fileExists(atPath: storedPath) { return storedPath }

        let oldURL = URL(fileURLWithPath: storedPath)
        let components = oldURL.pathComponents
        if let legacyIndex = components.firstIndex(of: legacyDirectoryName),
           legacyIndex + 1 < components.count {
            let relativeComponents = components[(legacyIndex + 1)...]
            let candidate = relativeComponents.reduce(currentDirectory) {
                $0.appendingPathComponent($1)
            }
            if fileManager.fileExists(atPath: candidate.path) { return candidate.path }
        }

        // Early builds kept every capture at the data-root. This fallback also
        // repairs references whose original parent path was customized.
        let rootCandidate = currentDirectory.appendingPathComponent(oldURL.lastPathComponent)
        return fileManager.fileExists(atPath: rootCandidate.path) ? rootCandidate.path : storedPath
    }
}
