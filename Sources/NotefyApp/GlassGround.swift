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
    /// Window tint. 0.62 is the addendum's value; the legibility floor in
    /// §3 is what governs it, not taste — see `GlassGround.contrastFloor`.
    static let paper = Color(hex: 0xF4F0E8, opacity: 0.62)
    /// Plates are a second pane, deliberately more opaque than the window.
    static let paperPlate = Color(hex: 0xF8F5EF, opacity: 0.74)
    /// A selected plate lifts by getting MORE SOLID, never by a shadow.
    static let paperPlateSelected = Color(hex: 0xF8F5EF, opacity: 0.86)
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
/// its own background. Applied as a view so the setting can be flipped at
/// runtime rather than only at launch.
struct WindowSurfaceBridge: NSViewRepresentable {
    let glass: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in apply(view?.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in apply(view?.window) }
    }

    private func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
        window.hasShadow = true
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
            }
        }
        .ignoresSafeArea()
    }
}

/// assets/glass-sheen.svg: one soft diagonal highlight at 4%. Grain is a
/// paper property and is removed on glass — a frosted pane has no tooth.
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
        .opacity(0.04)
        .allowsHitTesting(false)
    }
}
