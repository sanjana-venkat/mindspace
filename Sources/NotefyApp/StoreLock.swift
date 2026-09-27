import Foundation
import AppKit

/// One copy of Mindspace per data directory.
///
/// macOS refuses to launch the same app bundle twice, but it has nothing to say
/// about two *different* bundles: a build sitting on the Desktop and the copy in
/// /Applications are, as far as it is concerned, two unrelated programs. Both
/// then scan and rewrite the same `workspace.json`, and whichever one writes
/// last wins — including a copy that has been running for a week and whose
/// picture of your folders is a week old. Notes themselves survive that, because
/// they are found by scanning the directory, but folder organization does not.
///
/// An advisory `flock` is the right instrument here. The kernel releases it when
/// the process dies, however it dies, so a crash or a `kill -9` cannot strand a
/// lock the way a file full of process IDs can.
final class StoreLock {
    static let shared = StoreLock()

    struct Holder {
        var pid: pid_t
        var path: String
        var since: Date

        /// "Mindspace.app" out of a long path, for a sentence a person reads.
        var appName: String {
            let url = URL(fileURLWithPath: path)
            for component in url.pathComponents.reversed() where component.hasSuffix(".app") {
                return component
            }
            return url.lastPathComponent
        }

        var isStillAlive: Bool { kill(pid, 0) == 0 || errno == EPERM }
    }

    /// Non-nil when another copy already holds the directory, in which case this
    /// process must not touch a single file in it.
    private(set) var blockedBy: Holder?
    private(set) var directory: URL?

    /// Held for the lifetime of the process. Never closed: closing releases the
    /// lock, and there is no moment before termination when that would be right.
    private var descriptor: Int32 = -1

    private init() {}

    @discardableResult
    func acquire(directory: URL) -> Bool {
        self.directory = directory
        let lockURL = directory.appendingPathComponent(".lock")

        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            // If the lock file cannot even be opened the directory is unusable
            // for other reasons, and refusing to launch would only hide those.
            return true
        }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            descriptor = fd
            writeOurselves(to: fd)
            blockedBy = nil
            return true
        }

        // Someone else has it. Read who, then let go of our own handle.
        blockedBy = readHolder(from: lockURL)
        close(fd)
        return false
    }

    private func writeOurselves(to fd: Int32) {
        let record: [String: Any] = [
            "pid": Int(getpid()),
            "path": Bundle.main.bundlePath,
            "since": Date().timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
        ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = write(fd, base, buffer.count)
        }
        fsync(fd)
    }

    private func readHolder(from url: URL) -> Holder? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int,
              let path = object["path"] as? String
        else { return nil }
        let since = object["since"] as? TimeInterval ?? Date().timeIntervalSince1970
        return Holder(pid: pid_t(pid), path: path, since: Date(timeIntervalSince1970: since))
    }

    /// Bring the copy that is actually running to the front, so "already open"
    /// is a thing you can act on rather than only be told.
    func revealHolder() {
        guard let holder = blockedBy else { return }
        let url = URL(fileURLWithPath: holder.path)
        guard url.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
