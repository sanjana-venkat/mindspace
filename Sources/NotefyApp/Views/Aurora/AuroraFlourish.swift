import SwiftUI
import AppKit

/// The app's signature, played at the moment something is caught.
///
/// Aurora ribbons bloom along the top and bottom of the screen, drift, and go
/// out — about a second in all. It never covers what you were looking at and
/// never takes a click; it is the app saying *I have it* in its own language,
/// whether what it caught was a screenshot, a sentence you lifted, a voice
/// note or a meeting.
struct AuroraCaptureFlourish: View {
    enum Kind {
        /// Something was caught and kept.
        case captured
        /// A recording started — the light settles in and stays a beat longer.
        case listening
        /// A recording ended.
        case finished

        var palette: [Color] {
            switch self {
            case .captured:
                return [Color(red: 0.36, green: 0.96, blue: 0.71),
                        Color(red: 0.32, green: 0.78, blue: 0.93),
                        Color(red: 0.62, green: 0.53, blue: 0.98)]
            case .listening:
                return [Color(red: 0.42, green: 0.86, blue: 0.98),
                        Color(red: 0.53, green: 0.62, blue: 0.99),
                        Color(red: 0.78, green: 0.52, blue: 0.96)]
            case .finished:
                return [Color(red: 0.98, green: 0.84, blue: 0.52),
                        Color(red: 0.48, green: 0.94, blue: 0.74),
                        Color(red: 0.38, green: 0.72, blue: 0.95)]
            }
        }

        var duration: Double {
            switch self {
            case .captured: return 1.15
            case .listening: return 1.5
            case .finished: return 1.25
            }
        }
    }

    let kind: Kind
    /// When the flourish began, so the envelope is wall-clock rather than
    /// dependent on when the view happened to be created.
    let start: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let progress = max(0, min(1, elapsed / kind.duration))
            // In fast, out slow: a light coming on and dying away.
            let envelope = progress < 0.22
                ? pow(progress / 0.22, 0.7)
                : pow(1 - (progress - 0.22) / 0.78, 1.6)

            Canvas { context, size in
                context.addFilter(.blur(radius: 34))
                draw(in: &context, size: size, time: elapsed, envelope: envelope)
            }
            .blendMode(.plusLighter)
            .opacity(envelope)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// Three ribbons at the top, two at the foot — the sky is the louder half.
    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double, envelope: Double) {
        let colors = kind.palette
        for index in 0..<5 {
            let fromTop = index < 3
            let rank = fromTop ? index : index - 3
            let colour = colors[index % colors.count]

            let reach = size.height * (fromTop ? 0.30 : 0.22)
            let base = fromTop
                ? reach * (0.32 + Double(rank) * 0.24)
                : size.height - reach * (0.34 + Double(rank) * 0.3)
            let thickness = reach * (0.42 - Double(rank) * 0.07) * (0.7 + envelope * 0.5)
            let amplitude = size.height * 0.035 * (1 + Double(rank) * 0.4)
            let drift = time * (18 + Double(rank) * 9) * (fromTop ? 1 : -1)

            let band = ribbon(width: size.width,
                              centre: base,
                              amplitude: amplitude,
                              thickness: thickness,
                              phase: drift / 90 + Double(index))

            context.fill(band, with: .linearGradient(
                Gradient(stops: [
                    .init(color: colour.opacity(0), location: 0),
                    .init(color: colour.opacity(0.85), location: 0.3),
                    .init(color: colour.opacity(0.55), location: 0.68),
                    .init(color: colour.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: -size.width * 0.1, y: 0),
                endPoint: CGPoint(x: size.width * 1.1, y: 0)))
        }
    }

    /// A band whose top and bottom edges are the same wave, offset — so it
    /// keeps an even weight along its length instead of pinching.
    private func ribbon(width: CGFloat, centre: CGFloat, amplitude: CGFloat,
                        thickness: CGFloat, phase: Double) -> Path {
        var path = Path()
        let steps = 48
        func wave(_ x: CGFloat) -> CGFloat {
            let t = Double(x / max(width, 1))
            return centre
                + amplitude * CGFloat(sin(t * 3.1 + phase))
                + amplitude * 0.4 * CGFloat(sin(t * 7.3 - phase * 1.3))
        }
        for step in 0...steps {
            let x = width * CGFloat(step) / CGFloat(steps)
            let y = wave(x) - thickness / 2
            step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let x = width * CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: x, y: wave(x) + thickness / 2))
        }
        path.closeSubpath()
        return path
    }
}

/// Puts the flourish on screen: a borderless, click-through panel over
/// everything, which closes itself when the light has gone out.
@MainActor
final class AuroraFlourishController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func play(_ kind: AuroraCaptureFlourish.Kind) {
        guard !UserDefaults.standard.bool(forKey: "aurora.flourish.off") else { return }
        // Reduce Motion means no decorative animation, full stop.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        dismissal?.cancel()
        panel?.close()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.frame else { return }

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(
            rootView: AuroraCaptureFlourish(kind: kind, start: Date()))
        panel.orderFrontRegardless()
        self.panel = panel

        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(kind.duration * 1000) + 120))
            guard !Task.isCancelled else { return }
            panel.close()
            if self?.panel === panel { self?.panel = nil }
        }
    }
}
