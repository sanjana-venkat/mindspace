import SwiftUI

/// What the moon is feeling, while it listens.
///
/// The orbit moon used to be a single picture with its face painted on, so it
/// looked the same whether it was idle or hanging on your every word. The face
/// is now drawn over a faceless copy of the same art, which means it can pay
/// attention while you talk and look up, surprised, when you stop.
@MainActor
final class MoonMood: ObservableObject {
    enum Face: Equatable { case idle, attentive, surprised }

    @Published private(set) var face: Face = .idle
    @Published private(set) var blinking = false

    private var listenTimer: Timer?
    private var blinkTimer: Timer?
    private var lastVoice: Date?
    private var spoke = false
    private var lastWords = 0

    /// Speech sits around -20 to -35 dB; a quiet room around -50 and below.
    private static let voiceFloor: Float = -40
    /// How long a pause has to be before it reads as "you've finished".
    private static let pauseForSurprise: TimeInterval = 1.1

    func listen(level: @escaping () -> Float, words: @escaping () -> Int) {
        spoke = false
        lastVoice = nil
        lastWords = words()
        face = .attentive
        listenTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample(level: level(), words: words()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        listenTimer = timer
    }

    func rest() {
        listenTimer?.invalidate()
        listenTimer = nil
        face = .idle
    }

    /// Blinks every few seconds, at slightly uneven intervals so it never
    /// reads as a metronome. Never while surprised: a surprised face does not
    /// blink.
    func startBlinking() {
        guard blinkTimer == nil else { return }
        scheduleBlink()
    }

    func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    private func scheduleBlink() {
        let timer = Timer(timeInterval: Double.random(in: 2.8...5.2), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.face != .surprised {
                    self.blinking = true
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    self.blinking = false
                }
                self.scheduleBlink()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func sample(level: Float, words: Int) {
        let now = Date()
        // Either the level or new words count as you speaking. The level is
        // quicker; the words are the fallback when no level is reported.
        if level > Self.voiceFloor || words != lastWords {
            lastVoice = now
            spoke = true
            lastWords = words
        }
        let next: Face
        if spoke, let lastVoice, now.timeIntervalSince(lastVoice) > Self.pauseForSurprise {
            next = .surprised
        } else {
            next = .attentive
        }
        if next != face { face = next }
    }
}

/// The moon's features, drawn in the art's own pixel space so they land where
/// the painted face was. Positions and colours were measured from
/// `moon-idle.png`: eyes at (135.7, 157.7) and (223.0, 157.8), radius 11.5,
/// rgb(54, 54, 65); a smile 36 wide centred on (179.8, 186.3).
struct MoonFace: View {
    let face: MoonMood.Face
    var blinking: Bool = false

    private static let art = CGSize(width: 369, height: 383)
    private static let ink = Color(red: 54 / 255, green: 54 / 255, blue: 65 / 255)
    private static let leftEye = CGPoint(x: 135.7, y: 157.7)
    private static let rightEye = CGPoint(x: 223.0, y: 157.8)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / Self.art.width, size.height / Self.art.height)
            let ox = (size.width - Self.art.width * s) / 2
            let oy = (size.height - Self.art.height * s) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            let ink = GraphicsContext.Shading.color(Self.ink)

            // eyes
            let r: CGFloat = face == .surprised ? 13.5 : (face == .attentive ? 10.5 : 11.5)
            let squash: CGFloat = blinking ? 0.12 : 1
            for eye in [Self.leftEye, Self.rightEye] {
                let c = p(eye.x, eye.y)
                let rect = CGRect(x: c.x - r * s, y: c.y - r * s * squash,
                                  width: r * 2 * s, height: r * 2 * s * squash)
                ctx.fill(Path(ellipseIn: rect), with: ink)
                // A catchlight once it is paying attention. The idle face in
                // the original art has none, so idle stays without.
                if face != .idle && !blinking {
                    let hr: CGFloat = face == .surprised ? 4.2 : 3.2
                    let h = CGPoint(x: c.x + r * 0.32 * s, y: c.y - r * 0.34 * s)
                    ctx.fill(Path(ellipseIn: CGRect(x: h.x - hr * s, y: h.y - hr * s,
                                                    width: hr * 2 * s, height: hr * 2 * s)),
                             with: .color(.white.opacity(0.92)))
                }
            }

            // brows, only when it is concentrating or caught off guard
            if face != .idle {
                let lift: CGFloat = face == .surprised ? 34 : 26
                let bend: CGFloat = face == .surprised ? 4 : 0
                for (eye, dir) in [(Self.leftEye, -1.0), (Self.rightEye, 1.0)] {
                    var brow = Path()
                    let inner = p(eye.x - CGFloat(dir) * 11, eye.y - lift + (face == .attentive ? 1.5 : 0))
                    let outer = p(eye.x + CGFloat(dir) * 13, eye.y - lift)
                    let mid = p(eye.x + CGFloat(dir) * 1, eye.y - lift - bend)
                    brow.move(to: inner)
                    brow.addQuadCurve(to: outer, control: mid)
                    ctx.stroke(brow, with: ink, style: StrokeStyle(lineWidth: 4.2 * s, lineCap: .round))
                }
            }

            // mouth
            switch face {
            case .idle:
                var smile = Path()
                smile.move(to: p(162.5, 182.0))
                smile.addQuadCurve(to: p(197.0, 182.0), control: p(179.8, 197.5))
                ctx.stroke(smile, with: ink, style: StrokeStyle(lineWidth: 5.6 * s, lineCap: .round))
            case .attentive:
                var line = Path()
                line.move(to: p(172.5, 189.0))
                line.addLine(to: to(p(187.5, 189.0)))
                ctx.stroke(line, with: ink, style: StrokeStyle(lineWidth: 5.2 * s, lineCap: .round))
            case .surprised:
                ctx.fill(Path(ellipseIn: CGRect(x: ox + 173.5 * s, y: oy + 183 * s,
                                                width: 13 * s, height: 16 * s)), with: ink)
            }
        }
        .allowsHitTesting(false)
    }

    private func to(_ point: CGPoint) -> CGPoint { point }
}
