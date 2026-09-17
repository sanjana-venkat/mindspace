import SwiftUI

/// The first few seconds of the app, in three beats.
///
/// One: the aurora, alone, for long enough to be looked at.
/// Two: the light gathers into a shape — the mark's five strokes trace
/// themselves out of the curtains, carrying their colour, until the navy plate
/// arrives underneath and they settle into the logo.
/// Three: the logo steps to the right and uncovers the name.
///
/// Then the whole thing lets go: the sky eases up a little, the launch fades,
/// and setup rises into it. A nudge, not a page turn.
struct AuroraLaunch: View {
    var onFinish: () -> Void
    /// Fired as the launch begins to fade, so whatever is hosting it can start
    /// moving at the same time.
    var onLeave: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sky = false
    /// Per-stroke draw progress, so the mark traces one line at a time.
    @State private var drawn: [Double] = Array(repeating: 0, count: MindspaceMark.strokes.count)
    @State private var plate = false
    @State private var gathered = false
    @State private var split = false
    @State private var reveal: CGFloat = 0
    @State private var eyebrow = false
    @State private var leaving = false

    private let markSize: CGFloat = 104
    private let wordWidth: CGFloat = 286
    private let gap: CGFloat = 24

    /// How far the mark travels right to sit at the end of the lockup.
    private var markTravel: CGFloat { (wordWidth + gap) / 2 }
    /// Where the word sits once the mark has moved off it.
    private var wordTravel: CGFloat { -(markSize + gap) / 2 }

    var body: some View {
        ZStack {
            // The light the strokes are traced out of: wide at first, drawn in
            // around the mark as it forms, gone by the time we leave.
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 0.36, green: 0.92, blue: 0.68).opacity(0.32), .clear],
                                     center: .center, startRadius: 2, endRadius: 280))
                .frame(width: gathered ? 400 : 940, height: gathered ? 290 : 540)
                .blur(radius: 46)
                .opacity(sky ? (leaving ? 0 : 1) : 0)
                .offset(x: split ? markTravel * 0.55 : 0)

            lockup
                .opacity(leaving ? 0 : 1)
                .scaleEffect(leaving ? 0.97 : 1)
        }
        .onAppear(perform: run)
    }

    private var lockup: some View {
        ZStack {
            // The name is uncovered rather than faded in: the mask's edge rides
            // along just behind the mark as it slides away.
            VStack(alignment: .leading, spacing: 10) {
                Text("Mindspace")
                    .font(Aurora.display(46))
                    .foregroundStyle(.white)
                    .fixedSize()
                Text("OPENHUMAN")
                    .font(Aurora.mono(9.5)).tracking(3)
                    .foregroundStyle(.white.opacity(0.45))
                    .opacity(eyebrow ? 1 : 0)
                    .offset(y: eyebrow ? 0 : 6)
            }
            .frame(width: wordWidth, alignment: .leading)
            .mask(alignment: .leading) { Rectangle().frame(width: reveal) }
            .offset(x: split ? wordTravel : 0)

            MindspaceMarkView(draw: drawn, plate: plate ? 1 : 0, glow: plate ? 0.25 : 1)
                .frame(width: markSize, height: markSize)
                .offset(x: split ? markTravel : 0)
                .scaleEffect(plate ? 1 : 1.05)
        }
        .frame(width: wordWidth + gap + markSize)
    }

    private func run() {
        guard !reduceMotion else {
            sky = true
            drawn = Array(repeating: 1, count: MindspaceMark.strokes.count)
            plate = true; split = true; eyebrow = true; reveal = wordWidth
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onFinish() }
            return
        }

        // Beat one — the aurora, on its own. The sky itself is the host's;
        // this only brings up the pool of light the mark forms in.
        withAnimation(.easeOut(duration: 1.1)) { sky = true }

        // Beat two — the strokes trace out of it, then the plate lands.
        for i in MindspaceMark.strokes.indices {
            let delay = 0.95 + Double(i) * 0.16
            withAnimation(.easeInOut(duration: 0.7).delay(delay)) { drawn[i] = 1 }
        }
        withAnimation(.easeInOut(duration: 1.1).delay(1.0)) { gathered = true }
        withAnimation(.easeOut(duration: 0.55).delay(2.15)) { plate = true }

        // Beat three — the mark steps aside and the name is wiped open.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.84).delay(2.6)) { split = true }
        withAnimation(.easeOut(duration: 0.55).delay(2.72)) { reveal = wordWidth }
        withAnimation(.easeOut(duration: 0.5).delay(3.15)) { eyebrow = true }

        // And out: the camera starts down the sky, and the launch dissolves
        // into the move rather than being swept off by it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.85) {
            onLeave()
            withAnimation(.easeInOut(duration: 0.7)) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onFinish() }
        }
    }
}
