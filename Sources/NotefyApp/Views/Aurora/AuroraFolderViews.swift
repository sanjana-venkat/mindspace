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

    @State private var drag: CGSize = .zero
    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                let sheets = AuroraPile.sheets(for: tile.captureCount)
                ForEach(0..<sheets, id: \.self) { i in
                    let p = AuroraPile.place(i, of: sheets, plateWidth: 196, plateHeight: 118)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Aurora.tint(tile.tints[0] + i))
                        .frame(width: p.w, height: p.h)
                        .rotationEffect(.degrees(p.angle))
                        .offset(x: p.x, y: p.y)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Aurora.surface.opacity(0.82))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .frame(width: 196, height: 118)
                    .shadow(color: .black.opacity(hover ? 0.16 : 0.09),
                            radius: hover ? 26 : 14, y: hover ? 12 : 6)
                    .offset(y: hover ? -4 : 0)
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
                                .strokeBorder(Aurora.accent, lineWidth: 2))
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
        .opacity(dimmed ? 0.28 : 1)
        .saturation(dimmed ? 0.25 : 1)
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

    @State private var bloom = false
    @State private var hovered: URL?

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
                    .onTapGesture { onClose() }

                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    band(width: geo.size.width)
                        .frame(height: 300)
                        .opacity(bloom ? 1 : 0)
                    plate
                        .scaleEffect(bloom ? 1 : 0.92)
                        .opacity(bloom ? 1 : 0)
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
                        ForEach(Array(tile.notes.enumerated()), id: \.element.id) { i, note in
                            AuroraNoteCard(note: note, tint: tile.tints[i % tile.tints.count]) {
                                onOpenNote(note.url)
                            }
                            .offset(y: crest(i) + (hovered == note.url ? -16 : 0))
                            .rotationEffect(.degrees(tilt(i)), anchor: .bottom)
                            .scaleEffect(hovered == note.url ? 1.05 : 1)
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
                        .rotationEffect(.degrees(p.angle))
                        .offset(x: p.x, y: p.y)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
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
                Text(tile.name).font(Aurora.display(22)).foregroundStyle(Aurora.ink)
                Text("\(tile.notes.count) notes · \(tile.captureCount) captures")
                    .font(Aurora.ui(12, .medium)).foregroundStyle(Aurora.ink2)
            }
        }
    }
}

/// A note as a card: its title, the first line of what's in it, and how much.
struct AuroraNoteCard: View {
    let note: CanvasNoteSnapshot
    var tint: Int
    var open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Aurora.tint(tint).opacity(0.55), Aurora.tint(tint).opacity(0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if note.hasOrganizedNote {
                        Text("ORGANIZED")
                            .font(Aurora.mono(8.5)).tracking(1)
                            .foregroundStyle(Aurora.ink2)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Aurora.surface.opacity(0.8), in: Capsule())
                            .padding(9)
                    }
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
                .strokeBorder(hover ? Aurora.accent : Aurora.line, lineWidth: hover ? 1.6 : 1))
            .shadow(color: .black.opacity(hover ? 0.20 : 0.12), radius: hover ? 30 : 18, y: hover ? 14 : 8)
            .scaleEffect(hover ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.smooth(duration: 0.2), value: hover)
    }
}

/// The same library as a sorted list; a folder opens into its notes inline.
struct AuroraFeedView: View {
    let tiles: [AuroraFolderTile]
    var query: String
    @Binding var sort: AuroraSort
    @Binding var focused: String?
    var onOpenNote: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let id = focused, let tile = tiles.first(where: { $0.id == id }) {
                    notes(in: tile)
                } else {
                    header
                    ForEach(tiles) { tile in
                        AuroraFolderRow(tile: tile) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { focused = tile.id }
                        }
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
            .padding(.top, 150).padding(.bottom, 160)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("\(tiles.count) folders")
                .font(Aurora.mono(10.5)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(Aurora.ink3)
            Spacer()
            sortRail
            Text("\(tiles.reduce(0) { $0 + $1.notes.count }) notes")
                .font(Aurora.mono(10.5)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(Aurora.ink3)
        }
        .padding(.horizontal, 6).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Aurora.line).frame(height: 1) }
    }

    /// Sorting sits with the count it reorders, and stays quiet about it.
    private var sortRail: some View {
        HStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(tile.notes.count) notes in \(tile.name)")
                Spacer()
                Text("\(tile.captureCount) captures")
            }
            .font(Aurora.mono(10.5)).tracking(1.4).textCase(.uppercase)
            .foregroundStyle(Aurora.ink3)
            .padding(.horizontal, 6).padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Aurora.line).frame(height: 1) }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 16)], spacing: 16) {
                ForEach(Array(tile.notes.enumerated()), id: \.element.id) { i, note in
                    AuroraNoteCard(note: note, tint: tile.tints[i % tile.tints.count]) {
                        onOpenNote(note.url)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct AuroraFolderRow: View {
    let tile: AuroraFolderTile
    var open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 18) {
                LinearGradient(colors: tile.tints.map { Aurora.tint($0).opacity(0.9) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 56, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.name).font(Aurora.title(18)).foregroundStyle(Aurora.ink)
                    Text(tile.notes.prefix(3).map(\.title).joined(separator: " · "))
                        .font(Aurora.ui(12.5, .regular)).foregroundStyle(Aurora.ink3).lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 18) {
                    Text("\(tile.captureCount) captures")
                        .font(Aurora.mono(9.5)).tracking(1.1)
                        .foregroundStyle(Aurora.ink2)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Aurora.surface2, in: Capsule())
                    Text("\(tile.notes.count)")
                        .font(Aurora.ui(14, .semibold)).monospacedDigit()
                        .foregroundStyle(Aurora.ink2).frame(width: 22, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hover ? Aurora.accent : Aurora.ink3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 16)
            .contentShape(Rectangle())
            .background(hover ? Aurora.surface.opacity(0.55) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Aurora.line).frame(height: 1).padding(.horizontal, 6)
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
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
