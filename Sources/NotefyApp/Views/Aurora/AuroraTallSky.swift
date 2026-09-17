import SwiftUI

/// One aurora, taller than the window, with the window as a camera onto it.
///
/// The launch sequence looks at the top of it. When setup arrives, the camera
/// pans down the same sky to the foot of the curtains, where the light pools
/// over a ridge line. Nothing slides off the screen — the view moves, the way
/// it would if you tilted your head down.
struct AuroraTallSky: View {
    /// 0 is the top of the sky, 1 is down on the snow.
    var pan: Double

    /// A step change should feel like the sky moved, not just the text: every
    /// time the camera travels, the curtains surge and drift with it.
    @State private var surge: Double = 0
    @State private var drift: CGFloat = 0

    /// How much taller the sky is than the window it is seen through. Tall
    /// enough that the descent through setup has somewhere to go.
    private let scale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let sceneHeight = h * scale

            ZStack(alignment: .bottom) {
                AuroraNight(seed: 1)
                    .frame(width: w, height: sceneHeight)

                // Dawn. The sky is night overhead and morning at the foot of
                // it, so descending this scene is the app crossing from dark
                // into light — which is the choice setup ends on.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.36),
                    .init(color: Color(red: 0.30, green: 0.40, blue: 0.62).opacity(0.30), location: 0.58),
                    .init(color: Color(red: 0.62, green: 0.72, blue: 0.88).opacity(0.62), location: 0.76),
                    .init(color: Color(red: 0.88, green: 0.90, blue: 0.96).opacity(0.88), location: 0.90),
                    .init(color: Color(red: 0.95, green: 0.94, blue: 0.97), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(width: w, height: sceneHeight)

                // The light does not stop at the horizon: it pools above it,
                // which is what makes the ground read as ground.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(red: 0.30, green: 0.86, blue: 0.60).opacity(0.16), location: 0.62),
                    .init(color: Color(red: 0.62, green: 0.88, blue: 0.62).opacity(0.10), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(width: w, height: h * 0.55)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .offset(y: -h * 0.16)

                ground(width: w, height: h)
            }
            .overlay {
                // The surge: light running through the whole sky as it moves.
                LinearGradient(colors: [.clear,
                                        Color(red: 0.62, green: 1.0, blue: 0.86).opacity(0.22),
                                        .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: w, height: sceneHeight)
                    .blendMode(.plusLighter)
                    .opacity(surge)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: sceneHeight, alignment: .top)
            // pan 0 keeps the top of the sky in frame; pan 1 pulls the scene
            // up until the snow at its foot is what you are looking at.
            .offset(x: drift, y: -pan * (sceneHeight - h))
            .frame(width: w, height: h, alignment: .top)
            .clipped()
            .onChange(of: pan) { _, _ in sweep() }
        }
        .ignoresSafeArea()
    }

    /// A pulse of light and a sideways lean, so moving between steps reads as
    /// the sky itself shifting rather than a page being swapped.
    private func sweep() {
        withAnimation(.easeOut(duration: 0.45)) {
            surge = 1
            drift = 16
        }
        withAnimation(.easeInOut(duration: 1.1).delay(0.3)) {
            surge = 0
            drift = 0
        }
    }

    /// The foot of the sky: haze, a far treeline, and snow under it.
    ///
    /// The snow is the point. The top of this scene is the app at night and the
    /// bottom is the app by day — the same light, once as curtains and once as
    /// what the curtains land on.
    private func ground(width w: CGFloat, height h: CGFloat) -> some View {
        // Deep enough that by the end of the descent the window is mostly
        // snow — the light half of the app, seen from inside the scene.
        let snowHeight = h * 0.52
        let treeHeight = h * 0.055

        return ZStack(alignment: .bottom) {
            // Where the sky meets the land nothing has an edge: haze first.
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(red: 0.42, green: 0.60, blue: 0.66).opacity(0.20), location: 0.55),
                .init(color: Color(red: 0.62, green: 0.78, blue: 0.80).opacity(0.34), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: h * 0.17)
                .blur(radius: 22)
                .offset(y: -snowHeight + treeHeight * 0.35)

            // A town somewhere off under the treeline.
            RadialGradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.34), .clear],
                           center: .bottom, startRadius: 1, endRadius: w * 0.16)
                .frame(width: w * 0.42, height: h * 0.07)
                .blendMode(.plusLighter)
                .offset(x: w * 0.16, y: -snowHeight - treeHeight * 0.1)

            TreeLine(seed: 7)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.10))
                .frame(width: w, height: treeHeight)
                .blur(radius: 0.7)
                .offset(y: -snowHeight + treeHeight * 0.42)

            snow(width: w, height: snowHeight)
        }
    }

    /// Snow at night: bright, but blue — it is lit by the sky, and the sky is
    /// green and violet. Everything is composed inside one clip, or the blurred
    /// pieces leave their own rectangles on the field.
    private func snow(width w: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(red: 0.44, green: 0.56, blue: 0.62), location: 0),
                .init(color: Color(red: 0.60, green: 0.67, blue: 0.78), location: 0.45),
                .init(color: Color(red: 0.74, green: 0.77, blue: 0.88), location: 1),
            ], startPoint: .top, endPoint: .bottom)

            // The curtains landing on the field.
            LinearGradient(colors: [Color(red: 0.50, green: 0.98, blue: 0.76).opacity(0.26), .clear],
                           startPoint: .top, endPoint: .bottom)
                .blendMode(.plusLighter)

            // Drifts: shallow shadows, no edges anywhere.
            ForEach(0..<4, id: \.self) { i in
                Ellipse()
                    .fill(Color(red: 0.34, green: 0.42, blue: 0.62).opacity(0.30))
                    .frame(width: w * [0.52, 0.3, 0.62, 0.26][i],
                           height: height * [0.62, 0.45, 0.55, 0.4][i])
                    .blur(radius: 30)
                    .offset(x: w * [-0.3, 0.18, 0.4, -0.04][i],
                            y: height * [0.34, 0.46, 0.24, 0.54][i])
            }

            AuroraGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(.multiply)
                .opacity(0.14)
        }
        .frame(width: w, height: height)
        .clipShape(SnowField())
        .overlay {
            // The lit edge where the field meets the trees.
            SnowField()
                .stroke(Color(red: 0.78, green: 0.98, blue: 0.90).opacity(0.35), lineWidth: 1.2)
                .blur(radius: 1.2)
                .frame(width: w, height: height)
        }
    }
}

/// A far treeline: clumps of conifers with open field between them, seeded so
/// it is the same view every launch. Small — these are trees a long way off.
struct TreeLine: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        var state = UInt64(truncatingIfNeeded: 0x9E3779B9 &+ seed &* 104_729)
        func rand() -> CGFloat {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }

        var path = Path()
        let base = rect.maxY
        // The band of scrub they stand in, thinning toward the open middle.
        path.addRect(CGRect(x: rect.minX, y: base - rect.height * 0.13,
                            width: rect.width, height: rect.height * 0.13))

        var x = rect.minX - 8
        while x < rect.maxX + 8 {
            let spacing = 7 + rand() * 16
            // Crowded at the edges, open across the middle third.
            let fromCentre = min(1, abs((x - rect.midX) / (rect.width / 2)))
            let density = 0.18 + fromCentre * fromCentre * 1.15
            if rand() < density {
                let height = rect.height * (0.34 + rand() * 0.62) * (0.5 + 0.7 * fromCentre)
                let halfWidth = max(1.4, spacing * (0.2 + rand() * 0.16))
                path.move(to: CGPoint(x: x - halfWidth, y: base))
                path.addQuadCurve(to: CGPoint(x: x, y: base - height),
                                  control: CGPoint(x: x - halfWidth * 0.3, y: base - height * 0.5))
                path.addQuadCurve(to: CGPoint(x: x + halfWidth, y: base),
                                  control: CGPoint(x: x + halfWidth * 0.3, y: base - height * 0.5))
                path.closeSubpath()
            }
            x += spacing
        }
        return path
    }
}

/// The snowfield's own outline: a shallow crest across the top, lower at the
/// left where the land falls away. Straight edges read as a grey rectangle.
struct SnowField: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Nearly flat: this is a plain seen from across it, not a hill.
        let leftY = rect.minY + rect.height * 0.17
        let crestY = rect.minY + rect.height * 0.05
        let rightY = rect.minY + rect.height * 0.11
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: leftY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + rect.width * 0.08, y: crestY),
                          control: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rightY),
                          control: CGPoint(x: rect.maxX - rect.width * 0.16, y: crestY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
