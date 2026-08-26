import SwiftUI

// ============================================================
// NOTED — the ground
//
// Same object, different light. The paper panels are IDENTICAL in
// both modes — sidebar, capture mats, and every ink-on-paper text
// colour never change. Only the ground swaps, and the splatter
// inverts with it.
//
// Nothing in this file moves, resizes, or restructures anything.
// It is paint: colours, opacities, and one decorative layer that
// sits below all content and never responds to hover, scroll, or
// focus. The layout is frozen — see noted-correction-and-light-mode.md §0.
//
// Ported from noted-correction-and-light-mode.md §1, §2, §4.
// ============================================================

/// Ink is the default. This is a surface choice, not an accessibility
/// setting, so it is never driven by the system appearance — the window
/// stays pinned to `.light` in both modes precisely so the paper panels
/// resolve as paper either way.
enum GroundMode: String, CaseIterable, Identifiable {
    case ink
    case clay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ink: return "Ink"
        case .clay: return "Clay"
        }
    }
}

/// Every colour that depends on which ground is underneath. Anything NOT
/// in here is constant across both modes and lives in `Stoneink` — that
/// split is what guarantees the panels render pixel-identical.
struct GroundPalette {
    let mode: GroundMode

    let ground: Color
    let groundLift: Color
    let groundEdge: Color

    let onGround: Color
    let onGround72: Color
    let onGround42: Color
    let onGround16: Color

    /// Cobalt mixed for THIS ground. One hue, two substrate mixes: the ink
    /// mix carries more luminance, the clay mix more depth. They must read
    /// as the same pigment — if they drift, move the clay mix, never the
    /// ink one. Cobalt sitting ON PAPER is `Stoneink.cobalt600` in both
    /// modes and is not listed here.
    let cobalt: Color
    /// The MY THOUGHT highlighter. A mark, not a surface: no glow, no drop
    /// shadow, no outer stroke.
    let wash: Color
    let bloom: Color

    /// Splatter fills. The §2.1 opacity ceilings are baked into these
    /// alphas — marks are filled at full opacity, so a mark can never
    /// exceed its ceiling by construction.
    let splatCobalt: Color
    let splatPaper: Color
    let vignette: Color

    /// Destructive, mixed for the ground. Not a second accent — it never
    /// appears anywhere except a destructive verb, which is the one place
    /// the palette has always allowed oxide.
    let destructive: Color

    /// Warm ink. Hue ~35°, never 240°, never neutral grey — warmth is the
    /// only thing separating this from stock dark mode. Sampling check:
    /// the red channel is the highest of the three (0x17 > 0x14 > 0x0F).
    static let ink = GroundPalette(
        mode: .ink,
        ground: Color(hex: 0x17140F),
        groundLift: Color(hex: 0x211D16),
        groundEdge: Color(hex: 0x0F0D09),
        onGround: Color(hex: 0xF7F3EA),
        onGround72: Color(hex: 0xF7F3EA, opacity: 0.72),
        onGround42: Color(hex: 0xF7F3EA, opacity: 0.42),
        onGround16: Color(hex: 0xF7F3EA, opacity: 0.16),
        cobalt: Color(hex: 0x2C43E8),
        wash: Color(hex: 0x2C43E8, opacity: 0.28),
        bloom: Color(hex: 0x2C43E8, opacity: 0.18),
        splatCobalt: Color(hex: 0x2C43E8, opacity: 0.14),
        splatPaper: Color(hex: 0xF7F3EA, opacity: 0.08),
        vignette: Color(hex: 0x0F0D09, opacity: 0.55),
        destructive: Color(hex: 0xDE9077)
    )

    /// Deliberately deeper and warmer than the original `#D9D3C9` greige.
    /// That greige was the source of the original dullness; it must not
    /// creep back up.
    static let clay = GroundPalette(
        mode: .clay,
        ground: Color(hex: 0xC9BEA9),
        groundLift: Color(hex: 0xBFB29B),
        groundEdge: Color(hex: 0xB3A48B),
        onGround: Color(hex: 0x16130E),
        onGround72: Color(hex: 0x16130E, opacity: 0.72),
        onGround42: Color(hex: 0x16130E, opacity: 0.42),
        onGround16: Color(hex: 0x16130E, opacity: 0.16),
        cobalt: Color(hex: 0x1B2FC7),
        wash: Color(hex: 0x1B2FC7, opacity: 0.16),
        bloom: Color(hex: 0x1B2FC7, opacity: 0.10),
        splatCobalt: Color(hex: 0x1B2FC7, opacity: 0.12),
        splatPaper: Color(hex: 0x16130E, opacity: 0.07),
        vignette: Color(hex: 0x78684E, opacity: 0.16),
        destructive: Color(hex: 0x96412A)
    )

    static func of(_ mode: GroundMode) -> GroundPalette {
        switch mode {
        case .ink: return .ink
        case .clay: return .clay
        }
    }

    var isInk: Bool { mode == .ink }
}

private struct GroundPaletteKey: EnvironmentKey {
    static let defaultValue: GroundPalette = .ink
}

extension EnvironmentValues {
    /// Read this anywhere a colour depends on what's underneath. Anything
    /// on paper must NOT read it — that's what keeps the panels identical.
    var ground: GroundPalette {
        get { self[GroundPaletteKey.self] }
        set { self[GroundPaletteKey.self] = newValue }
    }
}

/// Where the mode is persisted. `data-ground` on the app shell, in
/// AppStorage form.
enum GroundStorage {
    static let key = "noted.groundMode"
}

// MARK: - The splatter
//
// §2 is a hard reduction. The previous marks were ~85% opacity and several
// hundred px across, sitting on top of thought blocks in the middle of the
// content column. Three corrections, all enforced structurally below:
//
//   §2.1 Opacity is carried by the FILL COLOUR, not by an .opacity()
//        modifier, so a mark can never exceed the ceiling.
//   §2.2 Placement is computed from the content-safe column and any mark
//        that would intersect it is not drawn at all.
//   §2.3 Three marks maximum, longest dimension <= 220px, and every mark
//        is either cobalt or paper. No neutrals — a grey mark reads as
//        dirt on the screen.

/// One irregular body traced through a fixed point-set. A blurred circle
/// reads as a gradient blob, not as ink, so the irregularity is in the
/// path. Fixed variants, no runtime randomness: the mark set is identical
/// on every load.
private struct SplatBlob: Shape {
    var variant: Int

    private static let pointSets: [[CGPoint]] = [
        [
            CGPoint(x: 0.50, y: 0.03), CGPoint(x: 0.79, y: 0.11), CGPoint(x: 0.95, y: 0.35),
            CGPoint(x: 0.87, y: 0.63), CGPoint(x: 0.67, y: 0.83), CGPoint(x: 0.42, y: 0.97),
            CGPoint(x: 0.17, y: 0.87), CGPoint(x: 0.03, y: 0.59), CGPoint(x: 0.11, y: 0.31),
            CGPoint(x: 0.29, y: 0.09),
        ],
        [
            CGPoint(x: 0.46, y: 0.02), CGPoint(x: 0.74, y: 0.08), CGPoint(x: 0.97, y: 0.28),
            CGPoint(x: 0.93, y: 0.55), CGPoint(x: 0.98, y: 0.78), CGPoint(x: 0.71, y: 0.93),
            CGPoint(x: 0.45, y: 0.99), CGPoint(x: 0.21, y: 0.90), CGPoint(x: 0.02, y: 0.68),
            CGPoint(x: 0.07, y: 0.40), CGPoint(x: 0.22, y: 0.14),
        ],
        [
            CGPoint(x: 0.52, y: 0.05), CGPoint(x: 0.83, y: 0.16), CGPoint(x: 0.92, y: 0.44),
            CGPoint(x: 0.79, y: 0.70), CGPoint(x: 0.55, y: 0.90), CGPoint(x: 0.30, y: 0.95),
            CGPoint(x: 0.08, y: 0.76), CGPoint(x: 0.06, y: 0.46), CGPoint(x: 0.20, y: 0.20),
        ],
    ]

    func path(in rect: CGRect) -> Path {
        let points = Self.pointSets[variant % Self.pointSets.count]
            .map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        path.closeSubpath()
        return path
    }
}

/// §2.3 — the hard ceiling on a mark's longest dimension.
private let splatMaxSize: CGFloat = 220

/// §2.2 — the margin held clear on each side of the content column.
private let contentSafeMargin: CGFloat = 48

/// Three marks, in the gutters only.
///
/// `contentColumnWidth` is the width of the strip occupied by the note
/// header, thought blocks, and capture cards, measured from the canvas's
/// leading edge. The safe column is that strip plus `contentSafeMargin` on
/// each side, and no mark may intersect it at any point. When the window is
/// too narrow to leave a real gutter, nothing is drawn — an invisible
/// splatter is correct, a mark over the text is not.
struct GroundSplatterField: View {
    @Environment(\.ground) private var ground
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let contentColumnWidth: CGFloat

    @State private var appeared = false

    private struct Mark: Identifiable {
        let id: Int
        /// Fraction of the gutter's own width, not the canvas's.
        let gutterX: CGFloat
        /// Fraction of canvas height.
        let y: CGFloat
        let size: CGFloat
        let rotation: Angle
        let kind: Kind
        let paper: Bool
        let delay: Double
    }

    private enum Kind { case blot, spray, fleck }

    /// Three. Not four, not eight. Every one is cobalt or paper — the
    /// grey/desaturated marks are gone entirely.
    private let marks: [Mark] = [
        // Top-right corner, above the tag pills.
        Mark(id: 0, gutterX: 0.58, y: 0.13, size: 74, rotation: .degrees(-18),
             kind: .fleck, paper: true, delay: 0.00),
        // Right gutter, mid-low.
        Mark(id: 1, gutterX: 0.46, y: 0.55, size: 190, rotation: .degrees(34),
             kind: .blot, paper: false, delay: 0.08),
        // Bottom-right dead zone.
        Mark(id: 2, gutterX: 0.62, y: 0.86, size: 205, rotation: .degrees(12),
             kind: .spray, paper: false, delay: 0.16),
    ]

    var body: some View {
        GeometryReader { proxy in
            // Everything from here rightwards is fair game; everything to
            // the left of it is content, or the margin protecting content.
            let safeEdge = contentColumnWidth + contentSafeMargin
            let gutterWidth = proxy.size.width - safeEdge

            ZStack {
                // A gutter narrower than the smallest mark cannot hold one
                // without crossing the safe column, so it holds none.
                if gutterWidth > 96 {
                    ForEach(marks) { mark in
                        let size = min(mark.size, splatMaxSize)
                        // Clamp so the mark's own bounding box — not just
                        // its centre — stays clear of the safe column.
                        let minCentre = safeEdge + size / 2
                        let maxCentre = proxy.size.width - size / 2
                        let wanted = safeEdge + gutterWidth * mark.gutterX
                        let centreX = min(max(wanted, minCentre), maxCentre)

                        if minCentre <= maxCentre {
                            markView(mark)
                                .frame(width: size, height: size)
                                .rotationEffect(mark.rotation)
                                // Just enough to break the vector edge so it
                                // reads as ink rather than a cut-out. Not
                                // enough to turn it into a blob.
                                .blur(radius: 3)
                                .position(x: centreX, y: proxy.size.height * mark.y)
                                .opacity((appeared || reduceMotion) ? 1 : 0)
                                .animation(reduceMotion ? nil
                                           : .easeOut(duration: 0.9).delay(mark.delay),
                                           value: appeared)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { appeared = true }
    }

    /// The fill already carries the §2.1 ceiling. Never wrap these in an
    /// additional `.opacity()` above 1 — and never tint them with anything
    /// that isn't cobalt or paper.
    private func fill(_ mark: Mark) -> Color {
        mark.paper ? ground.splatPaper : ground.splatCobalt
    }

    @ViewBuilder
    private func markView(_ mark: Mark) -> some View {
        let tint = fill(mark)
        switch mark.kind {
        case .blot:
            // One dense body, two satellites that broke off on impact.
            GeometryReader { proxy in
                let s = min(proxy.size.width, proxy.size.height)
                ZStack {
                    SplatBlob(variant: 0).fill(tint)
                    Circle().fill(tint).frame(width: s * 0.11, height: s * 0.11)
                        .offset(x: s * 0.26, y: -s * 0.19)
                    Circle().fill(tint).frame(width: s * 0.055, height: s * 0.055)
                        .offset(x: s * 0.36, y: -s * 0.06)
                }
            }
        case .spray:
            // Droplets on a directional arc — sparser and smaller as the
            // throw runs out of energy, which is what reads as motion.
            GeometryReader { proxy in
                let s = min(proxy.size.width, proxy.size.height)
                ZStack {
                    ForEach(0..<10, id: \.self) { i in
                        let t = Double(i) / 9.0
                        let arc = Angle.degrees(200 + t * 70)
                        let radius = 0.30 + t * 0.62
                        let dot = s * (0.10 - CGFloat(t) * 0.065)
                        Circle()
                            .fill(tint)
                            .frame(width: dot, height: dot)
                            .offset(x: CGFloat(cos(arc.radians)) * radius * s * 0.62,
                                    y: CGFloat(sin(arc.radians)) * radius * s * 0.62)
                    }
                }
            }
        case .fleck:
            // Punctuation, not a presence.
            GeometryReader { proxy in
                let s = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Circle().fill(tint).frame(width: s * 0.35, height: s * 0.35)
                    Circle().fill(tint).frame(width: s * 0.16, height: s * 0.16)
                        .offset(x: s * 0.32, y: s * 0.19)
                    Circle().fill(tint).frame(width: s * 0.09, height: s * 0.09)
                        .offset(x: -s * 0.22, y: s * 0.27)
                    Circle().fill(tint).frame(width: s * 0.11, height: s * 0.11)
                        .offset(x: s * 0.14, y: -s * 0.27)
                }
            }
        }
    }
}

// MARK: - The ground itself

/// Base fill, ambient bloom, grain, vignette — bottom to top, in that
/// order. The splatter is placed by the canvas that knows where its own
/// content column is, so it is NOT part of this stack.
///
/// Everything here is decorative and sits below all content. Nothing in it
/// ever responds to hover, scroll, or focus.
struct GroundBackdrop: View {
    @Environment(\.ground) private var ground

    var body: some View {
        ZStack {
            ground.ground

            // Two localized fields, NOT a full-canvas wash. The distinction
            // matters more than the opacity does: a cobalt gradient spread
            // across the whole ground pushes the blue channel above the red
            // everywhere and the ink stops being warm — which is the one
            // thing separating this from stock dark mode. Most of the ground
            // must sample as bare ink, with the bloom felt at two regions.
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                ZStack {
                    bloomField(w: w, h: h, cx: 0.74, cy: 0.72, radius: 0.34, strength: 1.0)
                    bloomField(w: w, h: h, cx: 0.20, cy: 0.10, radius: 0.20, strength: 0.55)
                }
                .blur(radius: 80)
            }

            GroundGrain()
        }
    }

    /// Felt as a warmth in the dark, not seen as a circle. If you can point
    /// at an edge, the radius is too tight. Nearly invisible on clay — that
    /// is expected and correct; it does quiet work at the edges, and raising
    /// it to compensate is exactly what §2.1's ceiling exists to prevent.
    private func bloomField(w: CGFloat, h: CGFloat,
                            cx: CGFloat, cy: CGFloat,
                            radius: CGFloat, strength: Double) -> some View {
        let r = max(w, h) * radius
        return Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: ground.bloom.opacity(strength), location: 0),
                        .init(color: ground.bloom.opacity(strength * 0.38), location: 0.45),
                        .init(color: ground.bloom.opacity(0), location: 1),
                    ],
                    center: .center, startRadius: 0, endRadius: r
                )
            )
            .frame(width: r * 2, height: r * 2)
            .position(x: w * cx, y: h * cy)
    }
}

/// Grain, mixed for the ground it lands on. A flat field looks like a
/// screen; a grained one looks like a surface — which matters more on ink
/// than it ever did on clay.
///
/// On clay the specks are ink multiplied in. On ink they are paper specks
/// laid on top: black multiply over near-black is invisible. Kept sparse
/// either way, since dense specks average into a grey cast and take the
/// warmth of the ink with them.
struct GroundGrain: View {
    @Environment(\.ground) private var ground

    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 11)
            let density = ground.isInk ? 26.0 : 7.0
            let count = Int(Double(size.width * size.height) / density)
            let speck: Color = ground.isInk ? Color(hex: 0xF7F3EA) : .black
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                             with: .color(speck))
            }
        }
        .blendMode(ground.isInk ? .normal : .multiply)
        .opacity(ground.isInk ? 0.045 : Stoneink.grogOpacity)
        .allowsHitTesting(false)
    }
}

/// The corners fall away so the slab reads as an object with edges rather
/// than a flat fill. Warm in both modes — a neutral or blue-black vignette
/// is the fastest way to lose the warmth the ground depends on.
struct GroundVignette: View {
    @Environment(\.ground) private var ground

    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [Color.clear, ground.vignette],
                center: .center,
                startRadius: min(proxy.size.width, proxy.size.height) * 0.35,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.78
            )
        }
        .allowsHitTesting(false)
    }
}
