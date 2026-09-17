import SwiftUI

/// The reading panel's backdrop: a night sky with an aurora hanging in it.
/// Ribbons are drawn in a Canvas and composited additively, which is what makes
/// the light look like light — a blurred fill on a pale ground never will.
///
/// The shape is a corona, the way it looks in a wide photograph: broad soft
/// curtains fanning down and outward from high overhead, violet and magenta up
/// top, green settling along the bottom. Everything stays heavily blurred —
/// the light has no edges.
struct AuroraNight: View {
    var seed: Int
    /// On a pale ground the same light has to be painted rather than added —
    /// `plusLighter` over near-white shows nothing at all.
    var onLight: Bool = false
    /// Curtains only: no night behind them, no veil over them, nothing opaque.
    /// This is what a reflection needs — the light, with the sky left out.
    var bare: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let night = Color(red: 0.043, green: 0.055, blue: 0.106)
    private let nightLow = Color(red: 0.055, green: 0.098, blue: 0.125)

    // Straight off the photograph: violet and magenta high, pink through the
    // middle, oxygen green low, and a pale lime wash right at the horizon.
    private let violet = Color(red: 0.46, green: 0.36, blue: 0.80)
    private let magenta = Color(red: 0.85, green: 0.33, blue: 0.64)
    private let pink = Color(red: 0.94, green: 0.56, blue: 0.76)
    private let green = Color(red: 0.33, green: 0.84, blue: 0.56)
    private let teal = Color(red: 0.33, green: 0.74, blue: 0.74)
    private let lime = Color(red: 0.72, green: 0.88, blue: 0.48)

    private let count = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.055

            ZStack {
                if !onLight, !bare {
                    LinearGradient(colors: [night, nightLow, night],
                                   startPoint: .top, endPoint: .bottom)
                }

                Canvas { context, size in
                    for i in 0..<count {
                        context.fill(ribbon(i, t: t, size: size), with: shading(i, size: size))
                    }
                }
                .blur(radius: onLight ? 46 : 38)
                // Bare means there is nothing underneath to add light to —
                // additive blending against transparency renders as nothing,
                // which is exactly how the lake ended up empty. The caller
                // does the adding instead.
                .blendMode(onLight || bare ? .normal : .plusLighter)
                .opacity(onLight ? 0.5 : 0.68)

                if !onLight, !bare {
                    // The horizon: in every photograph of one of these the
                    // green pools along the bottom and goes pale at the edge.
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.52),
                        .init(color: green.opacity(0.10), location: 0.80),
                        .init(color: lime.opacity(0.13), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                        .blendMode(.plusLighter)

                    // A wash of violet up top, which is what the sky does
                    // above a corona.
                    LinearGradient(stops: [
                        .init(color: violet.opacity(0.10), location: 0.0),
                        .init(color: .clear, location: 0.55),
                    ], startPoint: .top, endPoint: .bottom)
                        .blendMode(.plusLighter)

                    // Keeps the type legible: the light sits behind a slight
                    // veil, heaviest at the top where the title and thought sit.
                    LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.12), .black.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom)
                }

                if !bare {
                    AuroraGrain.tile
                        .resizable(resizingMode: .tile)
                        .blendMode(onLight ? .multiply : .overlay)
                        .opacity(onLight ? 0.22 : 0.35)
                }
            }
            .drawingGroup()
        }
    }

    /// One curtain of the fan. They all lean out from a point high above the
    /// window, widening as they fall, and each one wanders and breathes on its
    /// own clock.
    private func ribbon(_ i: Int, t: Double, size: CGSize) -> Path {
        let phase = Double(i) * 1.6 + Double(seed) * 0.8
        let lean = [-0.46, -0.26, -0.08, 0.14, 0.32, 0.52][i]
        let amp = 22.0 + Double(i % 3) * 14.0
        let baseWidth = [190.0, 120.0, 230.0, 140.0, 200.0, 130.0][i]
        let apexX = size.width * 0.46 + sin(t * 0.4 + phase) * 44
        let apexY = -size.height * 0.4

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        let samples = 30
        for s in 0...samples {
            let y = size.height * Double(s) / Double(samples)
            // How far down the fan this sample is — 0 at the apex overhead.
            let k = (y - apexY) / (size.height - apexY)
            let wander = sin(y * 0.0051 + t + phase) * amp
                + sin(y * 0.0122 - t * 0.8 + phase * 1.4) * amp * 0.45
            let cx = apexX + lean * size.width * k + wander
            let breath = baseWidth * (0.30 + 1.05 * k) * (0.82 + 0.3 * sin(y * 0.0036 + t * 0.5 + phase))
            left.append(CGPoint(x: cx - breath / 2, y: y))
            right.append(CGPoint(x: cx + breath / 2, y: y))
        }

        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    /// Colour runs down the curtain, not up it: violet and magenta where it
    /// starts overhead, green by the time it reaches the ground.
    private func shading(_ i: Int, size: CGSize) -> GraphicsContext.Shading {
        // Alternating families, so the sky has magenta curtains and green
        // ones crossing each other the way the photograph does.
        let warm = (i + seed) % 2 == 0
        let stops: [Gradient.Stop] = warm
            ? [
                .init(color: .clear, location: 0.0),
                .init(color: violet.opacity(0.30), location: 0.10),
                .init(color: magenta.opacity(0.50), location: 0.34),
                .init(color: pink.opacity(0.34), location: 0.56),
                .init(color: green.opacity(0.34), location: 0.84),
                .init(color: .clear, location: 1.0),
            ]
            : [
                .init(color: .clear, location: 0.0),
                .init(color: violet.opacity(0.20), location: 0.12),
                .init(color: teal.opacity(0.30), location: 0.40),
                .init(color: green.opacity(0.56), location: 0.72),
                .init(color: lime.opacity(0.26), location: 0.94),
                .init(color: .clear, location: 1.0),
            ]
        return .linearGradient(Gradient(stops: stops),
                               startPoint: .zero,
                               endPoint: CGPoint(x: 0, y: size.height))
    }
}
