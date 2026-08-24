import SwiftUI

/// Design tokens — read directly off Figma file `5ZSw0dNrfHERxpNMdpzK90`,
/// node `57:617` ("glassmorphism-notes-app"). See the design brief: the canvas
/// and surface are only ~3% apart in value — all depth comes from the blob
/// field behind the glass and from two *directional* shadow pairs (emboss /
/// deboss). Never substitute a generic symmetrical shadow for either.
enum NotefyTheme {
    // ---- Canvas & solid surfaces ----
    static let sand = Color(hex: 0xFDFBF7)       // canvas
    static let sandDeep = Color(hex: 0xF5F1E9)   // surface (neumorphic ground)
    static let cardPaper = Color(hex: 0xFAF8F4)  // surface-raised (active toggle pill)

    // ---- Ink ----
    static let ink = Color(hex: 0x2B2824)        // primary
    static let inkStrong = Color(hex: 0x282522)  // active control label
    static let inkMid = Color(hex: 0x4E4943)     // progress fill
    static let inkSoft = Color(hex: 0x6E6861)    // secondary body (contrast floor)
    static let inkMuted = Color(hex: 0x615E58)   // inactive control label
    static let inkFaint = Color(hex: 0x9B958F)   // section labels, meta (large-text only)
    static let inkDeep = Color(hex: 0x1D1A16)
    static let marginRose = Color(hex: 0xC79A90)

    static let textPrimary = ink
    static let textSecondary = inkSoft

    // ---- Glass ----
    // Fill + hairline + backdrop blur are a set; never use one without the others.
    static let glassFill = Color.white.opacity(0.30)
    static let glassFillStrong = Color.white.opacity(0.40)
    static let glassFillSubtle = Color.white.opacity(0.33)
    static let glassFillTag = Color.white.opacity(0.70)
    static let glassTint = Color(hex: 0xD8D8D8, opacity: 0.30) // large preview card
    static let glassBorder = Color.white.opacity(0.80)
    static let glassBorderSoft = Color.white.opacity(0.65)
    static let glassTintFaint = glassFill
    static let glassTintLight = Color.white.opacity(0.6)

    // Legacy aliases kept for call sites not yet migrated.
    static let pebbleTan = Color(hex: 0xE8EDF1)
    static let pebbleOlive = Color(hex: 0xDDE5E9)
    static let pebbleMauve = Color(hex: 0xE2E7EC)
    static let pebbleStone = Color(hex: 0xD9E0E5)
    static let gold = pebbleTan
    static let goldSoft = pebbleTan.opacity(0.7)
    static let paper = sand
    static let paperDim = sandDeep
    static let well = Color(hex: 0x1F1E1A)
    static let pillDark = inkMid
    static let pillDarkText = Color(hex: 0xF9F8F6)
    static let shadowWarm = Color(hex: 0x322E2A)

    // ---- Ambient blob field ----
    // Three large ellipses under everything. This is what makes the glass
    // mean anything — without them the panels read as flat grey.
    static let blobPeriwinkle = Color(hex: 0xDFE5FF, opacity: 0.55)
    static let blobAmber = Color(hex: 0xF59E0B, opacity: 0.13)
    static let blobRose = Color(hex: 0xEE9CA7, opacity: 0.18)

    // ---- Panel shadow (glass drop shadow) ----
    static let panelShadowColor = Color(hex: 0x322E2A, opacity: 0.11)

    static func surface(_ scheme: ColorScheme) -> Color { sand }
    static func card(_ scheme: ColorScheme) -> Color { cardPaper }
}

// MARK: - Elevation grammar
//
// Emboss = it acts (buttons, the active toggle pill, the avatar — things you
// press). Deboss = it holds or receives (selected nav item, empty wells, note
// rows at rest, the storage meter track). Never mix both on one element; a
// note row is never embossed — it is content, not a control.

extension View {
    /// Emboss: two-shadow directional pair, light up-left / dark down-right at 135deg.
    /// Use for things the user presses: buttons, the active toggle pill, the avatar.
    func emboss(hovering: Bool = false) -> some View {
        self
            .shadow(color: .white.opacity(hovering ? 0.55 : 0.50), radius: hovering ? 3 : 2, x: 4, y: 3)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0.20), radius: hovering ? 4 : 2, x: 0, y: hovering ? 2 : 1)
    }

    /// Deboss: the inverse pair, pressed in rather than raised. Use for content
    /// that holds or receives: selected nav rows, empty wells, hero card interiors.
    /// `cornerRadius` must match the shape already clipping this view.
    func deboss(cornerRadius: CGFloat, soft: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self.overlay {
            ZStack {
                shape
                    .stroke(Color.white.opacity(soft ? 0.80 : 0.93), lineWidth: soft ? 7 : 10)
                    .blur(radius: soft ? 5 : 6)
                    .offset(x: soft ? -4 : -5, y: soft ? -4 : -5)
                shape
                    .stroke(Color(hex: 0x1F1A12, opacity: soft ? 0.07 : 0.10), lineWidth: soft ? 7 : 10)
                    .blur(radius: soft ? 5 : 6)
                    .offset(x: soft ? 4 : 5, y: soft ? 4 : 5)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }

    /// Deboss-soft convenience: note rows at rest, the storage meter track, the search field.
    func debossSoft(cornerRadius: CGFloat) -> some View {
        deboss(cornerRadius: cornerRadius, soft: true)
    }
}

/// Frosted-glass panel: translucent material + white tint + hairline border + soft warm
/// shadow. Fill + hairline + blur always travel together — never use one without the others.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color = NotefyTheme.glassFill
    var borderWidth: CGFloat = 1
    var shadowRadius: CGFloat = 12
    var shadowY: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NotefyTheme.glassBorder, lineWidth: borderWidth)
            )
            .shadow(color: NotefyTheme.panelShadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 20, tint: Color = NotefyTheme.glassFill, borderWidth: CGFloat = 1, shadowRadius: CGFloat = 12, shadowY: CGFloat = 6) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, borderWidth: borderWidth, shadowRadius: shadowRadius, shadowY: shadowY))
    }

    /// Legacy name kept for call sites not yet migrated — identical to `.deboss`.
    func neomorphicDeboss(cornerRadius: CGFloat = 12) -> some View {
        deboss(cornerRadius: cornerRadius)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Exactly three typefaces, per the design brief: Instrument Serif (display —
/// note titles only), Geist (UI — buttons, nav, labels, source text), Geist
/// Mono (meta — uppercase labels, timestamps — and body, captured note text).
/// Plus one conditional fourth: Caveat, for the user's own annotations only.
/// Never use it for placeholder copy or machine-captured content.
enum NotefyFont {
    static let pageTitle = Font.custom("InstrumentSerif-Regular", size: 44)
    static let sectionTitle = Font.custom("InstrumentSerif-Regular", size: 26)

    static let wordmark = Font.custom("Geist-Bold", size: 15)
    static let title = Font.custom("Geist-SemiBold", size: 20)
    static let heading = Font.custom("Geist-SemiBold", size: 14)
    static let body = Font.custom("Geist-Regular", size: 15)
    static let bodyMedium = Font.custom("Geist-Medium", size: 14)

    // Geist Mono — uppercase tracked labels, timestamps, tags, and captured body copy.
    static let caption = Font.custom("GeistMono-Regular", size: 11)
    static let label = Font.custom("GeistMono-SemiBold", size: 10)
    static let mono = Font.custom("GeistMono-Regular", size: 11)
    static let capturedBody = Font.custom("GeistMono-Regular", size: 15)

    /// User annotations only — never placeholder text, never captured content.
    static let hand = Font.custom("Caveat-Regular", size: 20)
}

struct PebbleShape: Shape {
    var variant: Int = 0
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.04)
        var path = Path()
        if variant.isMultiple(of: 2) {
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.12, y: inset.midY))
            path.addCurve(to: CGPoint(x: inset.midX, y: inset.minY), control1: CGPoint(x: inset.minX, y: inset.height * 0.18), control2: CGPoint(x: inset.width * 0.27, y: inset.minY))
            path.addCurve(to: CGPoint(x: inset.maxX, y: inset.midY), control1: CGPoint(x: inset.width * 0.78, y: inset.minY), control2: CGPoint(x: inset.maxX, y: inset.height * 0.2))
            path.addCurve(to: CGPoint(x: inset.midX, y: inset.maxY), control1: CGPoint(x: inset.maxX, y: inset.height * 0.82), control2: CGPoint(x: inset.width * 0.72, y: inset.maxY))
            path.addCurve(to: CGPoint(x: inset.minX + inset.width * 0.12, y: inset.midY), control1: CGPoint(x: inset.width * 0.22, y: inset.maxY), control2: CGPoint(x: inset.minX, y: inset.height * 0.76))
        } else {
            path.addRoundedRect(in: inset, cornerSize: CGSize(width: inset.width * 0.42, height: inset.height * 0.48))
        }
        return path
    }
}

struct OrigamiCrane: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 34
            let sy = size.height / 30
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            var body = Path()
            body.move(to: point(4, 24)); body.addLine(to: point(15, 10))
            body.addLine(to: point(20, 16)); body.addLine(to: point(28, 6))
            body.addLine(to: point(30, 14)); body.addLine(to: point(22, 22))
            body.addLine(to: point(14, 26)); body.closeSubpath()
            context.fill(body, with: .color(NotefyTheme.cardPaper))
            context.stroke(body, with: .color(NotefyTheme.ink), lineWidth: 1.4)
            var fold = Path(); fold.move(to: point(15, 10)); fold.addLine(to: point(20, 16)); fold.addLine(to: point(14, 26))
            context.stroke(fold, with: .color(NotefyTheme.ink), lineWidth: 1)
            var beak = Path(); beak.move(to: point(28, 6)); beak.addLine(to: point(26, 3))
            context.stroke(beak, with: .color(NotefyTheme.marginRose), lineWidth: 1.6)
            context.fill(Path(ellipseIn: CGRect(x: 26.5 * sx, y: 6.5 * sy, width: 1.8 * sx, height: 1.8 * sy)), with: .color(NotefyTheme.ink))
        }
        .aspectRatio(34 / 30, contentMode: .fit)
    }
}

/// The supplied Noted mark. Keep the vector fallback for first-run previews or
/// developer builds where the bundled image has not been copied yet.
struct NotedLogo: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "NotedLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            OrigamiCrane()
        }
    }
}

struct NotefyBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(NotefyFont.label)
            .tracking(1.1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(NotefyTheme.inkSoft)
    }
}

/// A pill button in the system's own vocabulary: it presses (emboss), it never
/// fills with an out-of-system dark colour. The primary action is distinguished
/// by ink weight, not by a colour the palette doesn't have.
struct NotefyPillButton: View {
    let title: String
    let systemImage: String
    var tint: Color = NotefyTheme.ink
    var filled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(filled ? NotefyFont.label.weight(.bold) : NotefyFont.label)
                .tracking(1)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(NotefyTheme.cardPaper, in: Capsule())
        .foregroundStyle(filled ? NotefyTheme.inkStrong : NotefyTheme.inkMuted)
        .emboss()
    }
}

struct DualAudioSourceMeters: View {
    let microphoneDB: Float
    let systemDB: Float
    let microphoneActive: Bool
    let systemActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            source("YOU", value: microphoneDB, active: microphoneActive, color: NotefyTheme.marginRose)
            source("OTHERS", value: systemDB, active: systemActive, color: NotefyTheme.pebbleOlive)
        }
    }

    private func source(_ label: String, value: Float, active: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(active ? color : NotefyTheme.inkFaint).frame(width: 6, height: 6)
                Text(label).font(NotefyFont.caption).tracking(0.8).foregroundStyle(NotefyTheme.inkSoft)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotefyTheme.ink.opacity(0.09))
                    Capsule().fill(active ? color : NotefyTheme.inkFaint)
                        .frame(width: proxy.size.width * normalized(value))
                }
            }
            .frame(width: 72, height: 4)
        }
    }

    private func normalized(_ decibels: Float) -> CGFloat {
        CGFloat(max(0, min(1, (decibels + 60) / 60)))
    }
}
