import SwiftUI

/// How many sheets peek out from behind a folder: the pile is the count.
/// One capture shows one sheet; fifteen show five; a very full folder tops out
/// at eight so the fan stays a fan and not a smear.
enum AuroraPile {
    static func sheets(for captures: Int) -> Int {
        switch captures {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        case 3...4: return 3
        case 5...9: return 4
        case 10...19: return 5
        case 20...39: return 6
        case 40...79: return 7
        default: return 8
        }
    }

    /// Note `i` of `n`, peeking over the top edge of the folder: a small card,
    /// mostly hidden behind the plate, showing only its head. They spread
    /// across the top and never past the folder's left or right edge.
    static func place(_ i: Int, of n: Int, plateWidth: CGFloat, plateHeight: CGFloat)
        -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: Double) {
        let w: CGFloat = n <= 4 ? 64 : max(34, 64 - CGFloat(n - 4) * 5)
        let h: CGFloat = 56
        let span = max(0, plateWidth - 30 - w)
        let spacing = n > 1 ? min(w * 0.92, span / CGFloat(n - 1)) : 0
        let x = (CGFloat(i) - CGFloat(n - 1) / 2) * spacing
        let poke: CGFloat = i % 2 == 0 ? 25 : 17
        let y = -plateHeight / 2 - poke + h / 2
        return (x, y, w, h, i % 2 == 0 ? -2.5 : 2.5)
    }
}


/// The aurora itself: the folder's three hues drifting across the plate.
struct AuroraWash: View {
    let tints: [Int]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Aurora.tint(tints[0]),
                                    Aurora.tint(tints[1 % tints.count]),
                                    Aurora.tint(tints[2 % tints.count])],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Aurora.tint(tints[2 % tints.count]).opacity(0.95), .clear],
                           center: .init(x: 0.18, y: 0.12), startRadius: 2, endRadius: 130)
            RadialGradient(colors: [Aurora.tint(tints[1 % tints.count]).opacity(0.9), .clear],
                           center: .init(x: 0.88, y: 0.9), startRadius: 2, endRadius: 130)
            RadialGradient(colors: [Aurora.tint(tints[0]).opacity(0.7), .clear],
                           center: .init(x: 0.6, y: 0.35), startRadius: 2, endRadius: 90)
            LinearGradient(colors: [.white.opacity(0.22), .clear],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
        }
    }
}

/// A folder on the canvas: tinted sheets stacked under a frosted plate.
struct AuroraFolderNode: View {
    let tile: AuroraFolderTile
    var zoom: CGFloat
    var dimmed: Bool
    var cancelEdits: Int
    var onOpen: () -> Void
    var onMove: (CGPoint) -> Void
    var onRename: (String) -> Void
    var onRightClick: ((CGPoint) -> Void)? = nil
    /// Notes dropped on this folder. Returns true when they were filed.
    var onDropNotes: (([URL]) -> Bool)? = nil

    @State private var drag: CGSize = .zero
    @State private var hover = false
    @State private var targeted = false
    @State private var editing = false
    @State private var draft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                let sheets = AuroraPile.sheets(for: tile.captureCount)
                ForEach(0..<sheets, id: \.self) { i in
                    let p = AuroraPile.place(i, of: sheets, plateWidth: 196, plateHeight: 118)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Aurora.tint(tile.tints[0] + i))
                        .frame(width: p.w, height: p.h)
                        .rotationEffect(.degrees(p.angle + tabRotation(i)))
                        .offset(x: p.x + tabOffset(i).width,
                                y: p.y + tabOffset(i).height)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Aurora.surface.opacity(0.82))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .frame(width: 196, height: 118)
                    .shadow(color: .black.opacity(0.09), radius: 14, y: 6)
            }
            .frame(width: 212, height: 168)

            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if editing {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .font(Aurora.title(16))
                            .multilineTextAlignment(.center)
                            .frame(width: 150)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Aurora.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Aurora.focusRing, lineWidth: 2))
                            .onSubmit { onRename(draft); editing = false }
                            // Esc abandons the edit; anywhere else commits it.
                            .onExitCommand { draft = tile.name; editing = false }
                    } else {
                        Text(tile.name).font(Aurora.title(16)).foregroundStyle(Aurora.ink)
                    }
                    Text("\(tile.notes.count)")
                        .font(Aurora.ui(14, .medium)).foregroundStyle(Aurora.ink3).monospacedDigit()
                }
                Text(tile.captureCount == 0
                     ? (tile.isUnfiled ? "NOT FILED YET" : "EMPTY")
                     : "\(tile.captureCount) CAPTURES")
                    .font(Aurora.mono(9.5)).tracking(1.2)
                    .foregroundStyle(Aurora.ink3)
            }
        }
        .frame(width: 212)
        // Search dims what doesn't match. It used to drain the colour too,
        // which made the folders look x-rayed rather than quiet.
        .opacity(dimmed ? 0.34 : 1)
        .offset(drag)
        .onHover { hover = $0 && !dimmed }
        .onTapGesture(count: 2) { if !tile.isUnfiled { draft = tile.name; editing = true } }
        .onTapGesture { if !editing { onOpen() } }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    drag = CGSize(width: v.translation.width / zoom, height: v.translation.height / zoom)
                }
                .onEnded { v in
                    onMove(CGPoint(x: tile.point.x + v.translation.width / zoom,
                                   y: tile.point.y + v.translation.height / zoom))
                    drag = .zero
                }
        )
        .animation(.smooth(duration: 0.2), value: hover)
        .animation(.smooth(duration: 0.3), value: dimmed)
        .onChange(of: cancelEdits) { _, _ in
            if editing { onRename(draft) }
            editing = false
        }
        .modifier(AuroraOptionalRightClick(action: onRightClick))
        // A note dropped on the folder is filed in it. The pile lifts and
        // lights while it is over the target, so the aim is never a guess.
        .scaleEffect(targeted ? 1.06 : 1)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Aurora.accentSoft.opacity(targeted ? 0.9 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Aurora.accent.opacity(targeted ? 0.85 : 0), lineWidth: 2)
                }
                .padding(-10)
        }
        .animation(.smooth(duration: 0.16), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            onDropNotes?(urls) ?? false
        } isTargeted: { targeted = $0 && onDropNotes != nil }
    }

    private func tabOffset(_ index: Int) -> CGSize {
        guard hover, !reduceMotion else { return .zero }
        let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
        return CGSize(width: direction * (2 + CGFloat(index % 3)),
                      height: -CGFloat(2 + index % 2))
    }

    private func tabRotation(_ index: Int) -> Double {
        guard hover, !reduceMotion else { return 0 }
        return (index.isMultiple(of: 2) ? -1 : 1) * (1.4 + Double(index % 3) * 0.45)
    }
}

/// The folder steps forward and its notes rise above it in a wave — a band of
/// aurora with the notes riding on it. Few notes sit side by side; many stack
/// into a fanned deck that scrolls sideways, so a folder with eighty captures
/// is still one gesture wide.
struct AuroraFocusOverlay: View {
    let tile: AuroraFolderTile
    var onClose: () -> Void
    var onOpenNote: (URL) -> Void
    var onNoteRightClick: ((CanvasNoteSnapshot, CGPoint) -> Void)? = nil
    /// Dragging a note out is a request to see the rest of the library.
    var onDragNoteOut: (() -> Void)? = nil

    @State private var bloom = false
    @State private var hovered: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { tile.notes.count }

    /// Side by side while they fit; past that they overlap, and past that they
    /// overlap hard and the band scrolls.
    private var spacing: CGFloat {
        switch count {
        case 0...4: return 16
        case 5...9: return -26
        case 10...24: return -104
        default: return -142
        }
    }

    private func crest(_ i: Int) -> CGFloat { -sin(Double(i) * 0.62) * 30 }
    private func tilt(_ i: Int) -> Double { cos(Double(i) * 0.62) * 2.6 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { collapseAndClose() }

                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    band(width: geo.size.width)
                        .frame(height: 300)
                    plate
                        .scaleEffect(bloom ? 1 : 0.96)
                    Spacer(minLength: 130)
                }
                .padding(.top, 96)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { bloom = true } }
    }

    // MARK: the band

    private func band(width: CGFloat) -> some View {
        ZStack {
            aurora.frame(height: 220)

            if count == 0 {
                Text("Nothing in here yet — name a note below and hit Create.")
                    .font(Aurora.ui(13, .medium)).foregroundStyle(Aurora.ink3)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(tile.notesByRecency.enumerated()), id: \.element.id) { i, note in
                            AuroraNoteCard(note: note,
                                           tint: tile.tints[i % tile.tints.count],
                                           isNew: note.url == tile.freshNoteID,
                                           open: { onOpenNote(note.url) },
                                           onRightClick: { point in onNoteRightClick?(note, point) },
                                           onDragStart: onDragNoteOut)
                            .offset(
                                x: bloom ? 0 : collapsedX(i),
                                y: bloom ? crest(i) + (hovered == note.url ? -16 : 0) : 270
                            )
                            .rotationEffect(.degrees(bloom ? tilt(i) : collapsedTilt(i)), anchor: .bottom)
                            .scaleEffect(bloom ? (hovered == note.url ? 1.05 : 1) : 0.32, anchor: .bottom)
                            .opacity(bloom ? 1 : 0)
                            .shadow(color: .black.opacity(hovered == note.url ? 0.24 : 0.10),
                                    radius: hovered == note.url ? 34 : 14,
                                    y: hovered == note.url ? 16 : 7)
                            .zIndex(hovered == note.url ? 1000 : Double(i))
                            .onHover { inside in
                                withAnimation(.smooth(duration: 0.22)) {
                                    hovered = inside ? note.url : (hovered == note.url ? nil : hovered)
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(min(i, 12)) * 0.035),
                                       value: bloom)
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 54)
                    .frame(minWidth: width, alignment: .center)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// The light the notes ride on: three tinted blooms, blurred into a band.
    private var aurora: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(colors: [Aurora.tint(tile.tints[i % tile.tints.count]).opacity(0.55),
                                                Aurora.tint(tile.tints[(i + 1) % tile.tints.count]).opacity(0.30),
                                                .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 120 - CGFloat(i) * 22)
                    .offset(x: CGFloat(i - 1) * 90, y: CGFloat(i) * 26 - 20)
                    .rotationEffect(.degrees(Double(i - 1) * 2.4))
            }
        }
        .blur(radius: 44)
        .opacity(bloom ? 1 : 0)
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }

    // MARK: the folder itself

    private var plate: some View {
        VStack(spacing: 14) {
            ZStack {
                let sheets = AuroraPile.sheets(for: tile.captureCount)
                ForEach(0..<sheets, id: \.self) { i in
                    let p = AuroraPile.place(i, of: sheets, plateWidth: 210, plateHeight: 128)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Aurora.tint(tile.tints[0] + i))
                        .frame(width: p.w, height: p.h)
                        .rotationEffect(.degrees(bloom || reduceMotion ? p.angle : 0))
                        .offset(x: bloom || reduceMotion ? p.x : 0,
                                y: bloom || reduceMotion ? p.y : 34)
                        .opacity(bloom || reduceMotion ? 1 : 0)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        .animation(
                            reduceMotion
                                ? nil
                                : .spring(response: 0.48, dampingFraction: 0.72)
                                    .delay(Double(i) * 0.045),
                            value: bloom
                        )
                }
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Aurora.surface.opacity(0.86))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .frame(width: 210, height: 128)
                    .shadow(color: .black.opacity(0.22), radius: 40, y: 18)
            }
            VStack(spacing: 4) {
                Text(tile.name).font(Aurora.title(22)).foregroundStyle(Aurora.ink)
                Text("\(tile.notes.count) notes · \(tile.captureCount) captures")
                    .font(Aurora.ui(12, .medium)).foregroundStyle(Aurora.ink2)
            }
        }
    }

    /// Pulls each card back to the folder's mouth before the focus layer is
    /// removed, so an outside click reads as closing the physical folder and
    /// returning home rather than simply fading the notes away.
    private func collapseAndClose() {
        guard !reduceMotion else { onClose(); return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { bloom = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(390))
            onClose()
        }
    }

    private func collapsedX(_ index: Int) -> CGFloat {
        let stride = 218 + spacing
        return (CGFloat(count - 1) / 2 - CGFloat(index)) * stride
    }

    private func collapsedTilt(_ index: Int) -> Double {
        (index.isMultiple(of: 2) ? -1 : 1) * Double(min(index + 1, 5)) * 1.8
    }
}

/// A note as a card: its title, the first line of what's in it, and how much.
struct AuroraNoteCard: View {
    let note: CanvasNoteSnapshot
    var tint: Int
    /// The most recent note in its folder, when that was today.
    var isNew: Bool = false
    var open: () -> Void
    var onRightClick: ((CGPoint) -> Void)? = nil
    /// Called as the card is picked up, so an open folder can get out of the
    /// way and let you see where you might put it.
    var onDragStart: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                // Badges ride in the top-right corner of the colour band, out
                // of the way of the title underneath it.
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [Aurora.tint(tint), Aurora.tint(tint).opacity(0.74)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    HStack(spacing: 5) {
                        if isNew {
                            Text("NEW")
                                .font(Aurora.mono(8.5)).tracking(1)
                                .foregroundStyle(Aurora.onSolid)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Aurora.solid, in: Capsule())
                        }
                        if note.hasOrganizedNote {
                            Text("ORGANIZED")
                                .font(Aurora.mono(8.5)).tracking(1)
                                .foregroundStyle(Aurora.ink2)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Aurora.surface.opacity(0.8), in: Capsule())
                        }
                    }
                    .padding(9)
                }
                .frame(height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(Aurora.title(14.5)).foregroundStyle(Aurora.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !note.excerpt.isEmpty {
                        Text(note.excerpt)
                            .font(Aurora.ui(11.5, .regular)).foregroundStyle(Aurora.ink3)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        Text("\(note.captureCount) CAPTURES").font(Aurora.mono(9)).tracking(0.9)
                        Circle().fill(Aurora.ink3).frame(width: 2.5, height: 2.5)
                        Text(note.createdAt.auroraRelative).font(Aurora.mono(9))
                    }
                    .foregroundStyle(Aurora.ink3)
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
                Spacer(minLength: 0)
            }
            .frame(width: 218, height: 186, alignment: .top)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hover ? Aurora.focusRing : Aurora.line, lineWidth: hover ? 1.6 : 1))
            .shadow(color: .black.opacity(hover ? 0.20 : 0.12), radius: hover ? 30 : 18, y: hover ? 14 : 8)
            .scaleEffect(hover ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.smooth(duration: 0.2), value: hover)
        .modifier(AuroraOptionalRightClick(action: onRightClick))
        // Pick a note up and drop it on a folder to file it there. The note's
        // own file is what travels, so it can also be dropped into Finder.
        // The payload is evaluated when the drag actually begins, which is
        // the only hook SwiftUI gives for "picked up".
        .draggable(dragPayload()) {
            AuroraDragChip(title: note.title, tint: tint)
        }
    }

    private func dragPayload() -> URL {
        if let onDragStart {
            DispatchQueue.main.async { onDragStart() }
        }
        return note.url
    }
}

/// What a dragged note looks like under the cursor: small, legible, and the
/// note's own colour, so you can see what you are carrying.
struct AuroraDragChip: View {
    let title: String
    let tint: Int

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Aurora.tint(tint))
                .frame(width: 14, height: 14)
            Text(title)
                .font(Aurora.ui(13, .medium))
                .foregroundStyle(Aurora.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
    }
}

/// Applies the right-click reporter only when the card's owner wants it.
struct AuroraOptionalRightClick: ViewModifier {
    let action: ((CGPoint) -> Void)?
    func body(content: Content) -> some View {
        if let action {
            content.auroraRightClick(in: "auroraWorkspace") { action($0) }
        } else {
            content
        }
    }
}

/// The same library as a sorted list; a folder opens into its notes inline.
struct AuroraFeedView: View {
    let tiles: [AuroraFolderTile]
    var query: String
    @Binding var sort: AuroraSort
    @Binding var focused: String?
    var onOpenNote: (URL) -> Void
    var onRenameFolder: (AuroraFolderTile, String) -> Void
    var onDeleteFolder: (AuroraFolderTile) -> Void
    var onRenameNote: (CanvasNoteSnapshot, String) -> Void
    var onDeleteNote: (CanvasNoteSnapshot) -> Void
    var onNoteRightClick: ((CanvasNoteSnapshot, CGPoint) -> Void)? = nil
    /// Notes dropped onto a folder row.
    var onDropNotes: ((AuroraFolderTile, [URL]) -> Bool)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let id = focused, let tile = tiles.first(where: { $0.id == id }) {
                    notes(in: tile)
                } else {
                    header
                    ForEach(tiles) { tile in
                        AuroraFolderRow(tile: tile,
                                        open: {
                                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { focused = tile.id }
                                        },
                                        onRename: { onRenameFolder(tile, $0) },
                                        onDelete: { onDeleteFolder(tile) },
                                        onDropNotes: onDropNotes.map { handler in
                                            { urls in handler(tile, urls) }
                                        })
                    }
                    if tiles.isEmpty {
                        Text("Nothing here yet.")
                            .font(Aurora.ui(14, .medium)).foregroundStyle(Aurora.ink3)
                            .padding(.vertical, 40)
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, 194).padding(.bottom, 160)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("\(tiles.count) folders")
                .font(Aurora.mono(10.5)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(Aurora.ink)
            Spacer()
            sortRail
        }
        .padding(.horizontal, 6).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Aurora.line).frame(height: 1) }
    }

    /// Sorting sits with the count it reorders, and stays quiet about it.
    private var sortRail: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Aurora.ink3)
                .accessibilityHidden(true)
            ForEach(AuroraSort.allCases, id: \.self) { k in
                Button(k.label.lowercased()) { withAnimation(.smooth(duration: 0.3)) { sort = k } }
                    .buttonStyle(.plain)
                    .font(Aurora.mono(10.5))
                    .tracking(0.6)
                    .foregroundStyle(sort == k ? Aurora.ink : Aurora.ink3.opacity(0.7))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(sort == k ? Aurora.accent : .clear)
                            .frame(height: 1).offset(y: 3)
                    }
            }
        }
    }

    private func notes(in tile: AuroraFolderTile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(tile.notes.count) notes in \(tile.name)")
                Spacer()
                Text("\(tile.captureCount) captures")
            }
            .font(Aurora.mono(10.5)).tracking(1.4).textCase(.uppercase)
            .foregroundStyle(Aurora.ink3)
            .padding(.horizontal, 6).padding(.bottom, 12)

            // A list view stays a list when you open a folder — dropping into a
            // grid halfway through was a change of mode nobody asked for.
            ForEach(Array(tile.notesByRecency.enumerated()), id: \.element.id) { i, note in
                AuroraNoteRow(note: note,
                              tint: tile.tints[i % tile.tints.count],
                              isNew: note.url == tile.freshNoteID,
                              open: { onOpenNote(note.url) },
                              onRename: { onRenameNote(note, $0) },
                              onDelete: { onDeleteNote(note) },
                              onRightClick: { point in onNoteRightClick?(note, point) })
            }

            if tile.notes.isEmpty {
                Text("Nothing in here yet.")
                    .font(Aurora.ui(14, .medium)).foregroundStyle(Aurora.ink3)
                    .padding(.vertical, 30)
            }
        }
    }
}


/// Swipe a row to the right and Delete appears behind it. Folders and notes
/// both use it, so the gesture means the same thing wherever you are in the
/// list. The first press arms; the second one does it.
struct AuroraSwipeRow<Content: View>: View {
    var enabled: Bool = true
    /// One press. Whether it actually happens is settled in a confirmation
    /// window, not by pressing the same red button twice.
    var onDelete: () -> Void
    @ViewBuilder var content: (_ revealed: Bool, _ close: @escaping () -> Void) -> Content

    @State private var offset: CGFloat = 0

    private let revealed: CGFloat = 116

    var body: some View {
        ZStack(alignment: .leading) {
            if offset > 2 {
                Button {
                    onDelete()
                    offset = 0
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash").font(.system(size: 13, weight: .bold))
                        Text("DELETE")
                            .font(Aurora.mono(9)).tracking(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: revealed - 14, height: 58)
                    .background(Aurora.danger, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(AuroraPressStyle())
                .padding(.leading, 2)
                .transition(.opacity)
            }

            content(offset > 0, close)
                .background(Aurora.ground.opacity(offset > 0 ? 0.92 : 0),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .offset(x: offset)
                // High priority, or the row's own button swallows the drag and
                // opens the thing mid-swipe.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            guard enabled else { return }
                            offset = max(0, min(revealed, v.translation.width))
                        }
                        .onEnded { v in
                            guard enabled else { return }
                            offset = v.translation.width > revealed / 2.2 ? revealed : 0
                        }
                )
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: offset)
    }

    private func close() {
        offset = 0
    }
}

/// A note as a row. Renames on a double-click, deletes on a swipe, and
/// right-clicks into the one thing neither gesture covers: filing it somewhere
/// else.
struct AuroraNoteRow: View {
    let note: CanvasNoteSnapshot
    var tint: Int
    /// The most recent note in its folder, when that was today.
    var isNew: Bool = false
    var open: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void
    var onRightClick: ((CGPoint) -> Void)? = nil

    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        AuroraSwipeRow(enabled: !editing, onDelete: onDelete) { revealed, close in
            row(revealed: revealed, close: close)
        }
        .draggable(note.url) {
            AuroraDragChip(title: note.title, tint: tint)
        }
    }

    private func row(revealed: Bool, close: @escaping () -> Void) -> some View {
        Button(action: { if revealed { close() } else if !editing { open() } }) {
            HStack(spacing: 18) {
                LinearGradient(colors: [Aurora.tint(tint), Aurora.tint(tint + 2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .saturation(1.35)
                    .brightness(-0.08)
                    .frame(width: 46, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if editing {
                            TextField("", text: $draft)
                                .textFieldStyle(.plain)
                                .font(Aurora.title(15.5))
                                .foregroundStyle(Aurora.ink)
                                .focused($nameFocused)
                                .frame(maxWidth: 260, alignment: .leading)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Aurora.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Aurora.focusRing, lineWidth: 2))
                                .onSubmit { onRename(draft); editing = false }
                                // Esc abandons the edit; anywhere else commits it.
                                .onExitCommand { draft = note.title; editing = false }
                        } else {
                            Text(note.title).font(Aurora.title(15.5)).foregroundStyle(Aurora.ink)
                        }
                        if isNew {
                            Text("NEW")
                                .font(Aurora.mono(8.5)).tracking(1)
                                .foregroundStyle(Aurora.onSolid)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Aurora.solid, in: Capsule())
                        }
                        if note.hasOrganizedNote {
                            Text("ORGANIZED")
                                .font(Aurora.mono(8.5)).tracking(1)
                                .foregroundStyle(Aurora.ink2)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Aurora.surface2, in: Capsule())
                        }
                    }
                    if !note.excerpt.isEmpty {
                        Text(note.excerpt)
                            .font(Aurora.ui(12.5, .regular)).foregroundStyle(Aurora.ink3).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 16) {
                    // The count is the one piece of colour in the row, so it
                    // carries the app's own green rather than another grey.
                    Text("\(note.captureCount) captures")
                        .font(Aurora.mono(9.5)).tracking(1)
                        .foregroundStyle(Aurora.accent)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Aurora.accentSoft, in: Capsule())
                    Text(note.createdAt.auroraRelative)
                        .font(Aurora.ui(12, .regular)).foregroundStyle(Aurora.ink3)
                        .frame(width: 70, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hover ? Aurora.focusRing : Aurora.ink3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 13)
            .contentShape(Rectangle())
            .background(hover ? Aurora.surface.opacity(0.55) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onTapGesture(count: 2) {
            draft = note.title
            editing = true
            nameFocused = true
        }
        .animation(.smooth(duration: 0.18), value: hover)
        .modifier(AuroraOptionalRightClick(action: onRightClick))
    }
}

/// A folder as a row. Swipe it to the right to uncover Delete, and rename it
/// in place with a double-click — the same gesture that renames one on the
/// canvas, so the list is not a lesser view of the same thing.
struct AuroraFolderRow: View {
    let tile: AuroraFolderTile
    var open: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void
    /// Notes dropped on this row. Returns true when they were filed.
    var onDropNotes: (([URL]) -> Bool)? = nil

    @State private var hover = false
    @State private var targeted = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        // Unfiled is not a folder anyone can delete, so its row never opens.
        AuroraSwipeRow(enabled: !tile.isUnfiled && !editing, onDelete: onDelete) { revealed, close in
            row(revealed: revealed, close: close)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Aurora.accentSoft.opacity(targeted ? 1 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Aurora.accent.opacity(targeted ? 0.8 : 0), lineWidth: 1.5)
                }
        }
        .animation(.smooth(duration: 0.16), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            onDropNotes?(urls) ?? false
        } isTargeted: { targeted = $0 && onDropNotes != nil }
    }

    private func row(revealed: Bool, close: @escaping () -> Void) -> some View {
        Button(action: { if revealed { close() } else if !editing { open() } }) {
            HStack(spacing: 18) {
                LinearGradient(colors: tile.tints.map { Aurora.tint($0) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 56, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    if editing {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .font(Aurora.title(18))
                            .foregroundStyle(Aurora.ink)
                            .focused($nameFocused)
                            .frame(maxWidth: 260, alignment: .leading)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Aurora.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Aurora.focusRing, lineWidth: 2))
                            .onSubmit { onRename(draft); editing = false }
                            // Esc abandons the edit; anywhere else commits it.
                            .onExitCommand { draft = tile.name; editing = false }
                    } else {
                        Text(tile.name).font(Aurora.title(18)).foregroundStyle(Aurora.ink)
                    }
                    Text(tile.notes.prefix(3).map(\.title).joined(separator: " · "))
                        .font(Aurora.ui(12.5, .regular)).foregroundStyle(Aurora.ink3).lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 18) {
                    Text("\(tile.captureCount) captures")
                        .font(Aurora.mono(9.5)).tracking(1.1)
                        .foregroundStyle(Aurora.accent)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Aurora.accentSoft, in: Capsule())
                    Text("\(tile.notes.count)")
                        .font(Aurora.ui(14, .semibold)).monospacedDigit()
                        .foregroundStyle(Aurora.ink2).frame(width: 22, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hover ? Aurora.focusRing : Aurora.ink3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 16)
            .contentShape(Rectangle())
            .background(hover ? Aurora.surface.opacity(0.55) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onTapGesture(count: 2) {
            guard !tile.isUnfiled else { return }
            draft = tile.name
            editing = true
            nameFocused = true
        }
        .animation(.smooth(duration: 0.18), value: hover)
    }
}

extension Date {
    var auroraRelative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: self, relativeTo: .now)
    }
}
