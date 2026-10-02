import SwiftUI
import AppKit

/// A topic's notes, fanned on a curve beside the ring.
///
/// They sit on a circle around the moon, on the side the topic's arc is on, so
/// opening a topic looks like its notes swinging out of that part of the ring.
/// The one you are on faces you; two either side curve back toward the moon,
/// smaller and dimmer. Scroll, or use the arrow keys, and the curve turns.
///
/// It is the same card and the same aurora as the folder view's band, stood
/// on its end and bent.
struct AuroraNoteArc: View {
    enum Side { case left, right }

    let tile: AuroraFolderTile
    let side: Side
    var onOpenNote: (CanvasNoteSnapshot) -> Void
    var onClose: () -> Void
    var onRenameFolder: (String) -> Void = { _ in }
    var onNoteRightClick: ((CanvasNoteSnapshot, CGPoint) -> Void)? = nil
    @Binding var renaming: Bool
    var cancelRenameTick: Int = 0
    /// Skips the opening animation. Only the offscreen renderer uses it.
    var startsOpen = false

    @State private var selected = 0
    @State private var bloom = false
    @State private var hovered: URL?
    @State private var scrollMonitor: Any?
    @State private var scrollCarry: CGFloat = 0
    @State private var editingTitle = false
    @State private var draft = ""
    @FocusState private var keyboard: Bool
    @FocusState private var fieldFocused: Bool

    /// Where the moon sits across the window while a topic is open: away from
    /// the side the notes come out of, so the curve has room.
    /// The moon stays where it is. Sliding it aside left a wide empty band on
    /// one side of the window and made the ring feel like it had been moved.
    static func ringCentreFraction(for side: Side) -> CGFloat { 0.5 }

    private static let card = CGSize(width: 218, height: 186)
    /// The curve the cards sit on, measured from the moon's centre. As wide
    /// as the window allows with the moon in the middle, within limits.
    private func orbit(_ width: CGFloat) -> CGFloat {
        min(300, max(190, width / 2 - Self.card.width - 36))
    }
    /// The turn between neighbours. About 110pt apart vertically, so the
    /// 186pt cards overlap like a fanned deck, as in the folder band.
    private static let step: Double = 15
    /// The cards' curve sits a little below the moon's centre, leaving room
    /// above the top card for the topic's name.
    private static let drop: CGFloat = 58
    /// Cards beyond this many either side of the one you are on are hidden.
    private static let reach = 2

    private var notes: [CanvasNoteSnapshot] { tile.notesByRecency }
    private var tint: Color { tile.isUnfiled ? Aurora.arcNeutral : Aurora.arcTint(tile.tints.first ?? 0) }

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width * Self.ringCentreFraction(for: side),
                                 y: geo.size.height / 2 - 40)
            let r = orbit(geo.size.width)
            ZStack {
                // Clicking anywhere off the cards closes the topic, except on
                // the ring, which keeps its own clicks for switching topics.
                Color.black.opacity(0.001)
                    .contentShape(RingHole(centre: centre, radius: Mindspace.ringRadius + 34),
                                  eoFill: true)
                    .onTapGesture(perform: onClose)

                aurora(centre: centre, r: r)
                header(centre: centre, r: r)

                if notes.isEmpty {
                    Text("Nothing in \(tile.name) yet. Captures land here while it is the destination.")
                        .font(Aurora.serif(17))
                        .foregroundStyle(Aurora.ink3)
                        .multilineTextAlignment(side == .right ? .leading : .trailing)
                        .frame(width: 260, alignment: side == .right ? .leading : .trailing)
                        .position(x: centre.x + (side == .right ? 1 : -1) * (r + 130),
                                  y: centre.y)
                } else {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { i, note in
                        card(note, at: i, centre: centre, r: r)
                    }
                }
            }
        }
        .focusable()
        .focused($keyboard)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) {
            guard !editingTitle, notes.indices.contains(selected) else { return .ignored }
            onOpenNote(notes[selected])
            return .handled
        }
        .onAppear {
            keyboard = true
            installScroll()
            if startsOpen { bloom = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { bloom = true }
        }
        .onDisappear {
            removeScroll()
            if editingTitle { editingTitle = false; renaming = false }
        }
        .onChange(of: fieldFocused) { _, focused in
            if !focused, editingTitle { commitTitle() }
        }
        .onChange(of: cancelRenameTick) { _, _ in
            editingTitle = false
            renaming = false
            keyboard = true
        }
    }

    // MARK: a card on the curve

    /// The middle of the five on screen. It follows the selection, but stops
    /// at the ends of the list, so the first and last notes still show four
    /// neighbours and the selection walks to the end of the curve instead.
    private var windowCentre: Int {
        let visible = Self.reach * 2 + 1
        guard notes.count > visible else { return (notes.count - 1) / 2 }
        return min(max(selected, Self.reach), notes.count - 1 - Self.reach)
    }

    /// Where and how one card sits on the curve, worked out once with every
    /// type spelled out. Inline, the arithmetic and the modifier chain took the
    /// compiler a full second, which the toolchain CI uses does not allow.
    private struct Placement {
        let shown: Bool
        let away: Int
        let lit: Bool
        let scale: Double
        let tiltDegrees: Double
        let anchor: UnitPoint
        let position: CGPoint
        let opacity: Double
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowY: CGFloat
        let z: Double
        let bloomDelay: Double
    }

    private func placement(_ note: CanvasNoteSnapshot, at i: Int, centre: CGPoint, r: CGFloat) -> Placement {
        // Place by position in the window; weight by distance from the selection.
        let d: Int = i - windowCentre
        let away: Int = abs(i - selected)
        let shown: Bool = abs(d) <= Self.reach
        let right: Bool = side == .right
        let sign: Double = right ? 1.0 : -1.0
        // Right: angles run downward from 3 o'clock. Left: from 9 o'clock.
        let angle: Double = (right ? 0.0 : 180.0) + Double(d) * Self.step * sign
        let a: Double = angle * Double.pi / 180.0
        let px: Double = Double(centre.x) + cos(a) * Double(r)
        let py: Double = Double(centre.y) + Double(Self.drop) + sin(a) * Double(r)
        // The card's near edge sits on the curve and the card reaches outward.
        let x: Double = px + sign * Double(Self.card.width) / 2.0
        let restX: Double = Double(centre.x) + sign * (Double(Mindspace.ringRadius) + 20.0)
        let lit: Bool = hovered == note.url
        let scale: Double = away == 0 ? 1.0 : (away == 1 ? 0.92 : 0.84)
        let opacity: Double = (!shown || !bloom) ? 0.0 : (away == 0 ? 1.0 : (away == 1 ? 0.85 : 0.62))
        let pos = CGPoint(x: bloom ? x : restX, y: bloom ? py : Double(centre.y))
        return Placement(
            shown: shown, away: away, lit: lit, scale: scale,
            tiltDegrees: Double(d) * Self.step * 0.32 * sign,
            anchor: right ? .leading : .trailing,
            position: pos, opacity: opacity,
            shadowOpacity: away == 0 ? 0.3 : 0.14,
            shadowRadius: away == 0 ? 30 : 12,
            shadowY: away == 0 ? 14 : 6,
            z: Double(100 - away * 10) + (lit ? 5.0 : 0.0),
            bloomDelay: Double(min(abs(d) + Self.reach, 4)) * 0.04)
    }

    private func card(_ note: CanvasNoteSnapshot, at i: Int, centre: CGPoint, r: CGFloat) -> some View {
        let p: Placement = placement(note, at: i, centre: centre, r: r)
        let hoverScale: Double = (p.lit && p.away != 0) ? 1.03 : 1.0
        let ringOpacity: Double = (p.away == 0 && notes.count > 1) ? 0.9 : 0.0
        let open: () -> Void = {
            if i == selected { onOpenNote(note) } else { move(to: i) }
        }
        let base = AuroraNoteCard(note: note,
                                  tint: tile.tints[i % tile.tints.count],
                                  isNew: note.url == tile.freshNoteID,
                                  open: open,
                                  onRightClick: { point in onNoteRightClick?(note, point) })
        let leaned = base
            .scaleEffect(p.scale * hoverScale, anchor: p.anchor)
            // Each card leans with the curve.
            .rotationEffect(.degrees(p.tiltDegrees), anchor: p.anchor)
            .opacity(p.opacity)
            .shadow(color: .black.opacity(p.shadowOpacity), radius: p.shadowRadius, y: p.shadowY)
        // The selected note is ringed in its topic's colour, so arrowing
        // through the curve always shows where you are.
        let ringed = leaned.overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(ringOpacity), lineWidth: 2)
                .scaleEffect(p.scale, anchor: p.anchor)
                .rotationEffect(.degrees(p.tiltDegrees), anchor: p.anchor)
                .allowsHitTesting(false)
        }
        return ringed
            .position(p.position)
            .zIndex(p.z)
            .allowsHitTesting(p.shown)
            .onHover { inside in
                hovered = inside ? note.url : (hovered == note.url ? nil : hovered)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selected)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(p.bloomDelay), value: bloom)
    }

    // MARK: the light behind

    private func aurora(centre: CGPoint, r: CGFloat) -> some View {
        let sign: CGFloat = side == .right ? 1 : -1
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [Aurora.tint(tile.tints[i % tile.tints.count]).opacity(0.5),
                                                  Aurora.tint(tile.tints[(i + 1) % tile.tints.count]).opacity(0.26),
                                                  .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 130 - CGFloat(i) * 22, height: 560)
                    .offset(x: CGFloat(i - 1) * 46, y: CGFloat(i - 1) * 30)
                    .rotationEffect(.degrees(Double(i - 1) * 3))
            }
        }
        .blur(radius: 46)
        .opacity(bloom ? 0.9 : 0)
        .position(x: centre.x + sign * (r + Self.card.width * 0.45), y: centre.y)
        .allowsHitTesting(false)
    }

    // MARK: the title, floating

    /// Above the cards, lined up with their near edge, so the name heads the
    /// stack it belongs to.
    private func header(centre: CGPoint, r: CGFloat) -> some View {
        let sign: CGFloat = side == .right ? 1 : -1
        let edge = centre.x + sign * (r - 6)
        return VStack(alignment: side == .right ? .leading : .trailing, spacing: 8) {
            HStack(spacing: 9) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(meta)
                    .font(Aurora.mono(11)).tracking(1.2)
                    .foregroundStyle(Aurora.ink3)
            }
            if editingTitle {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Aurora.display(34))
                    .foregroundStyle(Aurora.ink)
                    .multilineTextAlignment(side == .right ? .leading : .trailing)
                    .focused($fieldFocused)
                    .onSubmit(commitTitle)
                    .frame(width: 360)
                    .padding(.bottom, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(tint).frame(height: 1.5) }
            } else {
                Text(tile.name)
                    .font(Aurora.display(34))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginTitle() }
                    .help("Double-click to rename")
            }
        }
        .fixedSize()
        .frame(width: 1, height: 1, alignment: side == .right ? .topLeading : .topTrailing)
        .position(x: edge, y: 52)
        .opacity(bloom ? 1 : 0)
    }

    private var meta: String {
        let n = tile.notes.count, c = tile.captureCount
        return "\(n) \(n == 1 ? "NOTE" : "NOTES")  ·  \(c) \(c == 1 ? "CAPTURE" : "CAPTURES")"
    }

    // MARK: moving

    private func move(_ delta: Int) { move(to: selected + delta) }

    private func move(to i: Int) {
        guard !notes.isEmpty else { return }
        let next = min(max(i, 0), notes.count - 1)
        if next != selected { selected = next }
    }

    /// One notch of a wheel, or about 36pt of trackpad, turns the curve one
    /// card. Kept in a carry so slow scrolling still moves, and fast scrolling
    /// does not skip past what you were looking for.
    private func installScroll() {
        removeScroll()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard !notes.isEmpty else { return event }
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            scrollCarry += dy
            while scrollCarry <= -36 { move(1); scrollCarry += 36 }
            while scrollCarry >= 36 { move(-1); scrollCarry -= 36 }
            if event.phase == .ended || event.momentumPhase == .ended { scrollCarry = 0 }
            return nil
        }
    }

    private func removeScroll() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    // MARK: renaming the topic

    private func beginTitle() {
        draft = tile.name
        editingTitle = true
        renaming = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commitTitle() {
        guard editingTitle else { return }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTitle = false
        renaming = false
        keyboard = true
        if !name.isEmpty, name != tile.name { onRenameFolder(name) }
    }
}

/// Shared geometry the ring and the curve both need.
enum Mindspace {
    static let ringRadius: CGFloat = 116
}

/// The whole window with a round hole in it, so a tap catcher can cover
/// everything but the ring.
private struct RingHole: Shape {
    let centre: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                width: radius * 2, height: radius * 2))
        return p
    }
}
