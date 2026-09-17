import AppKit
import CoreAudio
import NotefyCore
import UserNotifications

/// Offers meeting notes when a supported call is detected. It never records
/// until the user explicitly clicks the notification.
final class MeetingDetectionController: NSObject, UNUserNotificationCenterDelegate {
    var shouldSuggest: () -> Bool = { true }
    var onAccept: () -> Void = {}
    /// Asked to make the offer, with a line describing what was spotted. The
    /// app shows its own card rather than a system notification, so this is
    /// what actually reaches the screen.
    var onSuggest: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var activationObserver: NSObjectProtocol?
    private var timer: Timer?
    private var lastPromptKey: String?
    private var lastPromptDate = Date.distantPast
    private var checking = false

    func start() {
        guard timer == nil else { return }
        center.delegate = self
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.checkCurrentApp() }
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.checkCurrentApp()
        }
        checkCurrentApp()
    }

    deinit {
        timer?.invalidate()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func checkCurrentApp() {
        guard !checking, shouldSuggest(), let meeting = currentMeeting() else { return }
        guard lastPromptKey != meeting.key || Date().timeIntervalSince(lastPromptDate) >= 2 * 60 * 60 else { return }
        checking = true
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.deliver(meeting)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { self.deliver(meeting) }
                    else { DispatchQueue.main.async { self.checking = false } }
                }
            default:
                DispatchQueue.main.async { self.checking = false }
            }
        }
    }

    private func deliver(_ meeting: MeetingContext) {
        // The app's own card, when there is someone to show it to.
        if let onSuggest {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onSuggest(meeting.detail)
                self.lastPromptKey = meeting.key
                self.lastPromptDate = .now
                self.checking = false
            }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Mindspace"
        content.body = "I’ll do your meeting notes. Click to start recording and transcribing your voice and the other voices."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "mindspace.meeting.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil {
                    self.lastPromptKey = meeting.key
                    self.lastPromptDate = .now
                }
                self.checking = false
            }
        }
    }

    private func currentMeeting() -> MeetingContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = app.localizedName ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        if (name.localizedCaseInsensitiveContains("zoom")
            || bundleID.localizedCaseInsensitiveContains("zoom")), zoomHasActiveMeeting(pid: app.processIdentifier) {
            return MeetingContext(key: "zoom", detail: "You're in a Zoom call.")
        }
        if name == "Google Chrome", let tab = chromeTab(), MeetingDetectionRules.isGoogleMeet(url: tab.url, title: tab.title) {
            return MeetingContext(key: "google-meet:\(tab.url ?? tab.title ?? "active")",
                                  detail: "You're in a Google Meet.")
        }
        if name == "Safari", let tab = safariTab(), MeetingDetectionRules.isGoogleMeet(url: tab.url, title: tab.title) {
            return MeetingContext(key: "google-meet:\(tab.url ?? tab.title ?? "active")",
                                  detail: "You're in a Google Meet.")
        }
        // Anything else that has taken the microphone — Teams, Slack huddles,
        // FaceTime, a call in a browser this app can't read. The mic being
        // live is the honest signal that a conversation is happening.
        if Self.microphoneIsInUse() {
            let who = name.isEmpty ? "Something" : name
            return MeetingContext(key: "microphone:\(bundleID.isEmpty ? who : bundleID)",
                                  detail: "\(who) is using your microphone.")
        }
        return nil
    }

    /// True when any input device is running for some process on this Mac.
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` is the same flag that
    /// lights the orange dot in the menu bar.
    static func microphoneIsInUse() -> Bool {
        var listSize: UInt32 = 0
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &listSize) == noErr else { return false }

        let count = Int(listSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &listSize, &devices) == noErr else { return false }

        for device in devices where hasInput(device) {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    /// Output-only devices report as running whenever anything plays, so the
    /// check is limited to devices that actually have input channels.
    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private func zoomHasActiveMeeting(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else { return false }
            let title = (window[kCGWindowName as String] as? String) ?? ""
            return MeetingDetectionRules.isZoomMeetingWindow(title)
        }
    }

    private func chromeTab() -> (url: String?, title: String?)? {
        runTabScript("""
        tell application "Google Chrome"
            if (count of windows) > 0 then
                tell active tab of front window to return {URL, title}
            end if
        end tell
        """)
    }

    private func safariTab() -> (url: String?, title: String?)? {
        runTabScript("""
        tell application "Safari"
            if (count of windows) > 0 then
                tell current tab of front window to return {URL, name}
            end if
        end tell
        """)
    }

    private func runTabScript(_ source: String) -> (url: String?, title: String?)? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems == 2 else { return nil }
        return (result.atIndex(1)?.stringValue, result.atIndex(2)?.stringValue)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier.hasPrefix("mindspace.meeting.") else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [onAccept] in onAccept() }
        completionHandler()
    }
}

private struct MeetingContext {
    let key: String
    /// What to say we noticed.
    let detail: String
}
