import SwiftUI

/// The library as a mind rather than a filing cabinet.
///
/// Every folder is an arc around the moon, and the length of the arc is that
/// folder's share of everything you have saved. A grid of equal tiles says all
/// your folders are the same size, which is never true. The ring says, at a
/// glance, where your attention has actually gone.
struct AuroraOrbitView: View {
    let tiles: [AuroraFolderTile]
    @ObservedObject var transcript: LiveTranscriptEngine
    var levelDB: () -> Float = { -160 }
    var onOpenFolder: (AuroraFolderTile) -> Void
    var onListen: () -> Void
    var onStopListening: () -> Void
    /// Owned by AppState, so the ring can only claim to be listening when the
    /// microphone actually opened.
    let listening: Bool
    var onAsk: (String) -> Void

    @State private var hovered: String?
    @State private var moonDown = false
    /// Bumped on every hover change, so a delayed clear only lands if nothing
    /// has been hovered since.
    @State private var hoverToken = 0

    private let ringRadius: CGFloat = 116
    private let thickness: CGFloat = 9
    private let gapDegrees: Double = 2.4

    /// Empty folders still deserve a sliver. A folder you made and have not
    /// filled is a thought you have not come back to, not an absence.
    private var weights: [Double] {
        tiles.map { Double(max(1, $0.captureCount)) }
    }

    private var total: Double { max(1, weights.reduce(0, +)) }

    private struct Segment: Identifiable {
        let id: String
        let tile: AuroraFolderTile
        let start: Double
        let end: Double
        let tint: Color
    }

    /// The ring never closes. A full circle reads as a meter at maximum, and
    /// with a single folder it would say nothing at all, so the arcs share
    /// three quarters of the circle and the open wedge sits at the top.
    private let span: Double = 276

    private var segments: [Segment] {
        var out: [Segment] = []
        var angle = -90 + (360 - span) / 2
        for (i, tile) in tiles.enumerated() {
            let sweep = (weights[i] / total) * span
            // Below about four degrees an arc with round caps reads as a dot,
            // so give the slivers a floor and let the big folders pay for it.
            let drawn = max(4.0, sweep - gapDegrees)
            out.append(Segment(id: tile.id, tile: tile,
                               start: angle, end: angle + drawn,
                               tint: Aurora.tint(tile.tints.first ?? 0)))
            angle += sweep
        }
        return out
    }

    /// Leaving an arc lets go after a beat rather than at once, so the label
    /// is still there when the pointer crosses the gap to click it.
    private func setHover(_ id: String, _ inside: Bool) {
        hoverToken += 1
        if inside {
            hovered = id
            return
        }
        let token = hoverToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if hoverToken == token, hovered == id { hovered = nil }
        }
    }

    private var hoveredSegment: Segment? {
        guard let hovered else { return nil }
        return segments.first { $0.id == hovered }
    }

    /// Questions built from folders that actually exist, so the suggestions are
    /// never a promise the library cannot keep.
    private var suggestions: [String] {
        tiles.filter { !$0.isUnfiled && $0.captureCount > 0 }
            .sorted { $0.captureCount > $1.captureCount }
            .prefix(3)
            .map { "What did I save about \($0.name)?" }
    }

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 - 40)

            ZStack {
                if listening {
                    earRing(centre: centre)
                } else {
                    orbit(centre: centre)
                }
                moon(centre: centre)

                if let seg = hoveredSegment, !listening {
                    chip(for: seg, centre: centre)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if listening {
                    heard(centre: centre, width: geo.size.width)
                } else {
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.84), value: hovered)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: listening)
        }
    }

    // MARK: the ring

    private func orbit(centre: CGPoint) -> some View {
        ZStack {
            // A faint complete circle underneath, so the ring still reads as a
            // ring when one folder holds nearly everything.
            Circle()
                .stroke(Aurora.line.opacity(0.5), lineWidth: 1)
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .position(centre)

            ForEach(segments) { seg in
                let lit = hovered == seg.id
                OrbitArc(start: seg.start, end: seg.end, radius: ringRadius)
                    .stroke(seg.tint.opacity(lit ? 1 : 0.85),
                            style: StrokeStyle(lineWidth: lit ? thickness + 5 : thickness,
                                               lineCap: .round))
                    .shadow(color: lit ? seg.tint.opacity(0.7) : .clear, radius: 14)
                    .frame(width: ringRadius * 2 + thickness * 3,
                           height: ringRadius * 2 + thickness * 3)
                    // The stroke is the picture; this wedge is what the pointer
                    // actually hits, and it is deliberately fatter than the line
                    // so a 13pt arc is not a 13pt target.
                    //
                    // The shape has to be set while the view is still the
                    // ring's own square. Applied after `.position`, the view is
                    // the whole window, the wedge centres on the window rather
                    // than the moon, and the target sits 40pt below the arc
                    // you can see, which is why clicking the arc did nothing.
                    .contentShape(OrbitWedge(start: seg.start, end: seg.end,
                                             radius: ringRadius, thickness: thickness + 22))
                    .onHover { setHover(seg.id, $0) }
                    .onTapGesture { onOpenFolder(seg.tile) }
                    .help("Open \(seg.tile.name)")
                    .position(centre)
            }
        }
    }

    // MARK: the moon

    private func moon(centre: CGPoint) -> some View {
        let art = MoonPetArt.load()
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [(listening ? Aurora.accent : Aurora.tint(1)).opacity(0.5), .clear],
                                     center: .center, startRadius: 10, endRadius: 190))
                .frame(width: 236, height: 236)
                .blur(radius: 20)

            Group {
                if let idle = art.idle {
                    idle.resizable().scaledToFit()
                } else {
                    Circle().fill(Color(red: 0.97, green: 0.96, blue: 0.93))
                }
            }
            .frame(width: 92, height: 95)
            .scaleEffect(moonDown ? 0.95 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: moonDown)
        }
        .position(centre)
        .contentShape(Circle().size(width: 104, height: 104)
            .offset(x: centre.x - 52, y: centre.y - 52))
        .onTapGesture {
            guard !listening else { return }
            moonDown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { moonDown = false }
            onListen()
        }
        .help(listening ? "Listening" : "Tap to ask out loud")
    }

    // MARK: listening

    /// While it listens the folder arcs step aside for ticks that move with
    /// your voice. The ring is the same circle doing a different job, so the
    /// moon never jumps to another screen to hear you.
    private func earRing(centre: CGPoint) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // -160 dB is silence, about -20 is speaking.
            let loud = max(0, min(1, (Double(levelDB()) + 55) / 40))
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let ticks = 56
                for i in 0..<ticks {
                    let a = Double(i) / Double(ticks) * 2 * .pi - .pi / 2
                    let wobble = (sin(t * 5.2 + Double(i) * 0.7) + 1) / 2
                    let len = 6 + wobble * (6 + loud * 26)
                    let inner = ringRadius + 6
                    let p1 = CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner)
                    let p2 = CGPoint(x: c.x + cos(a) * (inner + len), y: c.y + sin(a) * (inner + len))
                    var line = Path()
                    line.move(to: p1); line.addLine(to: p2)
                    ctx.stroke(line,
                               with: .color(i % 5 == 0 ? Aurora.tint(2) : Aurora.accent),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                var rim = Path()
                rim.addArc(center: c, radius: ringRadius, startAngle: .degrees(0),
                           endAngle: .degrees(360), clockwise: false)
                ctx.stroke(rim, with: .color(Aurora.accent), lineWidth: 3)
            }
        }
        .frame(width: (ringRadius + 60) * 2, height: (ringRadius + 60) * 2)
        .position(centre)
        .allowsHitTesting(false)
    }

    private func heard(centre: CGPoint, width: CGFloat) -> some View {
        AuroraHeardView(transcript: transcript,
                        onCancel: onStopListening,
                        onSend: { text in
                            onStopListening()
                            onAsk(text)
                        })
            .position(x: centre.x, y: centre.y + ringRadius + 150)
    }

    // MARK: the label

    private func chip(for seg: Segment, centre: CGPoint) -> some View {
        let mid = (seg.start + seg.end) / 2 * .pi / 180
        let out = ringRadius + 54
        let point = CGPoint(x: centre.x + cos(mid) * out, y: centre.y + sin(mid) * out)

        return HStack(spacing: 9) {
            Circle().fill(seg.tint).frame(width: 9, height: 9)
            Text(seg.tile.name)
                .font(Aurora.ui(14, .semibold))
                .foregroundStyle(Aurora.ink)
            Text("\(seg.tile.captureCount) ITEMS")
                .font(Aurora.mono(11))
                .tracking(0.8)
                .foregroundStyle(Aurora.ink3)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Aurora.ink3)
        }
        .padding(.horizontal, 15).padding(.vertical, 10)
        .background {
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().fill(Aurora.surface.opacity(0.72)))
                .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        }
        .fixedSize()
        .contentShape(Capsule())
        .onHover { setHover(seg.id, $0) }
        .onTapGesture { onOpenFolder(seg.tile) }
        .help("Open \(seg.tile.name)")
        .position(point)
    }

}

/// One folder's slice of the ring, as a line to stroke.
private struct OrbitArc: Shape {
    var start: Double
    var end: Double
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: radius,
                 startAngle: .degrees(start),
                 endAngle: .degrees(end),
                 clockwise: false)
        return p
    }
}

/// The same slice as a solid wedge, used only for hit testing. A pointer should
/// not have to find a thirteen point line.
private struct OrbitWedge: Shape {
    var start: Double
    var end: Double
    var radius: CGFloat
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = radius + thickness / 2
        let inner = max(1, radius - thickness / 2)
        var p = Path()
        p.addArc(center: c, radius: outer,
                 startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        p.addArc(center: c, radius: inner,
                 startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// What it has heard so far, in the app's own serif, as a quote. It is a
/// question being formed, not a note being taken, so it never looks like
/// something that was filed. Shared by the orbit and the folders view, so
/// asking out loud works the same from either.
struct AuroraHeardView: View {
    @ObservedObject var transcript: LiveTranscriptEngine
    var onCancel: () -> Void
    var onSend: (String) -> Void

    /// Everything said this turn: the settled lines plus the words still
    /// arriving, so the sentence grows rather than appearing all at once.
    private var spoken: String {
        let settled = transcript.lines.filter { $0.voice == .you }.map(\.text)
        let arriving = transcript.pending[.you] ?? ""
        return (settled + [arriving])
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let said = spoken
        VStack(spacing: 22) {
            Text(said.isEmpty ? "Listening…" : "\u{201C}\(said)\u{201D}")
                .font(Aurora.serif(23))
                .italic()
                .foregroundStyle(said.isEmpty ? Aurora.ink3 : Aurora.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: 620)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(Aurora.mono(12)).tracking(1.2)
                        .foregroundStyle(Aurora.ink2)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(Capsule().fill(Aurora.surface2))
                }
                .buttonStyle(AuroraTapDown())

                Button {
                    let text = spoken
                    if text.isEmpty { onCancel() } else { onSend(text) }
                } label: {
                    HStack(spacing: 8) {
                        Text("SEND").font(Aurora.mono(12)).tracking(1.2)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 13)
                    .background(Capsule().fill(Aurora.accent))
                }
                .buttonStyle(AuroraTapDown())
                .disabled(said.isEmpty)
                .opacity(said.isEmpty ? 0.45 : 1)
            }
        }
    }
}
