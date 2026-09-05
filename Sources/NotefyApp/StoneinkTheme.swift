import CoreText
import SwiftUI

// ============================================================
// NOTED — "Stoneink" design system
// Material thesis: clay holds, ink lands. Every surface is either
// CLAY (the opaque substrate) or INK (the mark on it). No glass,
// no chrome, no glow, no translucency, no #FFFFFF/#000000.
// Ported 1:1 from tokens.css / BRAND.md / COMPONENTS.md.
// ============================================================

enum Stoneink {
    // ---- 1. Clay ramp — unfired stoneware, never cream/paper ----
    // Pigment pass: the ground deepened and warmed (was ~6% off the panel
    // tone, so nothing read as sitting *on* anything) while the panel
    // family lifted toward near-white, so a screenshot desaturated to
    // greyscale still shows panels as clearly separate shapes from the bed.
    static let clay000 = Color(hex: 0xFBF8F1) // slip — panel-raised: capture cards, the one element above panel
    static let clay050 = Color(hex: 0xF7F3EA) // leaf — panel: the writing surface
    static let clay100 = Color(hex: 0xF1EADC) // slab — cards, panels (between leaf and bed)
    static let clay200 = Color(hex: 0xC9BEA9) // bed  — app background, deepened ~10% L, chroma up
    static let clay300 = Color(hex: 0xCFC4B5) // rim  — dividers
    static let clay400 = Color(hex: 0xB3A593) // hairline, strong borders
    static let clay500 = Color(hex: 0x8E8070) // icons/non-text marks ONLY
    static let clay600 = Color(hex: 0x6A5D50) // minimum for text
    static let clay700 = Color(hex: 0x4B4139)
    static let clay800 = Color(hex: 0x322B26)
    static let clay900 = Color(hex: 0x1F1A16) // fired

    /// Vignette edge / window-chrome zone — a shade below the bed itself,
    /// felt at the shell's corners rather than seen as its own patch.
    static let bedDeep = Color(hex: 0xBFB29B)

    // ---- 2. Ink — iron-gall, warm near-black, never pure black ----
    static let ink900 = Color(hex: 0x16130E) // body text — warm black, not neutral
    static let ink700 = Color(hex: 0x2A241C) // headings on light slabs

    // ---- Cobalt — one hue, three dilutions. Never a second blue. ----
    // Ink strength is the accent's only 100%-chroma appearance; wash and
    // bloom are that same hue diluted, never a separate cooler blue —
    // that's what makes every blue on screen read as one pigment.
    static let cobalt700 = Color(hex: 0x16249C) // pressed
    static let cobalt600 = Color(hex: 0x1B2FC7) // ink strength — brand dot, primary button, cursor
    static let cobalt500 = Color(hex: 0x3F51D6) // hover
    static let cobalt300 = Color(hex: 0x1B2FC7, opacity: 0.35) // edge-strength dilution
    static let cobalt100 = Color(hex: 0x1B2FC7, opacity: 0.16) // wash — highlighter, selected row
    static let cobalt050 = Color(hex: 0x1B2FC7, opacity: 0.055) // bloom — splatter, ambient bleed
    static let cobaltEdge = Color(hex: 0x1B2FC7, opacity: 0.28) // wash-bleed edge stroke only

    // ---- Kiln pigments — semantic, rare ----
    static let oxide600 = Color(hex: 0x96412A)   // destructive
    static let celadon600 = Color(hex: 0x4F6B52) // success
    static let amber600 = Color(hex: 0x7C5F18)   // warning
    static let oxide050 = Color(hex: 0xF4E6E0)
    static let celadon050 = Color(hex: 0xE6EDE4)
    static let amber050 = Color(hex: 0xF2EBD8)

    // ---- Semantic surfaces ----
    static let surfaceBed = clay200
    static let surfaceSlab = clay100
    static let surfaceLeaf = clay050
    static let surfaceSlip = clay000
    static let surfacePress = Color(hex: 0xEFE9DC) // panel-sunken — search field, inset wells
    static let surfaceStamp = clay800

    static let textPrimary = ink900
    static let textSecondary = Color(hex: 0x16130E, opacity: 0.70) // ink-70
    static let textMuted = Color(hex: 0x16130E, opacity: 0.45) // ink-45
    static let textInverse = clay050
    static let textAccent = cobalt600

    static let edgeDark = Color(hex: 0x2D2218, opacity: 0.10)
    static let score = clay300

    static let borderHair = clay300
    static let borderFirm = clay400

    // ---- Type scale (points, not rem — 1rem == 16pt on macOS text) ----
    static let tDisplay: CGFloat = 56
    static let tTitle: CGFloat = 28
    static let tHeading: CGFloat = 21
    static let tSubhead: CGFloat = 17
    static let tRead: CGFloat = 17
    static let tBody: CGFloat = 15
    static let tLabel: CGFloat = 13
    static let tMark: CGFloat = 11

    static let lhRead: CGFloat = 1.65
    static let lhUI: CGFloat = 1.45
    static let trMark: CGFloat = 0.09 // tracking, mono always tracked out

    // ---- Space — clay is thick ----
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 24
    static let sp6: CGFloat = 32
    static let sp7: CGFloat = 48
    static let sp8: CGFloat = 64

    static let measure: CGFloat = 620 // ~68ch reading column, hard cap

    /// Sand in the clay body — the grog. Ceiling: 4%. If you can consciously
    /// perceive it as texture, it is too strong.
    static let grogOpacity: Double = 0.035

    // ---- Motion ----
    static let easeClay = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.30)
    static let easeInk = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.13)
}

extension Color {
    /// The lip of a slab: a warm, near-white hairline highlight.
    static let stoneEdgeLight = Color(hex: 0xFFFBF4, opacity: 0.72)
}

// MARK: - Depth (the kiln model)
//
// Depth is impression, not elevation. Nothing floats in air.
// Hard rule: no shadow blur radius may exceed 12px. Hover never lifts —
// hover only wets the surface (steps one clay value lighter).

extension View {
    /// The one-at-a-time page reveal: as a pair scrolls past identity it
    /// fades out while rising further away; the next pair rises up from
    /// below and fades in as it settles. Paired with `.scrollTargetBehavior
    /// (.paging)` so exactly one capture + thought is ever on screen.
    func revealTransition() -> some View {
        self.scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .offset(y: phase.value * 60)
        }
    }

    /// A pillow of clay resting on the bed — the "pinch": a soft glow of
    /// highlight along the top inner edge, a soft pool of shade along the
    /// bottom, and a cast shadow with real blur beneath it. This is what
    /// reads as inflated, pinched clay rather than a flat card with a
    /// hairline rule — the claymorphic signature, not the kiln-fired one.
    func depthSlab<S: Shape>(_ shape: S) -> some View {
        self
            .overlay {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.stoneEdgeLight.opacity(0.95), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 11)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, Stoneink.edgeDark.opacity(0.65)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 15)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .shadow(color: Color(hex: 0x2D2218, opacity: 0.10), radius: 3, x: 0, y: 2)
            .shadow(color: Color(hex: 0x2D2218, opacity: 0.16), radius: 18, x: 0, y: 10)
    }

    /// A well cut into the clay — inputs, search, wells, active tabs.
    /// Inner shadow only; never an outline.
    func depthPress<S: Shape>(_ shape: S) -> some View {
        self.overlay {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(hex: 0x2D2218, opacity: 0.22), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 8)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.stoneEdgeLight).frame(height: 1)
                }
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }

    /// A mark pressed into the surface — checkbox fill, toggle track.
    func depthStamp<S: Shape>(_ shape: S) -> some View {
        self.overlay {
            LinearGradient(
                colors: [Color(hex: 0x2D2218, opacity: 0.30), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }

    /// Drag only. Never for hover/rest.
    func depthLift<S: Shape>(_ shape: S) -> some View {
        self.shadow(color: Color(hex: 0x2D2218, opacity: 0.24), radius: 6, x: 0, y: 4)
    }

    /// The score line: not a border, a line scored into the clay with a
    /// tool. A light hairline beneath the dark one is the displaced burr.
    func scoreLineTop() -> some View {
        self.overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(Stoneink.score).frame(height: 1)
                Rectangle().fill(Color.stoneEdgeLight).frame(height: 1)
            }
        }
    }
}

// MARK: - Geometry — thrown, not extruded
//
// Radii are large and deliberately unequal: 1-2px variance per corner
// reads as handmade. Never a uniform radius.

struct ThrownRect: Shape {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomRight: CGFloat
    var bottomLeft: CGFloat

    // Bumped rounder across the board per direct request — still thrown
    // (unequal per corner), just a visibly softer, more rounded object.
    static let lg = ThrownRect(topLeft: 34, topRight: 31, bottomRight: 35, bottomLeft: 30)
    static let md = ThrownRect(topLeft: 24, topRight: 22, bottomRight: 25, bottomLeft: 21)
    static let sm = ThrownRect(topLeft: 16, topRight: 17, bottomRight: 15, bottomLeft: 17)
    static let press = ThrownRect(topLeft: 12, topRight: 13, bottomRight: 12, bottomLeft: 13)

    func path(in rect: CGRect) -> Path {
        let tl = min(topLeft, rect.width / 2, rect.height / 2)
        let tr = min(topRight, rect.width / 2, rect.height / 2)
        let br = min(bottomRight, rect.width / 2, rect.height / 2)
        let bl = min(bottomLeft, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A rolled coil of clay — tags, pills. Perfectly round; a coil has no
/// corners to throw unevenly.
typealias CoilShape = Capsule

// MARK: - Type
//
// Three families, everywhere in the app:
//
//   Narnia          — display. Faras Dina's art-deco face, Sanjana's own
//                     file: condensed, high contrast, counters nearly shut.
//                     One weight, no axes, display sizes only.
//                     Always uppercase; that is what makes it a masthead.
//   Hanken Grotesk  — everything read, at Light. Plain and open, so it sits
//                     under the display face without arguing with it.
//   Geist Mono      — machine strings only.
//
// The old rule here was "user ink is Newsreader, app chrome is Plex". The
// split survives, but it is now carried by weight and italic inside one text
// family rather than by a second typeface — a serif for the user and a
// grotesque for the chrome was reading as two apps stitched together.
//
// These are PostScript names, not family names. `Font.custom` fails SILENTLY
// to San Francisco when a name doesn't resolve, so a typo here looks like a
// design choice rather than a bug.

enum StoneFont {
    private static let wght: UInt32 = 0x77676874

    private static func varied(_ name: String, _ size: CGFloat, _ axes: [UInt32: CGFloat]) -> Font {
        var variations: [CFNumber: CFNumber] = [:]
        for (tag, value) in axes { variations[tag as CFNumber] = value as CFNumber }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name,
            kCTFontVariationAttribute: variations
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// Narnia has one weight and no axes; the argument is ignored so no call
    /// site can ask for a synthetic bold. See CanvasTypography.display.
    private static func display(_ size: CGFloat, _ weight: CGFloat = 0) -> Font {
        .custom("Narnia", size: size)
    }
    private static func text(_ size: CGFloat, _ weight: CGFloat = 330) -> Font {
        varied("HankenGrotesk-Regular", size, [wght: weight])
    }

    static func display() -> Font { display(Stoneink.tDisplay * 1.12) }
    static func title() -> Font { display(Stoneink.tTitle * 1.12) }
    static func heading() -> Font { display(Stoneink.tHeading * 1.12) }
    static func read() -> Font { text(Stoneink.tRead) }
    static func readSmall() -> Font { text(Stoneink.tRead - 2) }
    static func readSemibold() -> Font { text(Stoneink.tSubhead, 600) }
    static func readItalic() -> Font { varied("HankenGrotesk-Italic", Stoneink.tRead, [wght: 330]) }

    static func subhead() -> Font { text(Stoneink.tSubhead, 620) }
    static func body() -> Font { text(Stoneink.tBody) }
    static func bodyMedium() -> Font { text(Stoneink.tBody, 500) }
    static func label() -> Font { text(Stoneink.tLabel, 500) }

    static func mark() -> Font { .custom("GeistMono-Regular", size: Stoneink.tMark) }
    static func markMedium() -> Font { .custom("GeistMono-Medium", size: Stoneink.tMark) }
}

// MARK: - The mark
//
// A single ink drop with four irregular satellites. The drop is an
// ovoid blob with one drawn-out tail, as though it hit at an angle —
// never a perfect circle, never symmetric.

struct InkDrop: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // An ovoid body pulled toward the bottom-left, with a tail drawn
        // out to the upper-right — the angle-of-impact silhouette.
        path.move(to: CGPoint(x: w * 0.30, y: h * 0.18))
        path.addCurve(
            to: CGPoint(x: w * 0.86, y: h * 0.08),
            control1: CGPoint(x: w * 0.48, y: h * 0.02),
            control2: CGPoint(x: w * 0.70, y: h * -0.02)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.94, y: h * 0.46),
            control1: CGPoint(x: w * 1.00, y: h * 0.16),
            control2: CGPoint(x: w * 1.00, y: h * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.94),
            control1: CGPoint(x: w * 0.88, y: h * 0.62),
            control2: CGPoint(x: w * 0.78, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.14, y: h * 0.70),
            control1: CGPoint(x: w * 0.36, y: h * 1.00),
            control2: CGPoint(x: w * 0.14, y: h * 0.90)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.30, y: h * 0.18),
            control1: CGPoint(x: w * 0.12, y: h * 0.48),
            control2: CGPoint(x: w * 0.10, y: h * 0.32)
        )
        path.closeSubpath()
        return path
    }
}

/// Full mark: drop + 4 irregular satellite specks, always cobalt, never
/// rotated or recolored outside the pigment dilutions.
struct StoneinkMark: View {
    var tint: Color = Stoneink.cobalt600
    var showSpecks: Bool = true

    private let speckOffsets: [(CGFloat, CGFloat, CGFloat)] = [
        (1.32, -0.18, 0.10), (1.18, 0.62, 0.07),
        (-0.22, 0.98, 0.085), (0.55, 1.18, 0.06),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack(alignment: .topLeading) {
                if showSpecks {
                    ForEach(speckOffsets.indices, id: \.self) { i in
                        let (dx, dy, r) = speckOffsets[i]
                        Circle()
                            .fill(tint)
                            .frame(width: size * r, height: size * r)
                            .position(x: size * 0.5 + size * dx, y: size * 0.5 + size * dy)
                    }
                }
                InkDrop()
                    .fill(tint)
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Buttons

enum StoneButtonVariant {
    case ink, stamp, bare, oxide
    /// Sits directly on the ground: hairline border, no filled slab. Used
    /// where a filled clay button would read as a floating sticker on ink.
    case ghost
}

struct StoneButton: View {
    @Environment(\.ground) private var ground

    let title: String
    var systemImage: String?
    var variant: StoneButtonVariant = .stamp
    let action: () -> Void

    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
                }
                Text(title)
            }
            .font(StoneFont.bodyMedium())
            .foregroundStyle(foreground)
            .padding(.horizontal, Stoneink.sp4)
            .frame(height: 38)
            .background(background)
            .clipShape(ThrownRect.sm)
            .overlay {
                if variant == .oxide {
                    ThrownRect.sm.stroke(Stoneink.oxide600, lineWidth: 1)
                } else if variant == .stamp {
                    ThrownRect.sm.stroke(Stoneink.borderFirm, lineWidth: 1)
                } else if variant == .ghost {
                    ThrownRect.sm.stroke(hovering ? ground.onGround42 : ground.onGround16,
                                         lineWidth: 1)
                }
            }
            .offset(y: pressing ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
    }

    private var background: Color {
        switch variant {
        case .ink: return hovering ? Stoneink.cobalt500 : Stoneink.cobalt600
        case .stamp: return hovering ? Stoneink.surfaceLeaf : Stoneink.surfaceSlab
        case .bare: return hovering ? Stoneink.surfaceSlab : .clear
        case .oxide: return .clear
        // Opaque, not transparent: the shelf floats over capture mats as
        // they scroll past, and a see-through ghost with a ground-coloured
        // label disappears the moment a mat slides underneath it.
        case .ghost: return hovering ? ground.groundLift : ground.ground
        }
    }

    private var foreground: Color {
        switch variant {
        case .ink: return Stoneink.clay050
        case .stamp: return Stoneink.textPrimary
        case .bare: return Stoneink.textSecondary
        case .oxide: return Stoneink.oxide600
        case .ghost: return ground.onGround
        }
    }
}

/// A rolled coil of clay pressed onto the card — tag chip.
///
/// One ghost-pill treatment, two substrate mixes. On paper it keeps the
/// cobalt wash it has always had; on the ink ground a filled pill would
/// compete with the sidebar for the eye, so it becomes a hairline outline
/// with a paper label. Geometry is identical in every case.
struct TagCoil: View {
    @Environment(\.ground) private var ground

    let text: String
    /// True when the pill sits on a paper panel, where the substrate is the
    /// same in both modes and the ground must not be consulted.
    var onPaper: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(StoneFont.markMedium())
            .tracking(Stoneink.trMark * 11)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Stoneink.sp2)
            .frame(height: 22)
            .frame(maxWidth: 200, alignment: .leading)
            .background(fill, in: Capsule())
            .overlay {
                if let stroke { Capsule().stroke(stroke, lineWidth: 1) }
            }
    }

    private var fill: Color {
        if onPaper { return Stoneink.cobalt050 }
        return ground.isInk ? .clear : Stoneink.cobalt050
    }

    private var stroke: Color? {
        if onPaper { return nil }
        return ground.isInk ? ground.onGround16 : nil
    }

    private var textColor: Color {
        if onPaper { return Stoneink.cobalt700 }
        return ground.isInk ? ground.onGround72 : Stoneink.cobalt700
    }
}

// MARK: - Ground-aware depth
//
// The clay depth model is lit from above by a warm key: a light lip on top,
// a dark one below. On the ink ground that model inverts — light values
// there come from the paper, not from a highlight — so these two wrappers
// pick the right treatment instead of the call sites branching.

/// A well cut into whatever is underneath: the segmented track, inset
/// wells. Inner shadow on clay, a hairline lip on ink. Never an outline.
struct TrackWell<S: Shape>: ViewModifier {
    @Environment(\.ground) private var ground
    var shape: S

    func body(content: Content) -> some View {
        if ground.isInk {
            content
                .overlay { shape.stroke(Color.black.opacity(0.35), lineWidth: 1) }
                .overlay {
                    // The lip of the well catching light along its lower edge.
                    shape.stroke(ground.onGround16, lineWidth: 1)
                        .offset(y: 1)
                        .clipShape(shape)
                }
        } else {
            content.depthPress(shape)
        }
    }
}

extension TrackWell where S == Capsule {
    init() { self.init(shape: Capsule()) }
}

/// A slab seated in a well — the active segment. It is paper in both modes,
/// so it keeps its clay lip on clay; on ink it stays flat, because value
/// alone already separates paper from ink and the moment one of these grows
/// a cast shadow the ground stops reading as a slab.
struct SegmentSlab: ViewModifier {
    @Environment(\.ground) private var ground

    func body(content: Content) -> some View {
        if ground.isInk {
            content
        } else {
            content.depthSlab(Capsule())
        }
    }
}
