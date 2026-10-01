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
    /// Where the overflow arc goes: the grid, which can show every folder.
    var onShowAll: () -> Void = {}
    /// The folder open in the panel. Its arc stays lit so you can see which
    /// slice you are reading.
    var focusedID: String? = nil
    /// When a panel takes the right of the window, the ring centres in what is
    /// left rather than sitting half under it.
    var shiftedFraction: CGFloat? = nil
    #if DEBUG
    /// Lets the offscreen renderer draw the label without a real pointer.
    var previewHover: String? = nil
    #endif

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
        shown.map { Double(max(1, $0.captureCount)) }
    }

    private var total: Double { max(1, weights.reduce(0, +)) }

    private struct Segment: Identifiable {
        let id: String
        let tile: AuroraFolderTile
        /// Where the stroke's path runs. Round caps then add `capDegrees` past
        /// each end, so the visible arc fills `slotStart...slotEnd - gap`.
        let start: Double
        let end: Double
        /// The whole slice this folder owns, gap included. The pointer target
        /// covers all of it, so there is no dead ground between two arcs.
        let slotStart: Double
        let slotEnd: Double
        let tint: Color
        var isOverflow: Bool { id == AuroraOrbitView.overflowID }
    }

    static let overflowID = "__orbit_more__"

    /// How far a round cap reaches past the end of its path, in degrees. The
    /// old allocation ignored it, so with a 2.4° gap every pair of neighbours
    /// overlapped by a couple of degrees and no gap was ever visible.
    private var capDegrees: Double { Double(thickness / 2 / ringRadius) * 180 / .pi }

    /// The least a folder can have: a dot, plus the gap after it.
    private var minSweep: Double { capDegrees * 2 + gapDegrees }

    /// More folders than fit as dots, and the smallest are gathered into a
    /// single "more" arc that opens the grid. Forty slivers is not a picture of
    /// anything; it is a beaded necklace nobody can click.
    private var shown: [AuroraFolderTile] {
        let capacity = max(1, Int(span / minSweep))
        guard tiles.count > capacity else { return tiles }
        let ranked = tiles.sorted { $0.captureCount > $1.captureCount }
        let keep = Array(ranked.prefix(capacity - 1))
        let rest = ranked.dropFirst(capacity - 1)
        let more = AuroraFolderTile(
            id: Self.overflowID, folderID: UUID(), name: "\(rest.count) more folders",
            point: .zero, notes: rest.flatMap(\.notes), tints: [-1])
        return keep + [more]
    }

    /// The ring never closes. A full circle reads as a meter at maximum, and
    /// with a single folder it would say nothing at all, so the arcs share
    /// three quarters of the circle and the open wedge sits at the top.
    private let span: Double = 276

    private var segments: [Segment] {
        let list = shown
        // Every folder is guaranteed a dot and a gap; what is left over is
        // shared by size. The big folders really do pay for the small ones now,
        // instead of the small ones being drawn on top of their neighbours.
        let floor = minSweep * Double(list.count)
        let spare = max(0, span - floor)
        var out: [Segment] = []
        var angle = -90 + (360 - span) / 2
        for (i, tile) in list.enumerated() {
            let sweep = minSweep + spare * (weights[i] / total)
            let pathStart = angle + capDegrees
            let pathEnd = max(pathStart, angle + sweep - gapDegrees - capDegrees)
            // Unfiled is the inbox, not a subject, so it takes no colour of its
            // own. Hashed, it landed on amber, the same as Hobbies.
            let tint = tile.id == Self.overflowID ? Aurora.ink3
                : tile.isUnfiled ? Aurora.ink2
                : Aurora.tint(tile.tints.first ?? 0)
            out.append(Segment(id: tile.id, tile: tile,
                               start: pathStart, end: pathEnd,
                               slotStart: angle, slotEnd: angle + sweep,
                               tint: tint))
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
        #if DEBUG
        let id = hovered ?? previewHover
        #else
        let id = hovered
        #endif
        guard let id else { return nil }
        return segments.first { $0.id == id }
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
            let free = geo.size.width * (1 - (shiftedFraction ?? 0))
            let centre = CGPoint(x: free / 2, y: geo.size.height / 2 - 40)

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
            .animation(.spring(response: 0.48, dampingFraction: 0.86), value: shiftedFraction)
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
                let lit = hovered == seg.id || focusedID == seg.id
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
                    .contentShape(OrbitWedge(start: seg.slotStart, end: seg.slotEnd,
                                             radius: ringRadius, thickness: thickness + 16))
                    .onHover { setHover(seg.id, $0) }
                    .onTapGesture { open(seg) }
                    .help(seg.isOverflow ? "Show every folder" : "Open \(seg.tile.name)")
                    .position(centre)
            }
        }
    }

    private func open(_ seg: Segment) {
        if seg.isOverflow { onShowAll() } else { onOpenFolder(seg.tile) }
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
            .frame(width: 680, height: 260, alignment: .top)
            .position(x: centre.x, y: centre.y + ringRadius + 70 + 130)
    }

    // MARK: the label

    private func chip(for seg: Segment, centre: CGPoint) -> some View {
        // Anchor the label's near edge just outside the ring, on the side the
        // arc faces. Centring it there put half the label over the arc you
        // were pointing at.
        let mid = (seg.slotStart + seg.slotEnd - gapDegrees) / 2 * .pi / 180
        let dx = cos(mid), dy = sin(mid)
        let reach = ringRadius + thickness / 2 + 14
        let anchor = CGPoint(x: centre.x + dx * reach, y: centre.y + dy * reach)
        let side: Alignment = abs(dx) >= 0.45
            ? (dx < 0 ? .trailing : .leading)
            : (dy < 0 ? .bottom : .top)

        let count = seg.tile.captureCount
        let label = HStack(spacing: 9) {
            Circle().fill(seg.tint).frame(width: 9, height: 9)
            Text(seg.tile.name)
                .font(Aurora.ui(14, .semibold))
                .foregroundStyle(Aurora.ink)
            Text(seg.isOverflow ? "SHOW ALL"
                 : count == 0 ? "EMPTY"
                 : "\(count) \(count == 1 ? "ITEM" : "ITEMS")")
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
        .onTapGesture { open(seg) }
        .help(seg.isOverflow ? "Show every folder" : "Open \(seg.tile.name)")

        return Color.clear
            .frame(width: 1, height: 1)
            .overlay(alignment: side) { label }
            .position(anchor)
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
                // A long sentence keeps its newest words on screen. The start
                // of what you said is the part you already know.
                .lineLimit(3)
                .truncationMode(.head)
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
