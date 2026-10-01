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
    var onRenameFolder: (String) -> Void = { _ in }
    var onRenameNote: (CanvasNoteSnapshot, String) -> Void = { _, _ in }
    /// True while a title is being edited, so the window's Esc cancels the
    /// edit rather than closing the folder.
    @Binding var renaming: Bool
    /// Bumped by the window when Esc is pressed mid-edit.
    var cancelRenameTick: Int = 0

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

    /// What is being renamed: the folder, or one note.
    private enum Editing: Equatable { case folder, note(URL) }
    @State private var editing: Editing?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

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
        content(in: nil)
            .onChange(of: fieldFocused) { _, focused in
                if !focused, editing != nil { commit() }
            }
            .onChange(of: cancelRenameTick) { _, _ in cancel() }
            .onDisappear { if editing != nil { cancel() } }
    }

    @ViewBuilder
    private func content(in _: Void?) -> some View {
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

            Group {
                if editing == .folder {
                    renameField(font: Aurora.display(40))
                } else {
                    Text(tile.name)
                        .font(Aurora.display(40))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(2)
                        .onTapGesture(count: 2) { begin(.folder, from: tile.name) }
                        .help("Double-click to rename")
                }
            }
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
    /// icon, no card, no chevron.
    ///
    /// The title renames on a double-click, so a single click on it waits the
    /// double-click interval before opening. The rest of the row opens at once.
    private func row(_ note: CanvasNoteSnapshot) -> some View {
        let lit = hovered == note.url
        let isEditing = editing == .note(note.url)
        return VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                renameField(font: Aurora.serif(21))
            } else {
                Text(note.title)
                    .font(Aurora.serif(21))
                    .foregroundStyle(lit ? tint : Aurora.ink)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { begin(.note(note.url), from: note.title) }
                    .onTapGesture { onOpenNote(note) }
                    .help("Double-click to rename")
            }
            VStack(alignment: .leading, spacing: 6) {
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
            .onTapGesture { if !isEditing { onOpenNote(note) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovered = $0 ? note.url : (hovered == note.url ? nil : hovered) }
        .animation(.smooth(duration: 0.16), value: lit)
    }

    // MARK: renaming

    private func renameField(font: Font) -> some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Aurora.ink)
            .focused($fieldFocused)
            .onSubmit(commit)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(tint).frame(height: 1.5)
            }
    }

    private func begin(_ what: Editing, from current: String) {
        draft = current
        editing = what
        renaming = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    /// Saves on Return or when the field loses focus, like Finder. An empty
    /// name keeps the old one rather than erasing it.
    private func commit() {
        guard let what = editing else { return }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = nil
        renaming = false
        guard !name.isEmpty else { return }
        switch what {
        case .folder:
            if name != tile.name { onRenameFolder(name) }
        case .note(let url):
            if let note = tile.notes.first(where: { $0.url == url }), name != note.title {
                onRenameNote(note, name)
            }
        }
    }

    private func cancel() {
        editing = nil
        renaming = false
    }

    private func stamp(_ note: CanvasNoteSnapshot) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(note.createdAt) ? "'TODAY' HH:mm" : "d MMM"
        let c = note.captureCount
        return "\(f.string(from: note.createdAt).uppercased())  ·  \(c) \(c == 1 ? "CAPTURE" : "CAPTURES")"
    }
}
