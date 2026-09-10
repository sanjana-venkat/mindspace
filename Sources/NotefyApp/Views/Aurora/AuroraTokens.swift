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
        // Folders keep their hue in the dark, deep enough to sit on near-black
        // without glowing.
        dyn((157, 188, 171), (39, 92, 70)),    // sage
        dyn((205, 187, 209), (72, 60, 110)),   // mauve
        dyn((233, 226, 211), (94, 76, 48)),    // sand
        dyn((147, 170, 188), (38, 72, 108)),   // slate
        dyn((180, 213, 189), (28, 88, 94))     // teal
    ]

    /// The deep end of the palette — used where the wash needs to land, not tint.
    static let deep = dyn((37, 51, 64), (18, 26, 32))

    static func tint(_ i: Int) -> Color { tints[((i % tints.count) + tints.count) % tints.count] }

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

/// One translucent, grained ground for every Aurora screen — no seams between
/// panels, and the desktop shows faintly through.
struct AuroraGround: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            AuroraVisualEffect()
            Aurora.ground.opacity(scheme == .dark ? 0.26 : 0.12)
            AuroraGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(scheme == .dark ? .screen : .multiply)
                .opacity(scheme == .dark ? 0.11 : 0.20)
        }
        .ignoresSafeArea()
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
