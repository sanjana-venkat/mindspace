import SwiftUI
import AppKit
import CoreText

private enum BundledFontRegistrar {
    static let register: Void = {
        guard let fontsURL = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let fontURLs = try? FileManager.default.contentsOfDirectory(
                at: fontsURL,
                includingPropertiesForKeys: nil
              ) else { return }
        for url in fontURLs where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

/// One window per launch. The menu-bar label's task is what opens it — a
/// `WindowGroup` living beside a `MenuBarExtra` does not reliably present one
/// by itself, and a release build presents none at all — but that task fires
/// every time the label is rebuilt, and every one of those was opening another
/// window. Hence the latch.
private enum MainWindowLatch {
    static var opened = false
}

private struct NotefyMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let isRecording: Bool

    var body: some View {
        Image(systemName: isRecording ? "waveform.circle.fill" : "square.and.pencil")
            .task {
                guard !MainWindowLatch.opened else { return }
                MainWindowLatch.opened = true
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

final class NotefyAppDelegate: NSObject, NSApplicationDelegate {
    /// Re-opening the app — from the Dock, from `open`, from anywhere — should
    /// bring the window it already has forward, not make another one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let existing = Self.mainWindows.first {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }

    /// Windows belonging to the main scene, newest last.
    static var mainWindows: [NSWindow] {
        NSApp.windows.filter { $0.title == "Mindspace" && $0.isVisible }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Notefy has a menu-bar control, but it is also a regular windowed app.
        // Starting as an accessory can leave the dashboard alive but impossible
        // to bring forward when the app is launched from Finder or `open`.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            Self.closeDuplicateWindows()
            Self.mainWindows.first?.makeKeyAndOrderFront(nil)
            Self.nudgeMainWindowLayout()
        }
    }

    /// macOS restores every window a scene had when it was last quit, so a
    /// session that ended with several leaves you opening several. One is the
    /// app; the rest are debris.
    private static func closeDuplicateWindows() {
        let windows = mainWindows
        guard windows.count > 1 else { return }
        for window in windows.dropFirst() { window.close() }
    }

    /// SwiftUI's very first layout pass for the main window sometimes runs before the
    /// window has settled to its real `.defaultSize` frame, which leaves GeometryReader-based
    /// layouts (the sidebar's height) computed against a stale size. A real AppKit resize
    /// event forces a clean relayout against the window's actual bounds, so nudge the size
    /// by a point and back right after launch.
    private static func nudgeMainWindowLayout() {
        guard let window = NSApp.windows.first(where: { $0.title == "Mindspace" }) else { return }
        let original = window.frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            var nudged = original
            nudged.size.height += 1
            window.setFrame(nudged, display: true)
            DispatchQueue.main.async {
                window.setFrame(original, display: true)
            }
        }
    }
}

@main
struct NotefyMenuBarApp: App {
    @NSApplicationDelegateAdaptor(NotefyAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        _ = BundledFontRegistrar.register
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.installHotkeys()
                    appState.showCapturePet()
                }
        } label: {
            NotefyMenuBarLabel(isRecording: appState.isRecording)
        }
        .menuBarExtraStyle(.window)

        // A `Window` scene only appears at launch if macOS restores it, so a
        // fresh install — or any launch after the window was closed — left the
        // app running as a menu-bar icon with nothing on screen. A WindowGroup
        // always presents one.
        WindowGroup("Mindspace", id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    appState.installHotkeys()
                    appState.showCapturePet()
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        // The native title bar was a hard white bar across the top of an
        // otherwise all-clay window — hide it so the bed's own colour reads
        // all the way to the traffic lights, the way a real object would.
        .windowStyle(.hiddenTitleBar)
    }
}
