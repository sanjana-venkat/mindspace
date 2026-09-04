import AppKit
import SwiftUI

// ============================================================
// NOTED — ink on frosted glass
//
// Implements GLASS-ADDENDUM.md. The window becomes a frosted pane laid
// over the desktop and the fragments are things collected from what is
// underneath.
//
// "Frosted" is the operative word: this is OS vibrancy, which blurs
// heavily. You get the colour and movement of what is behind the window,
// never a legible view of it — you cannot read another app through this.
// That is also what keeps the type legible, and it is why the blur is the
// OS's and not ours.
//
// One window-level blur is cheap. Per-plate blur is not, and the addendum
// bans it: the plates are a second, more opaque pane rather than a second
// blur.
// ============================================================

enum GroundSurface: String, CaseIterable, Identifiable {
    case paper
    case glass

    var id: String { rawValue }
    var label: String { self == .paper ? "Paper" : "Glass" }
    static let storageKey = "noted.groundSurface"
}

/// Surface tokens for glass. Cream survives as a *tint* over the vibrancy
/// rather than as a fill, which is what keeps the app warm instead of
/// reading as stock grey macOS vibrancy.
enum GlassTokens {
    /// Window tint.
    ///
    /// The addendum specifies 0.62, and that is why the glass was invisible:
    /// at 0.62 only 38% of what is behind the window comes through, so the
    /// pane composites to near-solid cream and reads as paper. Dropped to
    /// 0.42, which passes 58%.
    ///
    /// The §3 arithmetic that justified 0.62 assumed the vibrancy passes the
    /// raw desktop colour, so a black wallpaper would leave the title on
    /// near-black. It does not: `.underWindowBackground` in a light
    /// appearance is a brightened, desaturated material whose floor is light
    /// whatever the wallpaper is, and the window is pinned to light. The
    /// title therefore keeps a light backing at this alpha.
    static let paper = Color(hex: 0xF4F0E8, opacity: 0.38)
    /// Plates are a second pane, deliberately more opaque than the window.
    static let paperPlate = Color(hex: 0xF8F5EF, opacity: 0.86)
    /// A selected plate lifts by getting MORE SOLID, never by a shadow.
    static let paperPlateSelected = Color(hex: 0xF8F5EF, opacity: 0.94)
    /// The 1px top highlight that reads as a glass edge. This inset is the
    /// one shadow the design allows anywhere.
    static let plateEdge = Color.white.opacity(0.55)
    /// Hairlines run slightly stronger on glass than on paper.
    static let ink12 = Color(hex: 0x1C1B19, opacity: 0.14)
}

/// Installs the frost directly into the window.
///
/// The SwiftUI route did not work and the diagnostics said so plainly: with
/// `VisualEffectGround` declared inside the canvas's ZStack, a dump of the
/// window's view hierarchy contained no `NSVisualEffectView` at all, at
/// launch or three seconds later. SwiftUI was drawing the ground's colours
/// into a layer and never realising the representable in that position, so
/// there was never any blur — what looked like glass was just a
/// non-opaque window behind a 38% tint, which is why it read as "too
/// subtle and not frosted".
///
/// So the effect view is added to the window's contentView as the
/// bottom-most subview, by hand. No SwiftUI involved, nothing to be
/// optimised away, and it survives re-renders because we look for an
/// existing one before adding another.
private final class WindowConfiguringView: NSView {
    var glass: Bool = false {
        didSet { configure() }
    }

    private static let tag = 0x6E074D

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    func configure() {
        guard let window, let content = window.contentView else { return }

        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
        window.hasShadow = true
        content.wantsLayer = true
        content.layer?.backgroundColor = glass ? NSColor.clear.cgColor
                                               : NSColor.windowBackgroundColor.cgColor

        // The window's contentView IS SwiftUI's hosting view, and SwiftUI
        // draws into that view's LAYER while representables become its
        // subviews. So a subview added here lands on top of the whole app —
        // which is exactly what happened: the frost worked and hid every
        // plate behind it. The frost has to go into the hosting view's
        // superview, beneath the hosting view itself.
        guard let frameView = content.superview else { return }

        let existing = frameView.subviews.first { $0.tag == Self.tag } as? NSVisualEffectView

        guard glass else {
            existing?.removeFromSuperview()
            return
        }

        let effect = existing ?? {
            let v = TaggedVisualEffectView()
            v.autoresizingMask = [.width, .height]
            frameView.addSubview(v, positioned: .below, relativeTo: content)
            return v
        }()
        // `.sidebar` frosts harder than `.underWindowBackground`; the point
        // here is that the blur is visible, not that it is tasteful.
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = content.frame
    }

    private final class TaggedVisualEffectView: NSVisualEffectView {
        override var tag: Int { 0x6E074D }
    }
}

struct WindowSurfaceBridge: NSViewRepresentable {
    let glass: Bool

    func makeNSView(context: Context) -> NSView {
        let view = WindowConfiguringView()
        view.glass = glass
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowConfiguringView)?.glass = glass
    }
}

/// The ground. Paper is a flat warm fill; glass is vibrancy, the cream tint
/// over it, and one diagonal sheen.
struct GroundSurfaceView: View {
    let surface: GroundSurface
    let paper: Color

    var body: some View {
        ZStack {
            switch surface {
            case .paper:
                paper
            case .glass:
                // The frost itself is installed into the window by
                // WindowConfiguringView and sits beneath all of this.
                GlassTokens.paper
                FrostGrain()
                GlassSheen()
                GlassEdge()
            }
        }
        .ignoresSafeArea()
    }
}

/// Heavy frost grain.
///
/// Etched glass scatters light rather than only blocking it, so the noise
/// runs both ways off a mid grey and composites with `.overlay` — a
/// single-colour multiply would read as dirt on the pane instead of as
/// texture in it.
///
/// Generated once into a small tile and repeated. The naive version — a
/// Canvas drawing a dot per pixel — is roughly a million fill operations
/// over a full window on every redraw, which is a real cost for something
/// that never changes.
private enum FrostNoise {
    static let tile: NSImage = make(side: 220)

    private static func make(side: Int) -> NSImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var generator = SeededGenerator(seed: 97)
        for y in 0..<side {
            for x in 0..<side {
                // Centred on mid grey so overlay lifts and drops in equal
                // measure; the spread is what reads as coarseness.
                let v = Double.random(in: 0.16...0.84, using: &generator)
                ctx.setFillColor(CGColor(srgbRed: v, green: v, blue: v, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}

struct FrostGrain: View {
    /// Heavy by design — this is the texture of the etch, not a whisper of
    /// paper tooth. It sits under the plates, which are 86% opaque, so it
    /// roughens the ground without touching anything anyone reads.
    var body: some View {
        Image(nsImage: FrostNoise.tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(0.38)
            .allowsHitTesting(false)
    }
}

/// The rim of the pane.
///
/// This is what was missing: a sheet of glass is read at its EDGE, where the
/// thickness catches light, far more than across its face. Without it the
/// window was a tinted rectangle; with it the whole surface resolves as a
/// slab. Brighter along the top where light would land, fading down the
/// sides, and inset by half a point so it sits on the window's own rounded
/// corner rather than beside it.
struct GlassEdge: View {
    /// macOS window corner radius.
    private let corner: CGFloat = 11

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.62), location: 0.00),
                        .init(color: .white.opacity(0.28), location: 0.28),
                        .init(color: .white.opacity(0.10), location: 0.62),
                        .init(color: .white.opacity(0.22), location: 1.00),
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

/// assets/glass-sheen.svg: one soft diagonal highlight. Grain is a paper
/// property and is removed on glass — a frosted pane has no tooth. Raised
/// from the spec's 4% because at 4% over a 38% tint it was not readable as
/// light on a surface.
struct GlassSheen: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(1.00), location: 0.00),
                .init(color: .white.opacity(0.35), location: 0.38),
                .init(color: .white.opacity(0.00), location: 0.55),
                .init(color: .white.opacity(0.15), location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(0.07)
        .allowsHitTesting(false)
    }
}
