import AppKit

/// Remembers whose work a capture interrupted, and gives the screen back.
///
/// Mindspace has to come forward for some of what it does — the region overlay
/// needs the mouse, the review panel needs the keyboard — but coming forward
/// raises every window the app owns, so finishing a capture dropped the whole
/// Mindspace window on top of whatever you were doing. That is the opposite of
/// the point: the moon is there so you can keep working and open the app when
/// *you* want it.
///
/// The app to return to has to be noted at the very start of a capture. By the
/// time the review panel appears, the region overlay has already made Mindspace
/// frontmost, so asking then just answers "Mindspace" — which is exactly why
/// the old restore never fired for screenshots.
@MainActor
enum FocusKeeper {
    private static var interrupted: NSRunningApplication?

    /// Call as a capture begins, before anything of ours takes the screen.
    static func remember() {
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        interrupted = front
    }

    /// Call when the capture is done with the screen.
    static func restore() {
        guard let interrupted, !interrupted.isTerminated else {
            self.interrupted = nil
            return
        }
        self.interrupted = nil
        interrupted.activate()
    }

    /// Forget without returning — for when the person deliberately came to
    /// Mindspace, so sending them away would be wrong.
    static func forget() {
        interrupted = nil
    }
}
