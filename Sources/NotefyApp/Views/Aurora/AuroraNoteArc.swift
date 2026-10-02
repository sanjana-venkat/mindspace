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
    static func ringCentreFraction(for side: Side) -> CGFloat { side == .right ? 0.34 : 0.66 }

    private static let card = CGSize(width: 218, height: 186)
    /// The curve the cards sit on, measured from the moon's centre.
    private static let orbit: CGFloat = 300
    /// The turn between neighbours. About 110pt apart vertically, so the
    /// 186pt cards overlap like a fanned deck, as in the folder band.
    private static let step: Double = 18
    /// Cards beyond this many either side of the one you are on are hidden.
    private static let reach = 2

    private var notes: [CanvasNoteSnapshot] { tile.notesByRecency }
    private var tint: Color { Aurora.tint(tile.tints.first ?? 0) }

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width * Self.ringCentreFraction(for: side),
                                 y: geo.size.height / 2 - 40)
            ZStack {
                aurora(centre: centre)
                header(centre: centre)

                if notes.isEmpty {
                    Text("Nothing in \(tile.name) yet. Captures land here while it is the destination.")
                        .font(Aurora.serif(17))
                        .foregroundStyle(Aurora.ink3)
                        .multilineTextAlignment(side == .right ? .leading : .trailing)
                        .frame(width: 260, alignment: side == .right ? .leading : .trailing)
                        .position(x: centre.x + (side == .right ? 1 : -1) * (Self.orbit + 130),
                                  y: centre.y)
                } else {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { i, note in
                        card(note, at: i, centre: centre)
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

    private func card(_ note: CanvasNoteSnapshot, at i: Int, centre: CGPoint) -> some View {
        // Place by position in the window; weight by distance from the selection.
        let d = i - windowCentre
        let away = abs(i - selected)
        let shown = abs(d) <= Self.reach
        let sign: Double = side == .right ? 1 : -1
        // Right: angles run downward from 3 o'clock. Left: from 9 o'clock.
        let angle = (side == .right ? 0 : 180) + Double(d) * Self.step * sign
        let a = angle * .pi / 180
        let point = CGPoint(x: centre.x + cos(a) * Self.orbit, y: centre.y + sin(a) * Self.orbit)
        // The card's near edge sits on the curve and the card reaches outward.
        let x = point.x + sign * Self.card.width / 2
        let lit = hovered == note.url
        let scale = away == 0 ? 1.0 : (away == 1 ? 0.92 : 0.84)

        return AuroraNoteCard(note: note,
                              tint: tile.tints[i % tile.tints.count],
                              isNew: note.url == tile.freshNoteID,
                              open: {
                                  if i == selected { onOpenNote(note) } else { move(to: i) }
                              },
                              onRightClick: { point in onNoteRightClick?(note, point) })
            .scaleEffect(scale * (lit && away != 0 ? 1.03 : 1), anchor: side == .right ? .leading : .trailing)
            // Each card leans with the curve.
            .rotationEffect(.degrees(Double(d) * Self.step * 0.32 * sign),
                            anchor: side == .right ? .leading : .trailing)
            .opacity(!shown || !bloom ? 0 : (away == 0 ? 1 : (away == 1 ? 0.85 : 0.62)))
            .shadow(color: .black.opacity(away == 0 ? 0.3 : 0.14), radius: away == 0 ? 30 : 12, y: away == 0 ? 14 : 6)
            // The selected note is ringed in its topic's colour, so arrowing
            // through the curve always shows where you are.
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(away == 0 && notes.count > 1 ? 0.9 : 0), lineWidth: 2)
                    .scaleEffect(scale, anchor: side == .right ? .leading : .trailing)
                    .rotationEffect(.degrees(Double(d) * Self.step * 0.32 * sign),
                                    anchor: side == .right ? .leading : .trailing)
                    .allowsHitTesting(false)
            }
            .position(x: bloom ? x : centre.x + sign * (Mindspace.ringRadius + 20),
                      y: bloom ? point.y : centre.y)
            .zIndex(Double(100 - away * 10) + (lit ? 5 : 0))
            .allowsHitTesting(shown)
            .onHover { inside in
                hovered = inside ? note.url : (hovered == note.url ? nil : hovered)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selected)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(min(abs(d) + Self.reach, 4)) * 0.04),
                       value: bloom)
    }

    // MARK: the light behind

    private func aurora(centre: CGPoint) -> some View {
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
        .position(x: centre.x + sign * (Self.orbit + Self.card.width * 0.45), y: centre.y)
        .allowsHitTesting(false)
    }

    // MARK: the title, floating

    /// Above the moon, centred on it. Beside the cards, the first one rose
    /// over it whenever you were at the top of a long topic.
    private func header(centre: CGPoint) -> some View {
        VStack(spacing: 8) {
            // The close sits on the side the notes are on, next to them.
            HStack(spacing: 9) {
                if side == .left { closeButton.padding(.trailing, 4) }
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(meta)
                    .font(Aurora.mono(11)).tracking(1.2)
                    .foregroundStyle(Aurora.ink3)
                if side == .right { closeButton.padding(.leading, 4) }
            }
            if editingTitle {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Aurora.display(34))
                    .foregroundStyle(Aurora.ink)
                    .multilineTextAlignment(.center)
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
        .frame(width: 1, height: 1, alignment: .top)
        .position(x: centre.x, y: 58)
        .opacity(bloom ? 1 : 0)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Aurora.ink2)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(AuroraTapDown())
        .help("Close (Esc)")
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
