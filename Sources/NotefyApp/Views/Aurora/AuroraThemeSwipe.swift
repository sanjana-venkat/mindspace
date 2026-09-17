import SwiftUI

/// Switching between light and dark is the surface turning over, not a panel
/// sliding across.
///
/// The app's ground already has a tooth to it — the film grain that sits on
/// every screen. That grain is what performs the change: it boils up, and the
/// new mode comes through it speck by speck, the way a print develops. Light
/// rises from the bottom; dark falls from the top. No landscape, no aurora —
/// the app is not travelling anywhere, it is changing its mind about the light.
///
/// Hosted once, at the top of the workspace. It is idle — and costs nothing —
/// until someone presses the toggle.
struct AuroraThemeSwipe: View {
    @Binding var run: AuroraThemeSwipe.Move?

    struct Move: Equatable {
        let toLight: Bool
        /// Bumped per press, so two flips in a row still animate.
        let id: Int
    }

    @State private var progress: Double = 0
    @State private var shown = false

    var body: some View {
        ZStack {
            if let run {
                ThemeDissolve(progress: progress, toLight: run.toLight)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(false)
                    .task(id: run) { await play(run) }
            }
        }
        .ignoresSafeArea()
    }

    private func play(_ move: Move) async {
        progress = 0
        // The cover goes up with no fade: what it shows first is the mode you
        // are already looking at, so there is nothing to hide.
        shown = true
        try? await Task.sleep(for: .milliseconds(20))
        withAnimation(.easeInOut(duration: 0.62)) { progress = 1 }
        try? await Task.sleep(for: .milliseconds(640))
        // By now the app underneath has already changed mode, so lifting the
        // cover reveals the same surface it is showing.
        withAnimation(.easeOut(duration: 0.22)) { shown = false }
        try? await Task.sleep(for: .milliseconds(220))
        run = nil
    }
}

// MARK: - the change itself

/// Both grounds at once, with the arriving one masked by boiling grain.
/// `Animatable` so the mask is rebuilt every frame: the dissolve lives in the
/// mask's geometry, which SwiftUI cannot interpolate on its own.
private struct ThemeDissolve: View, Animatable {
    var progress: Double
    var toLight: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = max(0, min(1, progress))
        ZStack {
            // What you are leaving, whole underneath.
            AuroraSurfaceFill(light: !toLight, opaque: true)

            // What you are arriving at, coming through the grain.
            AuroraSurfaceFill(light: toLight, opaque: true)
                .mask { GrainMask(progress: p, upward: toLight) }

            // The tooth itself, agitated while the change happens and settling
            // back to its resting weight at either end.
            AuroraGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(0.34 * sin(Double.pi * p))
        }
        .compositingGroup()
    }
}

/// A dissolve edge made of grain: a soft band sweeps the window, and the film
/// grain roughens it so the boundary breaks into specks instead of a line.
///
/// The band alone guarantees the reveal completes; the grain only decides the
/// order pixels turn over inside it.
private struct GrainMask: View {
    let progress: Double
    /// True sweeps bottom to top, false top to bottom.
    let upward: Bool

    var body: some View {
        // The band starts fully off one edge and ends fully off the other.
        let edge = progress * 1.36 - 0.18
        let lead = max(0, min(1, edge - 0.18))
        let trail = max(0, min(1, edge + 0.18))

        ZStack {
            Color.black

            AuroraGrain.tile
                .resizable(resizingMode: .tile)
                .opacity(0.55)
                .blendMode(.plusLighter)

            LinearGradient(stops: [
                .init(color: .white, location: lead),
                .init(color: .black, location: trail),
            ], startPoint: upward ? .bottom : .top, endPoint: upward ? .top : .bottom)
            .blendMode(.plusLighter)
        }
        .compositingGroup()
        // Pushes the soft band into a crunchy threshold: the grain decides
        // which side of it each speck falls on.
        .contrast(6)
        .luminanceToAlpha()
    }
}
