import SwiftUI

/// The reading panel's backdrop: a night sky with an aurora hanging in it.
/// Ribbons are drawn in a Canvas and composited additively, which is what makes
/// the light look like light — a blurred fill on a pale ground never will.
struct AuroraNight: View {
    var seed: Int
    /// On a pale ground the same light has to be painted rather than added —
    /// `plusLighter` over near-white shows nothing at all.
    var onLight: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let night = Color(red: 0.035, green: 0.075, blue: 0.094)
    private let nightLow = Color(red: 0.055, green: 0.125, blue: 0.137)
    private let green = Color(red: 0.26, green: 0.72, blue: 0.50)
    private let teal = Color(red: 0.27, green: 0.60, blue: 0.68)
    private let violet = Color(red: 0.47, green: 0.40, blue: 0.74)
    private let rose = Color(red: 0.72, green: 0.44, blue: 0.58)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.055

            ZStack {
                if !onLight {
                    LinearGradient(colors: [night, nightLow, night],
                                   startPoint: .top, endPoint: .bottom)
                }

                Canvas { context, size in
                    for i in 0..<5 {
                        context.fill(ribbon(i, t: t, size: size), with: shading(i, size: size))
                    }
                }
                .blur(radius: onLight ? 44 : 34)
                .blendMode(onLight ? .normal : .plusLighter)
                .opacity(onLight ? 0.5 : 0.62)

                // the glow the curtains stand in, low and green
                if !onLight {
                    LinearGradient(colors: [.clear, green.opacity(0.07), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .blendMode(.plusLighter)

                    // Keeps the type legible: the light sits behind a slight
                    // veil, heaviest at the top where the title and thought sit.
                    LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.12), .black.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom)
                }

                AuroraGrain.tile
                    .resizable(resizingMode: .tile)
                    .blendMode(onLight ? .multiply : .overlay)
                    .opacity(onLight ? 0.22 : 0.35)
            }
            .drawingGroup()
        }
    }

    /// One hanging curtain: the centre line wanders, the width breathes, and
    /// the whole thing drifts sideways over time.
    private func ribbon(_ i: Int, t: Double, size: CGSize) -> Path {
        let phase = Double(i) * 1.6 + Double(seed) * 0.8
        let amp = 26.0 + Double(i) * 13.0
        let baseWidth = [120.0, 66.0, 168.0, 52.0, 96.0][i]
        let cx = size.width * [0.22, 0.44, 0.66, 0.34, 0.82][i] + sin(t * 0.6 + phase) * 26

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        let samples = 30
        for s in 0...samples {
            let y = size.height * Double(s) / Double(samples)
            let wander = sin(y * 0.0058 + t + phase) * amp
                + sin(y * 0.0131 - t * 0.8 + phase * 1.4) * amp * 0.45
            let breath = baseWidth * (0.68 + 0.38 * sin(y * 0.0039 + t * 0.5 + phase))
            left.append(CGPoint(x: cx + wander - breath / 2, y: y))
            right.append(CGPoint(x: cx + wander + breath / 2, y: y))
        }

        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    private func shading(_ i: Int, size: CGSize) -> GraphicsContext.Shading {
        let tip = [violet, rose, violet, teal, rose][(i + seed) % 5]
        return .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: tip.opacity(0.34), location: 0.16),
                .init(color: teal.opacity(0.40), location: 0.40),
                .init(color: green.opacity(0.62), location: 0.68),
                .init(color: green.opacity(0.22), location: 0.92),
                .init(color: .clear, location: 1.0)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height))
    }
}
