import AppKit
import SwiftUI

@MainActor
final class CapturePetController {
    private var panel: NSPanel?
    private let captureText: () -> Void
    private let capturePage: () -> Void
    private let captureRegion: () -> Void
    private let toggleAudio: () -> Void
    private let toggleMeeting: () -> Void

    init(
        captureText: @escaping () -> Void,
        capturePage: @escaping () -> Void,
        captureRegion: @escaping () -> Void,
        toggleAudio: @escaping () -> Void,
        toggleMeeting: @escaping () -> Void
    ) {
        self.captureText = captureText
        self.capturePage = capturePage
        self.captureRegion = captureRegion
        self.toggleAudio = toggleAudio
        self.toggleMeeting = toggleMeeting
    }

    func show() {
        if let panel, panel.isVisible {
            return
        }

        let size = NSSize(width: 250, height: 292)
        let panel = self.panel ?? makePanel(size: size)
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.orderFrontRegardless()
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func hide() {
        panel?.animator().alphaValue = 0
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        }
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        let hostingView = TransparentHostingView(rootView: CaptureRailView(
            onDismiss: { [weak self] in self?.hide() },
            captureText: captureText,
            capturePage: capturePage,
            captureRegion: captureRegion,
            toggleAudio: toggleAudio,
            toggleMeeting: toggleMeeting
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSPoint(x: frame.maxX - size.width, y: frame.midY - size.height / 2)
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

private struct CaptureRailView: View {
    enum HoveredAction: Equatable { case capture, text, audio, meeting }

    @State private var hovered: HoveredAction?
    @State private var iconHovered: HoveredAction?
    @State private var labelHovered = false
    let onDismiss: () -> Void
    let captureText: () -> Void
    let capturePage: () -> Void
    let captureRegion: () -> Void
    let toggleAudio: () -> Void
    let toggleMeeting: () -> Void

    var body: some View {
        HStack(spacing: -4) {
            accessoryColumn
                .frame(width: 158, alignment: .trailing)
                .zIndex(2)

            VStack(spacing: 8) {
                Button {
                    onDismiss()
                } label: {
                    // No logo here. The mark was doing double duty as the
                    // dismiss control, which made the one piece of branding
                    // on screen also the button that makes it go away.
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(NotefyTheme.ink.opacity(0.45))
                        .frame(width: 46, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide Kami's capture rail")

                // Clicking has to do what hovering does: the capture options
                // were hover-only, so a click on the rail's main button did
                // nothing at all — and hover isn't available to everyone.
                railButton(.capture, icon: .capture, help: "Capture") {
                    withAnimation(.easeOut(duration: 0.14)) {
                        hovered = (hovered == .capture) ? nil : .capture
                    }
                }
                railButton(.text, icon: .text, help: "Selected text — ⌘⇧T") { perform(captureText) }
                railButton(.audio, icon: .audio, help: "Computer audio — ⌘⇧A") { perform(toggleAudio) }
                railButton(.meeting, icon: .meeting, help: "Meeting notes — ⌘⇧M") { perform(toggleMeeting) }
            }
            .padding(.horizontal, 6)
            .padding(.top, 7)
            .padding(.bottom, 8)
            .background {
                // The rail is a pane of glass laid on the desktop, not a
                // white pill sitting on it. `.behindWindow` frosts whatever
                // is actually behind the panel; the grain is the same etch
                // the main window uses, so the two read as one material.
                ZStack {
                    RailGlass()
                    FrostGrain()
                }
                .clipShape(Capsule())
            }
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
        }
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.16), value: hovered)
    }

    @ViewBuilder
    private var accessoryColumn: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 38)
            accessorySlot(.capture)
            accessorySlot(.text)
            accessorySlot(.audio)
            accessorySlot(.meeting)
        }
        .padding(.top, 5)
        .padding(.bottom, 8)
    }

    private func accessorySlot(_ action: HoveredAction) -> some View {
        Color.clear
            .frame(height: 44)
            .overlay(alignment: .trailing) {
                if hovered == action {
                    accessory(for: action)
                        .onHover { inside in
                            labelHovered = inside
                            if inside {
                                hovered = action
                            } else {
                                dismissAfterDelay(action)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .trailing)))
                }
            }
    }

    @ViewBuilder
    private func accessory(for action: HoveredAction) -> some View {
        if action == .capture {
            VStack(alignment: .trailing, spacing: 6) {
                satellite("FULL WINDOW", icon: .window) { perform(capturePage) }
                satellite("PARTIAL", icon: .region) {
                    onDismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        captureRegion()
                    }
                }
            }
        } else {
            Text(label(for: action))
                .font(NotefyFont.label)
                .tracking(1.1)
                .foregroundStyle(NotefyTheme.sand)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(NotefyTheme.ink, in: Capsule())
        }
    }

    private func railButton(
        _ action: HoveredAction,
        icon: OverlayIcon.Kind,
        help: String,
        perform actionBlock: @escaping () -> Void
    ) -> some View {
        Button(action: actionBlock) {
            ZStack {
                if hovered == action {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.42))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1))
                        .padding(3)
                }
                OverlayIcon(kind: icon).frame(width: 23, height: 23)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(RailPressStyle())
        .onHover { inside in
            if inside {
                iconHovered = action
                withAnimation(.easeOut(duration: 0.14)) { hovered = action }
            } else {
                if iconHovered == action { iconHovered = nil }
                dismissAfterDelay(action)
            }
        }
        .help(help)
    }

    private func dismissAfterDelay(_ action: HoveredAction) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            if hovered == action && iconHovered != action && !labelHovered {
                withAnimation(.easeOut(duration: 0.14)) { hovered = nil }
            }
        }
    }

    private func satellite(_ title: String, icon: OverlayIcon.Kind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                OverlayIcon(kind: icon, tint: NotefyTheme.sand).frame(width: 18, height: 18)
                Text(title).font(NotefyFont.label).tracking(1)
            }
            .foregroundStyle(NotefyTheme.sand)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(NotefyTheme.ink, in: Capsule())
        }
        .buttonStyle(RailPressStyle())
    }

    private func perform(_ action: () -> Void) {
        action()
    }

    private func label(for action: HoveredAction) -> String {
        switch action {
        case .capture: "CAPTURE"
        case .text: "TEXT"
        case .audio: "COMPUTER AUDIO"
        case .meeting: "MEETING"
        }
    }

}

private struct RailPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct OverlayIcon: View {
    enum Kind { case capture, text, audio, meeting, microphone, window, region }
    let kind: Kind
    var tint: Color = NotefyTheme.ink

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24
            let sy = size.height / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            func stroke(_ path: Path, dashed: Bool = false) {
                context.stroke(
                    path,
                    with: .color(tint),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: dashed ? [3, 3] : [])
                )
            }
            var path = Path()
            switch kind {
            case .capture:
                path.move(to: p(4,8)); path.addLine(to: p(4,6)); path.addQuadCurve(to: p(6,4), control: p(4,4)); path.addLine(to: p(8,4))
                path.move(to: p(16,4)); path.addLine(to: p(18,4)); path.addQuadCurve(to: p(20,6), control: p(20,4)); path.addLine(to: p(20,8))
                path.move(to: p(20,16)); path.addLine(to: p(20,18)); path.addQuadCurve(to: p(18,20), control: p(20,20)); path.addLine(to: p(16,20))
                path.move(to: p(8,20)); path.addLine(to: p(6,20)); path.addQuadCurve(to: p(4,18), control: p(4,20)); path.addLine(to: p(4,16)); stroke(path)
                stroke(Path(ellipseIn: CGRect(x: 8.8*sx, y: 8.8*sy, width: 6.4*sx, height: 6.4*sy)))
            case .text:
                path.move(to: p(5,7)); path.addCurve(to: p(6.5,10.5), control1: p(5,4.5), control2: p(10,3.5)); path.addCurve(to: p(10,7), control1: p(8,10), control2: p(10,9))
                path.move(to: p(13,7)); path.addCurve(to: p(14.5,10.5), control1: p(13,4.5), control2: p(18,3.5)); path.addCurve(to: p(18,7), control1: p(16,10), control2: p(18,9))
                path.move(to: p(5,15)); path.addLine(to: p(19,15)); path.move(to: p(5,19)); path.addLine(to: p(14,19)); stroke(path)
            case .audio:
                for (x, y1, y2) in [(4,10,14),(8,7,17),(12,4,20),(16,8,16),(20,10,14)] {
                    path.move(to: p(CGFloat(x),CGFloat(y1))); path.addLine(to: p(CGFloat(x),CGFloat(y2)))
                }; stroke(path)
            case .meeting:
                stroke(Path(ellipseIn: CGRect(x: 6*sx, y: 6*sy, width: 6*sx, height: 6*sy)))
                stroke(Path(ellipseIn: CGRect(x: 14.3*sx, y: 7.8*sy, width: 4.4*sx, height: 4.4*sy)))
                path.move(to: p(3.5,19)); path.addCurve(to: p(14.5,19), control1: p(4.5,13), control2: p(13.5,13)); path.move(to: p(16,15.6)); path.addCurve(to: p(20,19), control1: p(18,16), control2: p(19.4,17)); stroke(path)
            case .microphone:
                path.addRoundedRect(in: CGRect(x: 9*sx, y: 3.5*sy, width: 6*sx, height: 11*sy), cornerSize: CGSize(width: 3*sx, height: 3*sy)); path.move(to: p(5.5,11.5)); path.addCurve(to: p(18.5,11.5), control1: p(5.5,20), control2: p(18.5,20)); path.move(to: p(12,18)); path.addLine(to: p(12,20.5)); stroke(path)
            case .window:
                path.addRoundedRect(in: CGRect(x: 3.5*sx, y: 5*sy, width: 17*sx, height: 14*sy), cornerSize: CGSize(width: 2*sx, height: 2*sy)); path.move(to: p(3.5,9)); path.addLine(to: p(20.5,9)); stroke(path)
            case .region:
                path.addRoundedRect(in: CGRect(x: 5*sx, y: 5*sy, width: 14*sx, height: 14*sy), cornerSize: CGSize(width: 1.5*sx, height: 1.5*sy)); stroke(path, dashed: true)
            }
        }
        .foregroundStyle(NotefyTheme.ink)
    }
}


/// Frosted backing for the floating rail.
///
/// `.behindWindow` blending is what makes it real glass: the material samples
/// the desktop behind the panel rather than the panel's own contents. The
/// panel is already non-opaque with a clear background, which is the
/// precondition — without that the effect view has nothing to sample.
///
/// The shape comes from `maskImage` rather than a SwiftUI clip, because a
/// clip applied over an NSViewRepresentable does not reliably reach the
/// effect view's own layer.
private struct RailGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        // Pinned light, like the main window: the rail's glyphs are ink, and
        // a dark material under them would leave them unreadable on a dark
        // desktop.
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        let radius = max(1, min(view.bounds.width, view.bounds.height) / 2)
        view.maskImage = Self.capsuleMask(radius: radius)
    }

    private static func capsuleMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
