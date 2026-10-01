import SwiftUI

/// A folder opened from the ring, beside it rather than on top of it.
///
/// The ring slides left and stays sharp, with the opened arc still lit, so you
/// can see which slice of your mind you are reading and click another arc to
/// switch. Nothing here is boxed: the title, the sort and the notes float on
/// the same night as the moon. A card around them would say "this is a
/// separate place", and it isn't.
struct AuroraFolderPanel: View {
    let tile: AuroraFolderTile
    var onOpenNote: (CanvasNoteSnapshot) -> Void
    var onClose: () -> Void

    enum Order: String, CaseIterable, Identifiable {
        case recent, az, most
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: return "recent"
            case .az: return "a-z"
            case .most: return "most captures"
            }
        }
    }

    @State private var order: Order = .recent
    @State private var hovered: URL?

    /// The share of the window the panel takes. The ring keeps the rest.
    static let widthFraction: CGFloat = 0.44

    /// The offscreen renderer cannot draw inside a ScrollView, so while it
    /// runs the rows are laid out flat. Always false in a real window.
    static var drawsUnscrolled = false

    private var notes: [CanvasNoteSnapshot] {
        switch order {
        case .recent:
            return tile.notes.sorted { $0.createdAt > $1.createdAt }
        case .az:
            return tile.notes.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .most:
            return tile.notes.sorted { ($0.captureCount, $0.createdAt) > ($1.captureCount, $1.createdAt) }
        }
    }

    private var tint: Color { Aurora.tint(tile.tints.first ?? 0) }

    var body: some View {
        GeometryReader { geo in
            let width = min(max(geo.size.width * Self.widthFraction, 380), 600)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(width: width)
                    .background(alignment: .trailing) {
                        // Not a panel, a fall of shade, so the words stay
                        // readable over whatever the aurora is doing behind.
                        LinearGradient(
                            stops: [
                                .init(color: Aurora.ground.opacity(0), location: 0),
                                .init(color: Aurora.ground.opacity(0.78), location: 0.22),
                                .init(color: Aurora.ground.opacity(0.9), location: 1)
                            ],
                            startPoint: .leading, endPoint: .trailing)
                        .frame(width: width + 120)
                        .allowsHitTesting(false)
                    }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Aurora.ink2)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(AuroraTapDown())
                .help("Close (Esc)")
            }
            .padding(.top, 96)

            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(meta)
                    .font(Aurora.mono(11)).tracking(1.2)
                    .foregroundStyle(Aurora.ink3)
            }
            .padding(.top, 4)

            Text(tile.name)
                .font(Aurora.display(40))
                .foregroundStyle(Aurora.ink)
                .lineLimit(2)
                .padding(.top, 10)

            sortRow
                .padding(.top, 22)
                .padding(.bottom, 18)

            if notes.isEmpty {
                Text("Nothing saved here yet. Captures land in a folder while it is the destination.")
                    .font(Aurora.serif(17))
                    .foregroundStyle(Aurora.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                Spacer()
            } else if Self.drawsUnscrolled {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(notes) { note in row(note) }
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(notes) { note in row(note) }
                    }
                    .padding(.top, 8)
                    // Room for the last note to scroll clear of the button in
                    // the bottom corner.
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.never)
                // Fade the list into the dark at its foot instead of cutting it.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: 0.88),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 44)
    }

    private var meta: String {
        let n = tile.notes.count, c = tile.captureCount
        return "\(n) \(n == 1 ? "NOTE" : "NOTES")  ·  \(c) \(c == 1 ? "CAPTURE" : "CAPTURES")"
    }

    private var sortRow: some View {
        HStack(spacing: 18) {
            ForEach(Order.allCases) { o in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { order = o }
                } label: {
                    Text(o.label)
                        .font(Aurora.mono(12))
                        .foregroundStyle(order == o ? Aurora.ink : Aurora.ink3)
                        .padding(.bottom, 5)
                        .overlay(alignment: .bottom) {
                            if order == o {
                                Capsule().fill(Aurora.accent).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A note is its words: a title, a line of what is in it, and when. No
    /// icon, no card, no chevron. The whole row is the target.
    private func row(_ note: CanvasNoteSnapshot) -> some View {
        let lit = hovered == note.url
        return Button { onOpenNote(note) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title)
                    .font(Aurora.serif(21))
                    .foregroundStyle(lit ? tint : Aurora.ink)
                    .lineLimit(2)
                if !note.excerpt.isEmpty {
                    Text(note.excerpt)
                        .font(Aurora.ui(13.5, .regular))
                        .foregroundStyle(Aurora.ink3)
                        .lineLimit(2)
                }
                Text(stamp(note))
                    .font(Aurora.mono(10.5)).tracking(0.8)
                    .foregroundStyle(Aurora.ink3.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? note.url : (hovered == note.url ? nil : hovered) }
        .animation(.smooth(duration: 0.16), value: lit)
    }

    private func stamp(_ note: CanvasNoteSnapshot) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(note.createdAt) ? "'TODAY' HH:mm" : "d MMM"
        let c = note.captureCount
        return "\(f.string(from: note.createdAt).uppercased())  ·  \(c) \(c == 1 ? "CAPTURE" : "CAPTURES")"
    }
}
