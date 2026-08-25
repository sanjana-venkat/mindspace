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
    static let clay000 = Color(hex: 0xF7F3EC) // slip — freshest surface
    static let clay050 = Color(hex: 0xF1ECE4) // leaf — writing surface
    static let clay100 = Color(hex: 0xE9E2D8) // slab — cards, panels
    static let clay200 = Color(hex: 0xDED5C9) // bed  — app background
    static let clay300 = Color(hex: 0xCFC4B5) // rim  — dividers
    static let clay400 = Color(hex: 0xB3A593) // hairline, strong borders
    static let clay500 = Color(hex: 0x8E8070) // icons/non-text marks ONLY
    static let clay600 = Color(hex: 0x6A5D50) // minimum for text
    static let clay700 = Color(hex: 0x4B4139)
    static let clay800 = Color(hex: 0x322B26)
    static let clay900 = Color(hex: 0x1F1A16) // fired

    // ---- 2. Ink — iron-gall, warm near-black, never pure black ----
    static let ink900 = Color(hex: 0x211B16) // body text
    static let ink700 = Color(hex: 0x3D342B) // headings on light slabs

    // ---- Cobalt — the single accent, three dilutions ----
    static let cobalt700 = Color(hex: 0x26397F)
    static let cobalt600 = Color(hex: 0x2E469B) // primary accent
    static let cobalt500 = Color(hex: 0x4459B4) // hover
    static let cobalt300 = Color(hex: 0x93A0D3) // diluted mark
    static let cobalt100 = Color(hex: 0xCBD1E8) // highlighter wash
    static let cobalt050 = Color(hex: 0xE5E8F4) // selection bloom

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
    static let surfacePress = Color(hex: 0xD6CCBE)
    static let surfaceStamp = clay800

    static let textPrimary = ink900
    static let textSecondary = clay600
    static let textMuted = clay600
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
// Newsreader (the ink — user-written content only), IBM Plex Sans
// (the stamp — app chrome), IBM Plex Mono (the kiln mark — metadata).
// If the user wrote it, it's Newsreader. If the app wrote it, it's Plex.

enum StoneFont {
    static func display() -> Font { .custom("NewsreaderRoman-72pt", size: Stoneink.tDisplay) }
    static func title() -> Font { .custom("NewsreaderRoman-72pt", size: Stoneink.tTitle) }
    static func heading() -> Font { .custom("NewsreaderRoman-72pt", size: Stoneink.tHeading) }
    static func read() -> Font { .custom("NewsreaderRoman-Regular", size: Stoneink.tRead) }
    static func readSmall() -> Font { .custom("NewsreaderRoman-Regular", size: Stoneink.tRead - 2) }
    static func readSemibold() -> Font { .custom("NewsreaderRoman-SemiBold", size: Stoneink.tSubhead) }
    static func readItalic() -> Font { .custom("NewsreaderItalic-Italic", size: Stoneink.tRead) }

    static func subhead() -> Font { .custom("IBMPlexSansRoman-SemiBold", size: Stoneink.tSubhead) }
    static func body() -> Font { .custom("IBMPlexSansRoman-Regular", size: Stoneink.tBody) }
    static func bodyMedium() -> Font { .custom("IBMPlexSansRoman-Medium", size: Stoneink.tBody) }
    static func label() -> Font { .custom("IBMPlexSansRoman-Medium", size: Stoneink.tLabel) }

    static func mark() -> Font { .custom("IBMPlexMono-Regular", size: Stoneink.tMark) }
    static func markMedium() -> Font { .custom("IBMPlexMono-Medium", size: Stoneink.tMark) }
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
}

struct StoneButton: View {
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
        }
    }

    private var foreground: Color {
        switch variant {
        case .ink: return Stoneink.clay050
        case .stamp: return Stoneink.textPrimary
        case .bare: return Stoneink.textSecondary
        case .oxide: return Stoneink.oxide600
        }
    }
}

/// A rolled coil of clay pressed onto the card — tag chip.
struct TagCoil: View {
    let text: String
    var fill: Color = Stoneink.cobalt050
    var textColor: Color = Stoneink.cobalt700

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
    }
}
