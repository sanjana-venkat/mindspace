import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

enum NotedPermission: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen & System Audio"
        }
    }

    var explanation: String {
        switch self {
        case .microphone: "Records your voice as “You” in audio and meeting notes."
        case .accessibility: "Reads only the text you select when you press ⌘⇧T."
        case .screenRecording: "Captures windows, regions, and meeting audio playing on your Mac."
        }
    }

    var icon: String {
        switch self {
        case .microphone: "mic.fill"
        case .accessibility: "text.cursor"
        case .screenRecording: "rectangle.on.rectangle"
        }
    }

    var settingsPane: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
    }
}

struct NotedPermissionSnapshot: Equatable {
    var microphone: Bool
    var accessibility: Bool
    var screenRecording: Bool

    var allGranted: Bool { microphone && accessibility && screenRecording }

    func isGranted(_ permission: NotedPermission) -> Bool {
        switch permission {
        case .microphone: microphone
        case .accessibility: accessibility
        case .screenRecording: screenRecording
        }
    }
}

@MainActor
final class PermissionCenter: ObservableObject {
    static let completionKey = "noted.permissions.onboarding.completed.v1"

    @Published private(set) var snapshot: NotedPermissionSnapshot
    @Published private(set) var requestedPermission: NotedPermission?

    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    init() {
        snapshot = Self.readSnapshot()
    }

    deinit {
        pollTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    func startPolling() {
        refresh()
        guard pollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() {
        snapshot = Self.readSnapshot()
        if let requestedPermission, snapshot.isGranted(requestedPermission) {
            self.requestedPermission = nil
        }
    }

    func request(_ permission: NotedPermission) {
        requestedPermission = permission
        switch permission {
        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
            } else if status != .authorized {
                openSettings(for: permission)
            }
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
            refresh()
        }
    }

    func openSettings(for permission: NotedPermission) {
        requestedPermission = permission
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func markComplete() {
        UserDefaults.standard.set(true, forKey: Self.completionKey)
    }

    func relaunch() {
        let appURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSWorkspace.shared.open(appURL)
        }
    }

    private static func readSnapshot() -> NotedPermissionSnapshot {
        NotedPermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }
}

struct PermissionOnboardingView: View {
    @ObservedObject var permissionCenter: PermissionCenter
    let onFinished: () -> Void

    private var currentPermission: NotedPermission? {
        NotedPermission.allCases.first { !permissionCenter.snapshot.isGranted($0) }
    }

    var body: some View {
        ZStack {
            NotefyTheme.sand.ignoresSafeArea()
            InkSplatterMark(seed: 21, opacity: 0.06)
                .frame(width: 620, height: 520).blur(radius: 50)
                .offset(x: 390, y: -270)
            InkSplatterMark(seed: 34, opacity: 0.05)
                .frame(width: 480, height: 400).blur(radius: 60)
                .offset(x: -390, y: 300)

            VStack(spacing: 24) {
                ZStack {
                    InkSplatterMark(seed: 5, tint: NotefyTheme.pigment, opacity: 0.20)
                        .frame(width: 118, height: 96)
                    NotedMark(tint: NotefyTheme.ink, knockout: NotefyTheme.sand)
                        .frame(width: 48, height: 48)
                }
                .frame(width: 126, height: 92)

                VStack(spacing: 6) {
                    Text("LET KAMI WORK ACROSS YOUR MAC")
                        .font(NotefyFont.label).tracking(1.5).foregroundStyle(NotefyTheme.inkSoft)
                    Text(currentPermission == nil ? "You’re ready" : "A few permissions first")
                        .font(NotefyFont.pageTitle).foregroundStyle(NotefyTheme.ink)
                    Text("Noted checks macOS directly and keeps this page updated while you grant access.")
                        .font(NotefyFont.body).foregroundStyle(NotefyTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    ForEach(NotedPermission.allCases) { permission in
                        permissionStatus(permission)
                    }
                }

                if let permission = currentPermission {
                    permissionCard(permission)
                } else {
                    readyCard
                }
            }
            .padding(36)
            .frame(maxWidth: 760)
        }
        .preferredColorScheme(.light)
        .onAppear { permissionCenter.startPolling() }
        .onDisappear { permissionCenter.stopPolling() }
    }

    private func permissionStatus(_ permission: NotedPermission) -> some View {
        let granted = permissionCenter.snapshot.isGranted(permission)
        return HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : permission.icon)
            Text(permission.title.uppercased()).font(NotefyFont.caption).tracking(0.6)
        }
        .foregroundStyle(granted ? NotefyTheme.ink : NotefyTheme.inkSoft)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(granted ? NotefyTheme.pebbleOlive.opacity(0.7) : NotefyTheme.cardPaper, in: Capsule())
        .overlay(Capsule().stroke(NotefyTheme.ink.opacity(0.1), lineWidth: 1))
    }

    private func permissionCard(_ permission: NotedPermission) -> some View {
        VStack(spacing: 17) {
            Image(systemName: permission.icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(NotefyTheme.ink)
            VStack(spacing: 5) {
                Text(permission.title).font(NotefyFont.sectionTitle)
                Text(permission.explanation)
                    .font(NotefyFont.body).foregroundStyle(NotefyTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button {
                    permissionCenter.request(permission)
                } label: {
                    Label(primaryTitle(for: permission), systemImage: "checkmark.shield")
                        .font(NotefyFont.label).tracking(0.8)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(NotefyTheme.ink, in: Capsule())
                        .foregroundStyle(NotefyTheme.sand)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grant \(permission.title)")

                Button("OPEN SYSTEM SETTINGS") {
                    permissionCenter.openSettings(for: permission)
                }
                .buttonStyle(.plain).font(NotefyFont.label).tracking(0.7)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .overlay(Capsule().stroke(NotefyTheme.ink.opacity(0.65), lineWidth: 1.2))
                .accessibilityLabel("Open System Settings for \(permission.title)")
            }
            HStack(spacing: 14) {
                Button("RECHECK") { permissionCenter.refresh() }
                    .buttonStyle(.plain).font(NotefyFont.caption)
                    .accessibilityLabel("Recheck permissions")
                Button("RELAUNCH NOTED") { permissionCenter.relaunch() }
                    .buttonStyle(.plain).font(NotefyFont.caption)
                    .accessibilityLabel("Relaunch Noted")
            }
            .foregroundStyle(NotefyTheme.inkSoft)
            Text(permission == .accessibility
                 ? "If Noted is already enabled, turn it off and on once, then relaunch Noted. macOS sometimes keeps the old signed build cached."
                 : "Return here after changing System Settings. This status refreshes automatically.")
                .font(NotefyFont.caption).foregroundStyle(NotefyTheme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 590)
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NotefyTheme.ink.opacity(0.12), lineWidth: 1))
    }

    private var readyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(NotefyTheme.pebbleOlive)
            Text("Microphone, selected text, screen capture, and meeting audio are ready.")
                .font(NotefyFont.body).foregroundStyle(NotefyTheme.inkSoft)
            Button("START USING NOTED") {
                permissionCenter.markComplete()
                onFinished()
            }
            .buttonStyle(.plain).font(NotefyFont.label).tracking(1)
            .padding(.horizontal, 20).padding(.vertical, 11)
            .background(NotefyTheme.ink, in: Capsule()).foregroundStyle(NotefyTheme.sand)
            .accessibilityLabel("Start using Noted")
        }
        .padding(26)
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NotefyTheme.ink.opacity(0.12), lineWidth: 1))
    }

    private func primaryTitle(for permission: NotedPermission) -> String {
        permissionCenter.requestedPermission == permission ? "ASK MACOS AGAIN" : "GRANT \(permission.title.uppercased())"
    }
}
