import Foundation

public class ScreenCapturer {
    public static func takeScreenshot(saveTo fileURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x flag takes screen capture silently without sound
        process.arguments = ["-x", fileURL.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("⚠️ Screencapture command execution failed: \(error.localizedDescription)")
            return false
        }
    }
}
