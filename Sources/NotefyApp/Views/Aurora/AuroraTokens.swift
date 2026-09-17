import SwiftUI
import AppKit

/// Aurora's surface: a polar-light palette on translucent, grained paper.
/// Kept separate from `CanvasPalette` / `Stoneink` so the two systems can sit
/// in the same binary while the UI moves across.
/// How the app picks its appearance. `system` follows the Mac, which is what
/// carries the automatic light-to-dark switch at sunset.
enum AuroraAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "aurora.appearance"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension AuroraAppearance {
    /// What the app is set to right now, read straight from defaults — the
    /// panels the app throws up (capture review, toasts) live outside the
    /// SwiftUI environment and would otherwise follow the Mac rather than the
    /// choice made in here.
    static var current: AuroraAppearance {
        AuroraAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// nil means "follow the Mac", which is what `system` asks for.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum Aurora {
    private static func dyn(_ light: (Int, Int, Int), _ dark: (Int, Int, Int)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: Double(c.0)/255, green: Double(c.1)/255, blue: Double(c.2)/255, alpha: 1)
        })
    }

    static let ground    = dyn((233, 234, 231), (11, 14, 12))
    static let surface   = dyn((255, 255, 255), (20, 26, 23))
    static let surface2  = dyn((238, 240, 236), (26, 33, 29))
    static let ink       = dyn((16, 20, 16), (255, 255, 255))
    // Dark mode needs far more contrast than a straight inversion gives:
    // these two carry most of the running text and were unreadable at the
    // light-mode weights.
    static let ink2      = dyn((89, 99, 90), (201, 207, 216))
    static let ink3      = dyn((139, 148, 139), (139, 146, 156))
    static let line      = dyn((214, 219, 211), (42, 47, 55))
    static let accent    = dyn((14, 109, 85), (52, 211, 153))
    static let accentSoft = dyn((220, 239, 231), (17, 41, 31))

    /// Primary buttons and selected chips: near-black on paper, white on the
    /// night. The folders already carry the colour, so the primary stays
    /// neutral rather than adding another hue to compete with them.
    static let solid     = dyn((16, 20, 16), (255, 255, 255))
    static let onSolid   = dyn((233, 234, 231), (14, 16, 19))

    /// What marks the thing you have selected or are hovering. Neutral for the
    /// same reason as `solid`.
    static let focusRing = dyn((16, 20, 16), (255, 255, 255))

    /// Five desaturated polar-light hues. Folders and captures pick one by id,
    /// so the same folder is the same colour every launch.
    static let tints: [Color] = [
        // On near-black, a dark tint reads as grime rather than colour — these
        // are pitched to carry at the small sizes they actually appear in, as
        // tabs behind a folder and swatches in the feed.
        // The light side used to be pastel to the point of disappearing on
        // white — these carry at card size without shouting.
        dyn((118, 175, 146), (52, 176, 124)),   // green
        dyn((176, 150, 196), (146, 112, 224)),  // violet
        dyn((222, 197, 140), (208, 158, 74)),   // amber
        dyn((114, 152, 186), (72, 138, 220)),   // blue
        dyn((126, 196, 190), (56, 176, 186))    // teal
    ]

    /// Amber: something is out of date, not wrong.
    static let warning = dyn((176, 118, 24), (235, 179, 76))

    /// The one red in the system: destructive actions only, so it never reads
    /// as decoration.
    static let danger = dyn((176, 48, 52), (226, 84, 84))

    /// The deep end of the palette — used where the wash needs to land, not tint.
    static let deep = dyn((37, 51, 64), (18, 26, 32))

    static func tint(_ i: Int) -> Color { tints[((i % tints.count) + tints.count) % tints.count] }

    /// Mixes two colours, alpha included. Used where the interface crosses
    /// from its night palette to its daylight one part-way through a journey.
    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = max(0, min(1, t))
        guard let from = NSColor(a).usingColorSpace(.sRGB),
              let to = NSColor(b).usingColorSpace(.sRGB) else { return a }
        return Color(nsColor: NSColor(
            srgbRed: from.redComponent + (to.redComponent - from.redComponent) * t,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * t,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * t,
            alpha: from.alphaComponent + (to.alphaComponent - from.alphaComponent) * t))
    }

    /// FNV-1a. `hashValue` is seeded per process, so using it here meant a
    /// folder changed colour on every launch.
    static func stableHash(_ text: String) -> Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return Int(h % 1_000_003)
    }

    /// A stable tint index for any identifier.
    static func tintIndex(for id: UUID) -> Int { stableHash(id.uuidString) % tints.count }
    static func tintIndex(for text: String) -> Int { stableHash(text) % tints.count }

    /// Three hues that are always distinct, seeded off one identifier.
    static func triad(seed: String) -> [Int] {
        let base = stableHash(seed) % tints.count
        return [base, (base + 2) % tints.count, (base + 4) % tints.count]
    }

    // Type roles, on the three families the app already bundles: Boldonse for
    // anything that announces itself, Hanken Grotesk for the interface, Geist
    // Mono for labels and data. Boldonse runs large for its point size, so
    // display sizes are scaled down to sit where the old system face did.
    static func display(_ size: CGFloat) -> Font { .custom("Boldonse-Regular", size: size * 0.78) }
    static func title(_ size: CGFloat) -> Font { .custom("HankenGrotesk-Regular", size: size).weight(.bold) }
    static func ui(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
        .custom("HankenGrotesk-Regular", size: size).weight(w)
    }
    static func serif(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w, design: .serif) }
    static func mono(_ size: CGFloat) -> Font { .custom("GeistMono-Regular", size: size) }
}

/// A tileable film-grain texture, generated once.
enum AuroraGrain {
    static let tile: Image = {
        let side = 220
        let bpp = 4
        var pixels = [UInt8](repeating: 0, count: side * side * bpp)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10_000) / 10_000.0
        }
        for i in 0..<(side * side) {
            let v = rand() * 0.72 + ((rand() + rand()) * 0.5) * 0.28
            let luma = UInt8(max(0, min(255, v * 255)))
            let o = i * bpp
            pixels[o] = luma; pixels[o+1] = luma; pixels[o+2] = luma
            pixels[o+3] = UInt8(90 + rand() * 90)
        }
        let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: side * bpp, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return Image(decorative: ctx.makeImage()!, scale: 2.0)
    }()
}

/// Window-backdrop blur, so the app sits on whatever is behind it.
struct AuroraVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Makes the host window non-opaque so the backdrop blur has something to blur.
struct AuroraWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.backgroundColor = .clear
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The painted part of the ground — the colour and the tooth, without the
/// window blur behind it. Split out so the theme change can render both modes
/// at once and dissolve between them; `AuroraGround` is this over the blur.
struct AuroraSurfaceFill: View {
    let light: Bool
    /// The ground is normally translucent, so the desktop shows faintly
    /// through. A transition covers the window instead, and needs the dark
    /// side solid or the old mode reads through the new one.
    var opaque: Bool = false

    /// Dark mode over the window blur, written out: this is used from outside
    /// the themed part of the app, where the dynamic tokens would resolve to
    /// whichever mode happens to be current.
    static let night = Color(red: 0.043, green: 0.055, blue: 0.047)

    var body: some View {
        ZStack {
            if light {
                // Light is snow: white, with only enough cool in it to keep
                // it from reading as flat paper. It carried a green wash at
                // the top for a while, which tinted the whole interface teal.
                LinearGradient(stops: [
                    .init(color: Color(red: 0.961, green: 0.969, blue: 0.976), location: 0),
                    .init(color: Color(red: 0.976, green: 0.980, blue: 0.984), location: 0.5),
                    .init(color: Color(red: 0.992, green: 0.992, blue: 0.992), location: 1),
                ], startPoint: .top, endPoint: .bottom)

                // The drifts, felt rather than seen.
                LinearGradient(colors: [.clear, .white.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .blur(radius: 40)
                    .opacity(0.5)

            } else if opaque {
                Self.night
            } else {
                Color(red: 11/255, green: 14/255, blue: 12/255).opacity(0.26)
            }

            AuroraGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(light ? .multiply : .screen)
                // Dark carries the same amount of tooth as light — on a
                // near-black ground the grain has to be screened back in at
                // full strength or the surface reads as flat glass.
                .opacity(0.20)
        }
    }
}

/// One translucent, grained ground for every Aurora screen — no seams between
/// panels, and the desktop shows faintly through.
struct AuroraGround: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AuroraVisualEffect()
            AuroraSurfaceFill(light: scheme != .dark)
        }
        .ignoresSafeArea()
    }
}

/// A small control that answers the moment it is pressed: the glyph dips and
/// dims under the cursor rather than waiting for the click to complete, which
/// is the difference between a button that feels slow and one that doesn't.
struct AuroraTapDown: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hover ? Aurora.ink.opacity(0.07) : .clear, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Carries what was searched for into the note that was opened from a result,
/// so the words that matched can be marked where they actually live.
private struct AuroraSearchMarkKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var auroraSearchMark: String? {
        get { self[AuroraSearchMarkKey.self] }
        set { self[AuroraSearchMarkKey.self] = newValue }
    }
}

extension Aurora {
    /// The same text, with every occurrence of `query` lit up. Returns plain
    /// text when there is nothing to mark, so callers can use it everywhere.
    static func marked(_ text: String, query: String?) -> AttributedString {
        var attributed = AttributedString(text)
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return attributed }

        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let haystack = text.lowercased()
        var cursor = haystack.startIndex
        while let found = haystack.range(of: needle, range: cursor..<haystack.endIndex) {
            // The attributed string mirrors the original, so the same offsets
            // hold in both.
            let start = haystack.distance(from: haystack.startIndex, to: found.lowerBound)
            let length = haystack.distance(from: found.lowerBound, to: found.upperBound)
            if let from = attributed.index(attributed.startIndex, offsetByCharacters: start) as AttributedString.Index?,
               let to = attributed.index(from, offsetByCharacters: length) as AttributedString.Index? {
                attributed[from..<to].backgroundColor = Aurora.accent.opacity(0.28)
                attributed[from..<to].foregroundColor = Aurora.ink
            }
            cursor = found.upperBound
        }
        return attributed
    }
}

struct AuroraHoverRow: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hover ? Aurora.surface2 : .clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .onHover { hover = $0 }
    }
}
