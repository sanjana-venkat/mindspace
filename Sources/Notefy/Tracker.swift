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
    
    public func captureCustomStep(_ step: ExplorationStep) {
        guard isTracking && !isPaused else { return }
        steps.append(step)
        onStepCaptured?(step)
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
