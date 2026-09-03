import Foundation
import AppKit
import ApplicationServices

public struct ExplorationStep: Codable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let appName: String
    public let windowTitle: String
    public let url: String?
    public let selectedText: String?
    public let screenshotPath: String?
    public let htmlPath: String?
    public let pageText: String?

    public init(
        appName: String,
        windowTitle: String,
        url: String? = nil,
        selectedText: String? = nil,
        screenshotPath: String? = nil,
        htmlPath: String? = nil,
        pageText: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.screenshotPath = screenshotPath
        self.htmlPath = htmlPath
        self.pageText = pageText
    }
}

public struct CaptureSourceContext: Sendable, Equatable {
    public let appName: String
    public let windowTitle: String
    public let url: String?

    public init(appName: String, windowTitle: String, url: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
    }
}

/// Holds a manually curated exploration session. Nothing is captured until the
/// user invokes a capture command from the UI or a global hotkey.
public final class ExplorationTracker: NSObject {
    public private(set) var isTracking = false
    public private(set) var isPaused = false
    public var onStepCaptured: ((ExplorationStep) -> Void)?

    private let outputDirectory: URL
    private var steps: [ExplorationStep] = []
    private var lastMetadataKey = ""
    private var lastFingerprint: [UInt8]?
    private var lastCaptureDate = Date.distantPast
    private var lastArchivedChromePage = ""
    private var isPolling = false

    public init(
        outputDir: URL,
        pollInterval: TimeInterval = 0.75,
        minimumCaptureInterval: TimeInterval = 1.75,
        visualChangeThreshold: Double = 0.045
    ) {
        self.outputDirectory = outputDir
        super.init()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: outputDir.appendingPathComponent("Chrome_HTML", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    public func start() -> Bool {
        guard !isTracking else { return true }
        isTracking = true
        isPaused = false
        steps = []
        lastMetadataKey = ""
        lastFingerprint = nil
        lastCaptureDate = .distantPast
        lastArchivedChromePage = ""

        return true
    }

    public func stop() -> [ExplorationStep] {
        guard isTracking else { return [] }
        isTracking = false
        isPaused = false
        return steps
    }

    public func pause() {
        guard isTracking else { return }
        isPaused = true
    }

    public func resume() {
        guard isTracking else { return }
        isPaused = false
    }

    public func captureCustomStep(_ step: ExplorationStep) {
        guard isTracking && !isPaused else { return }
        steps.append(step)
        onStepCaptured?(step)
    }

    public func removeStep(id: UUID) {
        steps.removeAll { $0.id == id }
    }

    public func captureCurrentState(_ app: NSRunningApplication) {
        Task { await poll(appOverride: app, force: true) }
    }

    @discardableResult
    /// Reads the frontmost app's current selection WITHOUT capturing it.
    ///
    /// Deliberately does NOT use the synthetic-Copy fallback that
    /// `captureSelectedText` falls back to: this is called on a poll while the
    /// user is still choosing what to highlight, and firing ⌘C at another app
    /// several times a second would stomp their clipboard and fight their
    /// selection. Accessibility-only means it reports nothing for Chromium
    /// views that hide AXSelectedText — that case still works, it just waits
    /// for the timeout and then goes through the copy path once.
    public func peekSelectedText() -> String? {
        guard AXIsProcessTrusted(), isTracking, !isPaused else { return nil }
        guard let text = selectedText()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    public func captureSelectedText() async -> Bool {
        // Permission prompts belong to the app's onboarding flow. Capture paths
        // only inspect current state so a failed action cannot create a prompt loop.
        guard AXIsProcessTrusted() else { return false }
        guard isTracking, !isPaused,
              let app = NSWorkspace.shared.frontmostApplication
        else { return false }

        // Native controls usually expose AXSelectedText. Chromium and some
        // Electron/web views can visibly retain a selection without exposing
        // that attribute, so fall back to a synthetic Copy while restoring the
        // user's clipboard immediately afterward.
        let text: String?
        if let accessibilityText = selectedText() {
            text = accessibilityText
        } else {
            text = await copiedSelectionPreservingClipboard()
        }
        guard let text else { return false }

        let appName = app.localizedName ?? "Unknown App"
        let window = activeWindow(for: app)
        let chrome = appName == "Google Chrome" ? chromeTabDetails() : nil
        let step = ExplorationStep(
            appName: appName,
            windowTitle: chrome?.title ?? window.title,
            url: chrome?.url,
            selectedText: text
        )
        steps.append(step)
        onStepCaptured?(step)
        return true
    }

    @discardableResult
    public func captureActiveWindow() async -> Bool {
        guard isTracking, !isPaused else { return false }
        guard CGPreflightScreenCaptureAccess() else {
            return false
        }
        let count = steps.count
        await poll(force: true)
        return steps.count > count
    }

    public func currentSourceContext() -> CaptureSourceContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = app.localizedName ?? "Unknown App"
        let window = activeWindow(for: app)
        let chrome = appName == "Google Chrome" ? chromeTabDetails() : nil
        return CaptureSourceContext(
            appName: appName,
            windowTitle: chrome?.title ?? window.title,
            url: chrome?.url
        )
    }

    public func captureScreenshotFile(
        _ url: URL,
        label: String = "Selected screen region",
        source: CaptureSourceContext? = nil
    ) {
        guard isTracking, !isPaused else { return }
        let resolved = source ?? currentSourceContext()
        let appName = resolved?.appName ?? "Screen region"
        let title = resolved?.windowTitle ?? ""
        let step = ExplorationStep(
            appName: appName,
            windowTitle: title.isEmpty ? label : title,
            url: resolved?.url,
            selectedText: label,
            screenshotPath: url.path
        )
        steps.append(step)
        onStepCaptured?(step)
    }

    private func poll(appOverride: NSRunningApplication? = nil, force: Bool = false) async {
        guard isTracking, !isPaused, !isPolling,
              let app = appOverride ?? NSWorkspace.shared.frontmostApplication
        else { return }

        isPolling = true
        defer { isPolling = false }

        let appName = app.localizedName ?? "Unknown App"
        let window = activeWindow(for: app)
        if appName == "Finder" && window.title.isEmpty { return }

        let chrome = appName == "Google Chrome" ? chromeTabDetails() : nil
        let title = chrome?.title ?? window.title
        let url = chrome?.url
        let metadataKey = "\(app.bundleIdentifier ?? appName)|\(title)|\(url ?? "")"
        let candidate = outputDirectory.appendingPathComponent(".notefy-candidate-\(UUID().uuidString).png")
        guard await ScreenCapturer.takeScreenshot(saveTo: candidate, windowID: window.id) else { return }
        let fingerprint = ScreenCapturer.visualFingerprint(of: candidate)

        let screenshotURL = outputDirectory.appendingPathComponent("screenshot_\(UUID().uuidString).png")
        do {
            try FileManager.default.moveItem(at: candidate, to: screenshotURL)
        } catch {
            try? FileManager.default.removeItem(at: candidate)
            return
        }

        var htmlPath: String?
        var pageText: String?
        if chrome != nil, metadataKey != lastArchivedChromePage {
            pageText = chromePageValue(
                javascript: "document.body ? document.body.innerText.slice(0, 30000) : ''"
            )
            if let html = chromePageValue(
                javascript: "document.documentElement ? document.documentElement.outerHTML : ''"
            ), !html.isEmpty {
                let htmlURL = outputDirectory
                    .appendingPathComponent("Chrome_HTML", isDirectory: true)
                    .appendingPathComponent("page_\(UUID().uuidString).html")
                if (try? html.write(to: htmlURL, atomically: true, encoding: .utf8)) != nil {
                    htmlPath = htmlURL.path
                }
            }
            lastArchivedChromePage = metadataKey
        }

        let step = ExplorationStep(
            appName: appName,
            windowTitle: title,
            url: url,
            selectedText: selectedText(),
            screenshotPath: screenshotURL.path,
            htmlPath: htmlPath,
            pageText: pageText
        )
        steps.append(step)
        lastMetadataKey = metadataKey
        lastFingerprint = fingerprint
        lastCaptureDate = Date()
        onStepCaptured?(step)
    }

    private func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success, let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(20_000))
    }

    private func copiedSelectionPreservingClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                if let data = item.data(forType: type) { values[type] = data }
            }
        } ?? []

        pasteboard.clearContents()
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        else {
            restorePasteboard(snapshot)
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 140_000_000)
        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        restorePasteboard(snapshot)
        guard let copied, !copied.isEmpty else { return nil }
        return String(copied.prefix(20_000))
    }

    private func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func chromeTabDetails() -> (url: String?, title: String?) {
        let source = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                tell active tab of front window
                    return {URL, title}
                end tell
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return (nil, nil) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems == 2 else { return (nil, nil) }
        return (result.atIndex(1)?.stringValue, result.atIndex(2)?.stringValue)
    }

    private func chromePageValue(javascript: String) -> String? {
        let escaped = javascript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                return execute active tab of front window javascript "\(escaped)"
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }

    private func activeWindow(for app: NSRunningApplication) -> (id: CGWindowID?, title: String) {
        let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return (nil, "") }

        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid == app.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let id = window[kCGWindowNumber as String] as? UInt32
            else { continue }
            return (CGWindowID(id), window[kCGWindowName as String] as? String ?? "")
        }
        return (nil, "")
    }
}
