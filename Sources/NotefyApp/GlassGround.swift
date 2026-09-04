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

/// `NSVisualEffectView` blending with what is behind the WINDOW. `.withinWindow`
/// would only frost the app's own background and look like a flat fill.
struct VisualEffectGround: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        // Keeps the pane frosted when Noted is not frontmost. Without it the
        // window goes grey and flat the moment you click away, which is the
        // opposite of a pane of glass.
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}

/// A window cannot show anything behind it while it is opaque and painting
/// its own background.
///
/// The first version of this poked the window from `DispatchQueue.main.async`
/// inside `makeNSView`, which is a race: at that moment the view usually has
/// no window yet, and SwiftUI does not reliably call `updateNSView` again
/// afterwards, so the poke silently did nothing. `viewDidMoveToWindow` fires
/// exactly when the window becomes available, which is the whole point of it.
///
/// SwiftUI also resets the background when the scene re-renders, so the
/// configuration is reapplied on every update rather than assumed to stick.
private final class WindowConfiguringView: NSView {
    var glass: Bool = false {
        didSet { configure() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    func configure() {
        guard let window else { return }
        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
        window.hasShadow = true
        // The content view's own backing layer will happily paint an opaque
        // colour over the vibrancy if it has one.
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = glass
            ? NSColor.clear.cgColor
            : NSColor.windowBackgroundColor.cgColor
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
                VisualEffectGround()
                GlassTokens.paper
                GlassSheen()
                GlassEdge()
            }
        }
        .ignoresSafeArea()
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
