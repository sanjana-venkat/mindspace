import Foundation
import AppKit

public struct ExplorationStep: Codable {
    public let timestamp: Date
    public let appName: String
    public let windowTitle: String
    public let url: String?
    public let selectedText: String?
    public let screenshotPath: String?
    
    public init(appName: String, windowTitle: String, url: String? = nil, selectedText: String? = nil, screenshotPath: String? = nil) {
        self.timestamp = Date()
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.screenshotPath = screenshotPath
    }
}

public class ExplorationTracker {
    public private(set) var isTracking = false
    public private(set) var isPaused = false
    private var lastActiveApp: String = ""
    private var lastActiveTitle: String = ""
    private var steps: [ExplorationStep] = []
    private let outputDirectory: URL
    
    public var onStepCaptured: ((ExplorationStep) -> Void)?
    
    public init(outputDir: URL) {
        self.outputDirectory = outputDir
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }
    
    public func start() {
        guard !isTracking else { return }
        isTracking = true
        steps = []
        
        print("🚀 Notefy Exploration Tracker Started!")
        print("Watching active window changes...")
        
        // Start watching didActivateApplicationNotification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Force capture the currently active app immediately
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            captureCurrentState(activeApp)
        }
    }
    
    public func stop() -> [ExplorationStep] {
        guard isTracking else { return [] }
        isTracking = false
        
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        print("🛑 Notefy Exploration Tracker Stopped.")
        return steps
    }
    
    public func pause() {
        guard isTracking && !isPaused else { return }
        isPaused = true
        print("⏸️ Exploration tracker paused.")
    }
    
    public func resume() {
        guard isTracking && isPaused else { return }
        isPaused = false
        print("▶️ Exploration tracker resumed.")
    }
    
    @objc private func handleAppChange(_ notification: Notification) {
        guard isTracking && !isPaused else { return }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            captureCurrentState(app)
        }
    }
    
    public func captureCurrentState(_ app: NSRunningApplication) {
        guard isTracking && !isPaused else { return }
        let appName = app.localizedName ?? "Unknown App"
        let windowTitle = getActiveWindowTitle(for: app) ?? ""
        
        // Skip background or system elements
        if appName == "Finder" && windowTitle.isEmpty { return }
        
        var url: String? = nil
        var pageTitle = windowTitle
        
        // Special case: Google Chrome
        if appName == "Google Chrome" {
            let chromeDetails = getChromeTabDetails()
            url = chromeDetails.url
            if let title = chromeDetails.title {
                pageTitle = title
            }
        }
        
        // Avoid duplicate captures if app & title haven't changed
        if appName == lastActiveApp && pageTitle == lastActiveTitle {
            return
        }
        
        lastActiveApp = appName
        lastActiveTitle = pageTitle
        
        // Capture highlighted text from clipboard or accessibility
        let selectedText = getSelectedText()
        
        // Take screenshot asynchronously
        let screenshotFilename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let screenshotURL = self.outputDirectory.appendingPathComponent(screenshotFilename)
        
        // Capture screenshot
        if ScreenCapturer.takeScreenshot(saveTo: screenshotURL) {
            let step = ExplorationStep(
                appName: appName,
                windowTitle: pageTitle,
                url: url,
                selectedText: selectedText,
                screenshotPath: screenshotURL.path
            )
            steps.append(step)
            onStepCaptured?(step)
        } else {
            let step = ExplorationStep(
                appName: appName,
                windowTitle: pageTitle,
                url: url,
                selectedText: selectedText,
                screenshotPath: nil
            )
            steps.append(step)
            onStepCaptured?(step)
        }
    }
    
    // Read selected text using AppleScript or Clipboard
    private func getSelectedText() -> String? {
        // Option A: Quick AppleScript to trigger cmd+c and check pasteboard
        let originalPasteboard = NSPasteboard.general.string(forType: .string)
        
        let source = """
        tell application "System Events"
            keystroke "c" using {command down}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        
        // Wait a tiny fraction for clipboard to update
        Thread.sleep(forTimeInterval: 0.1)
        
        let currentPasteboard = NSPasteboard.general.string(forType: .string)
        
        // Restore pasteboard so we don't mess up user clipboard
        if let original = originalPasteboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(original, forType: .string)
        }
        
        // If it changed, return the copied selection
        if currentPasteboard != originalPasteboard {
            return currentPasteboard?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    // Extract active Google Chrome tab URL & Title via AppleScript
    private func getChromeTabDetails() -> (url: String?, title: String?) {
        let source = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                tell active tab of first window
                    return {URL, title}
                end tell
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return (nil, nil) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        
        if error != nil {
            return (nil, nil)
        }
        
        // NSAppleEventDescriptor lists are indexed starting from 1
        if result.numberOfItems == 2,
           let url = result.atIndex(1)?.stringValue,
           let title = result.atIndex(2)?.stringValue {
            return (url, title)
        }
        
        return (nil, nil)
    }
    
    // Get Window Title using CGWindowList API
    private func getActiveWindowTitle(for app: NSRunningApplication) -> String? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else {
            return nil
        }
        
        for info in windowListInfo {
            guard let dict = info as? NSDictionary,
                  let windowOwnerPID = dict[kCGWindowOwnerPID as String] as? Int,
                  windowOwnerPID == app.processIdentifier,
                  let windowLayer = dict[kCGWindowLayer as String] as? Int,
                  windowLayer == 0, // Main window layer
                  let windowName = dict[kCGWindowName as String] as? String else {
                continue
            }
            return windowName
        }
        return nil
    }
}
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
import Foundation
import AVFoundation

public class VoiceRecorder {
    private var audioRecorder: AVAudioRecorder?
    public private(set) var isRecording = false
    
    public init() {}
    
    public func startRecording(saveTo url: URL) -> Bool {
        guard !isRecording else { return false }
        
        // Define audio format: AAC, compact and clear for dictation
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0, // 16kHz is ideal for speech transcription
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard let recorder = audioRecorder else {
                print("⚠️ Failed to initialize audio recorder instance.")
                return false
            }
            
            if recorder.prepareToRecord() {
                recorder.record()
                isRecording = true
                print("🎙️ Voice thought recording started. Saving to: \(url.path)")
                return true
            } else {
                print("⚠️ Failed to prepare AVAudioRecorder.")
                return false
            }
        } catch {
            print("⚠️ Error starting audio recording: \(error.localizedDescription)")
            return false
        }
    }
    
    public func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        isRecording = false
        audioRecorder = nil
        print("🎙️ Voice thought recording finished.")
    }
}
import Foundation

public class ExplorationSummarizer {
    
    // Process raw steps, filter out noise, and build a formatted markdown note
    public static func summarize(steps: [ExplorationStep]) -> String {
        guard !steps.isEmpty else {
            return "# Notefy Exploration Summary\nNo exploration data captured."
        }
        
        // Define apps classified as context-switching/communication noise
        let noisyApps = ["Slack", "Microsoft Teams", "Mail", "Messages", "Discord", "Telegram"]
        
        // Filter out noise
        let filteredSteps = steps.filter { step in
            let isNoiseApp = noisyApps.contains(step.appName)
            
            // Filter criteria: Keep it if it has selected text, or if it is not a known communication noise app
            if step.selectedText != nil {
                return true
            }
            return !isNoiseApp
        }
        
        var output = ""
        output += "# Notefy Exploration Summary\n"
        output += "Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n"
        output += "Duration: Captured \(steps.count) events (Filtered down to \(filteredSteps.count) relevant actions)\n\n"
        
        output += "## 📝 Key Takeaways & Research Findings\n"
        
        var citations: [String] = []
        
        if filteredSteps.isEmpty {
            output += "Only context-switching noise was captured during this brief exploration session.\n"
        } else {
            for step in filteredSteps {
                let timeStr = DateFormatter.localizedString(from: step.timestamp, dateStyle: .none, timeStyle: .medium)
                
                // Track source for citations
                let sourceIdentifier: String
                if let url = step.url {
                    sourceIdentifier = "\(step.appName) — [\(step.windowTitle)](\(url))"
                } else {
                    sourceIdentifier = "\(step.appName) — \(step.windowTitle)"
                }
                
                if !citations.contains(sourceIdentifier) {
                    citations.append(sourceIdentifier)
                }
                
                let citationIndex = citations.firstIndex(of: sourceIdentifier)! + 1
                
                output += "### • [\(timeStr)] On \(step.appName) [\(citationIndex)]\n"
                output += "  Active Window: *\(step.windowTitle)*\n"
                
                if let selected = step.selectedText {
                    output += "  > **Highlighted Text**: \"\(selected)\"\n"
                }
                
                if let screenshot = step.screenshotPath {
                    output += "  *Screenshot recorded: \(URL(fileURLWithPath: screenshot).lastPathComponent)*\n"
                }
                output += "\n"
            }
        }
        
        // Output Citations List
        if !citations.isEmpty {
            output += "## 🌐 Sources & Citations\n"
            for (index, citation) in citations.enumerated() {
                output += "[\(index + 1)] \(citation)\n"
            }
        }
        
        // Context-Switching Noise Filter logs for verification
        let filteredOut = steps.filter { step in
            let isNoiseApp = noisyApps.contains(step.appName)
            return isNoiseApp && step.selectedText == nil
        }
        
        if !filteredOut.isEmpty {
            output += "\n## 🧹 Filtered Noise Logs (Removed by AI Agent)\n"
            for noise in filteredOut {
                output += "• Removed active focus on **\(noise.appName)**: *\(noise.windowTitle)*\n"
            }
        }
        
        return output
    }
}
import Foundation
import AppKit
import Dispatch

// Setup active paths
let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
let notefySessionDir = desktopURL.appendingPathComponent("Notefy_Sessions")

print("==================================================")
print("             NOTEFY macOS PORTABLE DECK            ")
print("==================================================")
print("Session output directory: \(notefySessionDir.path)")

// Initialize modules
let tracker = ExplorationTracker(outputDir: notefySessionDir)
let recorder = VoiceRecorder()

var recordingSessionCount = 0

// Setup callbacks for Tracker
tracker.onStepCaptured = { step in
    print("\n🔍 [Captured Event] on: \(step.appName)")
    print("   Title: \(step.windowTitle)")
    if let url = step.url {
        print("   URL: \(url)")
    }
    if let selection = step.selectedText {
        print("   Highlight: \"\(selection)\"")
    }
    if let screenshot = step.screenshotPath {
        print("   Screenshot saved: \(URL(fileURLWithPath: screenshot).lastPathComponent)")
    }
}

// Function to print console menu
func printMenu() {
    print("\n---------------- MENU CONTROLS ----------------")
    if !tracker.isTracking {
        print("[E] Start new Exploration Tracker session")
    } else {
        print("[E] Finish Exploration Tracker & compile summary")
        if tracker.isTracking {
            print("[P] Pause / Resume tracking")
        }
    }
    
    if tracker.isTracking {
        if !recorder.isRecording {
            print("[R] Record inline Audio Voice Thought")
        } else {
            print("[R] Stop recording Audio Voice Thought")
        }
    }
    print("[Q] Quit Notefy")
    print("-----------------------------------------------")
    print("Select option: ", terminator: "")
    fflush(stdout)
}

// Global thread control
let consoleQueue = DispatchQueue(label: "notefy.console.reader")

consoleQueue.async {
    printMenu()
    
    while let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        switch input {
        case "e":
            DispatchQueue.main.async {
                if !tracker.isTracking {
                    tracker.start()
                    print("\n🟢 Tracking is active! Switch tabs/windows to capture logs.")
                } else {
                    let steps = tracker.stop()
                    print("\n📊 Compiling session findings...")
                    let summaryMarkdown = ExplorationSummarizer.summarize(steps: steps)
                    
                    // Save final markdown note to desktop
                    let outputFilename = "Exploration_Summary_\(Int(Date().timeIntervalSince1970)).md"
                    let outputURL = notefySessionDir.appendingPathComponent(outputFilename)
                    
                    do {
                        try summaryMarkdown.write(to: outputURL, atomically: true, encoding: .utf8)
                        print("\n✨ Done! Exploration notes compiled successfully.")
                        print("💾 Document saved: \(outputURL.path)")
                    } catch {
                        print("⚠️ Error saving summary markdown: \(error.localizedDescription)")
                    }
                }
                printMenu()
            }
            
        case "p":
            DispatchQueue.main.async {
                if tracker.isTracking {
                    if tracker.isPaused {
                        tracker.resume()
                        print("\n▶️ Tracking Resumed.")
                    } else {
                        tracker.pause()
                        print("\n⏸️ Tracking Paused.")
                    }
                } else {
                    print("\n⚠️ No active exploration session to pause.")
                }
                printMenu()
            }
            
        case "r":
            DispatchQueue.main.async {
                if tracker.isTracking {
                    if !recorder.isRecording {
                        recordingSessionCount += 1
                        let audioURL = notefySessionDir.appendingPathComponent("voice_note_\(recordingSessionCount).aac")
                        if recorder.startRecording(saveTo: audioURL) {
                            print("\n🎙️ Dictation active. Speak clearly...")
                        }
                    } else {
                        recorder.stopRecording()
                        print("\n🎙️ Saved voice thought.")
                    }
                } else {
                    print("\n⚠️ Voice thoughts can only be recorded during active exploration.")
                }
                printMenu()
            }
            
        case "q":
            print("\n👋 Exiting Notefy. Clean up resources...")
            DispatchQueue.main.async {
                _ = tracker.stop()
                recorder.stopRecording()
                exit(0)
            }
            
        default:
            print("\n❌ Invalid option. Try again.")
            printMenu()
        }
    }
}

// Start Main thread Dispatch Loop (required for AppKit workspace observers)
dispatchMain()
