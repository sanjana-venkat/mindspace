import SwiftUI

// ============================================================
// NOTED — the aurora panel
//
// The left panel is the one place the sky shows through. Four slow,
// low-saturation colour fields drift behind the panel's frost so it reads
// faintly pink, violet and green rather than grey. Calm, not decorative: it
// should register as a TINT, not as a wallpaper. The right side of the window
// is deliberately untouched — the main area stays neutral frost so the cream
// plates read as the brightest thing on screen.
//
// ---- Why this is not a literal port of the brief ----
//
// The brief is written for a web build, where the colour fields sit BEHIND a
// backdrop-filtered frost layer and the frost does the mixing. Here the frost
// is an `NSVisualEffectView` that `WindowConfiguringView` installs *below*
// SwiftUI's hosting view (see GlassGround.swift), so nothing drawn in SwiftUI
// can get underneath it. Anything we draw is already on top of the blur.
//
// Two things follow, and both were arrived at by rendering the composite
// rather than by reading the CSS across:
//
// 1. `mix-blend-mode: screen` is wrong here. Screen always moves a pixel
//    toward white, so over a backdrop this light — the frost composites to
//    roughly 92% luminance whatever the wallpaper is — it is very nearly a
//    no-op, and it cannot produce saturation at all. In the web build the
//    fields screen against the RAW desktop and the frost lightens the result
//    afterwards; that order is not available to us. So the fields are laid on
//    normally, at low alpha, and their own lightness is what keeps the panel
//    from darkening.
//
// 2. The panel must NOT re-apply the window's frost. `GroundSurfaceView`
//    already tints and etches the whole window; a second copy over the left
//    third makes the panel more opaque than the main area, which is the exact
//    inverse of "the panel is the one place the sky shows through". The brief
//    says the panel keeps its existing frost fill at its current opacity — so
//    the panel adds colour and nothing else, and the frost that mixes it down
//    is the one already there.
//
// What keeps the frost winning, then, is field alpha alone — which is what the
// brief asks for anyway: "if the panel looks 'colorful', reduce field opacity."
// ============================================================

/// The composed panel background: aurora, then the frost veil that mixes it
/// down, then the night-sky dot field.
///
/// Attach as a `.background` on the note column, on the same padded box the
/// column's trailing hairline already uses, so tint and divider align exactly.
struct AuroraPanelBackground: View {
    @AppStorage(GroundSurface.storageKey) private var surfaceRaw = GroundSurface.paper.rawValue

    private var glass: Bool { (GroundSurface(rawValue: surfaceRaw) ?? .paper) == .glass }

    var body: some View {
        ZStack {
            // On glass the aurora sits directly on the window's own frost, so
            // the panel stays exactly as transparent as the rest of the
            // window and only gains colour. On paper there is no frost to mix
            // it down, so the fields run a shade quieter instead.
            AuroraField(attenuation: glass ? 1.0 : 0.82)
            PanelDotField()
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - The sky

/// Four soft fields, drifting.
///
/// Each is a heavily blurred ellipse on a seamless loop. "Seamless" is the
/// requirement that shapes the implementation: the brief bans easing at the
/// loop boundary, so an autoreversing animation is out — a reversal is a
/// visible stop even when the curve is linear. Instead a single `phase` runs
/// 0 → 1 on a linear `repeatForever(autoreverses: false)`, and position and
/// scale are derived from it as harmonics of 2πφ, which makes the end state
/// identical to the start state. There is no boundary to see.
private struct AuroraField: View {
    /// Scales every field's alpha together, for the surface it is landing on.
    let attenuation: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var running = false

    /// Position and size are fractions of the panel, so the sky is the same
    /// composition whatever width the window is dragged to.
    private struct Field {
        let color: Color
        let widthFraction: CGFloat
        let center: UnitPoint
        let period: Double
        let opacity: Double
        /// Offsets the field's place on its own loop, so four fields sharing a
        /// construction never move as one mass.
        let seed: CGFloat
    }

    /// A, B, C, D from the brief: pink upper third, green middle, violet lower
    /// third, and a half-strength green washing the bottom edge.
    ///
    /// The opacities are tuned for a normal blend against the frost, not the
    /// brief's `.55` behind a backdrop filter — see the note at the top of
    /// this file. They land the composited panel at roughly 9–13% saturation,
    /// which is the number the `.55` was aiming at. D runs at half, per the
    /// brief, because it is the wash along the bottom edge rather than a field
    /// in its own right.
    private static let fields: [Field] = [
        Field(color: CanvasPalette.auroraPink,   widthFraction: 0.60, center: UnitPoint(x: 0.42, y: 0.18), period: 38, opacity: 0.42, seed: 0.00),
        Field(color: CanvasPalette.auroraGreen,  widthFraction: 0.55, center: UnitPoint(x: 0.60, y: 0.47), period: 46, opacity: 0.34, seed: 0.27),
        Field(color: CanvasPalette.auroraViolet, widthFraction: 0.45, center: UnitPoint(x: 0.34, y: 0.74), period: 52, opacity: 0.40, seed: 0.58),
        Field(color: CanvasPalette.auroraGreen,  widthFraction: 0.50, center: UnitPoint(x: 0.55, y: 0.96), period: 60, opacity: 0.18, seed: 0.81),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(Array(Self.fields.enumerated()), id: \.offset) { _, field in
                    let w = size.width * field.widthFraction
                    Ellipse()
                        .fill(field.color)
                        // A field is wider than it is tall — a band of sky, not
                        // a ball of colour.
                        .frame(width: w, height: w * 0.78)
                        .position(x: size.width * field.center.x,
                                  y: size.height * field.center.y)
                        .opacity(field.opacity * attenuation)
                        .modifier(
                            Drift(
                                phase: running && !reduceMotion ? field.seed + 1 : field.seed,
                                amplitude: CGSize(width: size.width * 0.06,
                                                  height: size.height * 0.06)
                            )
                        )
                        .animation(
                            reduceMotion
                                ? nil
                                : .linear(duration: field.period).repeatForever(autoreverses: false),
                            value: running
                        )
                }
            }
            // 70px in the brief. The blur is what makes these fields sky
            // rather than shapes, so it is applied to the group and generously.
            .blur(radius: 70)
            // Flattened before it meets the panel, so the four fields blend
            // with each other at their own alphas and reach the frost as one
            // sheet of colour rather than as four stacked washes.
            .compositingGroup()
        }
        .onAppear {
            // A frame's grace so the first layout pass is not also the first
            // animation frame — otherwise the fields visibly jump into place.
            guard !reduceMotion else { return }
            DispatchQueue.main.async { running = true }
        }
    }
}

/// Drift: ±6% translation on a figure-eight, and a 0.96–1.08 breath, both
/// derived from one animatable phase.
///
/// x uses cos(2πφ) and y uses sin(4πφ) — integer harmonics, so φ = 0 and φ = 1
/// are the same point and the loop closes on itself. Any non-integer multiplier
/// here would reintroduce the seam the brief is trying to avoid.
private struct Drift: ViewModifier, Animatable {
    var phase: CGFloat
    let amplitude: CGSize

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let a = phase * 2 * .pi
        return content
            .scaleEffect(1.02 + 0.06 * sin(a))
            .offset(x: amplitude.width * cos(a),
                    y: amplitude.height * sin(2 * a))
    }
}

// MARK: - The dot field

/// A night sky rather than a grid: a regular field of 1pt dots at 24pt
/// spacing, with a handful placed larger and darker by hand so the eye reads
/// stars instead of graph paper. Masked to fade to nothing at the panel's
/// right edge, so the tint ends where the neutral half of the window begins
/// and there is never a visible seam down the middle.
///
/// Takes no inputs on purpose. The panel's body re-evaluates on every
/// keystroke in the note editor, and a `Canvas` redraws with its owner; with
/// no properties to change, SwiftUI has nothing to invalidate here.
private struct PanelDotField: View {
    private static let spacing: CGFloat = 24

    /// Seven, by hand. A generated "random" subset reads as noise; these are
    /// placed as fractions of the field so the constellation survives a resize.
    private static let stars: [CGPoint] = [
        CGPoint(x: 0.14, y: 0.09),
        CGPoint(x: 0.63, y: 0.17),
        CGPoint(x: 0.31, y: 0.34),
        CGPoint(x: 0.08, y: 0.52),
        CGPoint(x: 0.52, y: 0.61),
        CGPoint(x: 0.25, y: 0.83),
        CGPoint(x: 0.70, y: 0.92),
    ]

    var body: some View {
        Canvas { context, size in
            let dot = GraphicsContext.Shading.color(CanvasPalette.dot)
            var y = Self.spacing / 2
            while y < size.height {
                var x = Self.spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: dot)
                    x += Self.spacing
                }
                y += Self.spacing
            }

            let star = GraphicsContext.Shading.color(CanvasPalette.dotStar)
            for point in Self.stars {
                // Snapped onto the lattice: a star is one of these dots grown,
                // not a second scattering laid over them.
                let x = (point.x * size.width / Self.spacing).rounded() * Self.spacing + Self.spacing / 2
                let y = (point.y * size.height / Self.spacing).rounded() * Self.spacing + Self.spacing / 2
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 0.3, y: y - 0.3, width: 1.6, height: 1.6)),
                    with: star
                )
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.00),
                    .init(color: .black, location: 0.58),
                    .init(color: .clear, location: 1.00),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .allowsHitTesting(false)
    }
}

/// The same field at half strength, for the margin inside the Organized plate.
/// Masked to the left 30% — this is a margin on a page, not a page background.
struct PlateMarginDots: View {
    private static let spacing: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            let dot = GraphicsContext.Shading.color(CanvasPalette.dotPlate)
            var y = Self.spacing / 2
            while y < size.height {
                var x = Self.spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: dot)
                    x += Self.spacing
                }
                y += Self.spacing
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.00),
                    .init(color: .black, location: 0.18),
                    .init(color: .clear, location: 0.30),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .allowsHitTesting(false)
    }
}
