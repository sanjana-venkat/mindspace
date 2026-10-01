import SwiftUI

/// A folder opened from the ring, as a list in a modal.
///
/// It sits over the orbit rather than replacing it, so the moon and the rest of
/// the ring are still there, dimmed, behind it. You are looking into one
/// folder, not leaving the library.
struct AuroraFolderSheet: View {
    let tile: AuroraFolderTile
    var onOpenNote: (CanvasNoteSnapshot) -> Void
    var onClose: () -> Void

    enum Order: String, CaseIterable, Identifiable {
        case recent, az, most
        var id: String { rawValue }
        var label: String {
            switch self {
            case .az: return "a-z"
            case .recent: return "recent"
            case .most: return "most captures"
            }
        }
    }

    @State private var filter = ""
    @State private var order: Order = .recent
    @State private var landed = false

    private var notes: [CanvasNoteSnapshot] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = needle.isEmpty ? tile.notes : tile.notes.filter {
            $0.title.lowercased().contains(needle) || $0.excerpt.lowercased().contains(needle)
        }
        switch order {
        case .az:
            return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent:
            return all.sorted { $0.createdAt > $1.createdAt }
        case .most:
            return all.sorted { ($0.captureCount, $0.createdAt) > ($1.captureCount, $1.createdAt) }
        }
    }

    private var tint: Color { Aurora.tint(tile.tints.first ?? 0) }

    var body: some View {
        ZStack {
            Color.black.opacity(landed ? 0.42 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                head
                toolbar
                Divider().overlay(Aurora.line).padding(.horizontal, 28)
                list
            }
            .frame(width: 780, height: 560)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Aurora.surface.opacity(0.8))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Aurora.line, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 48, y: 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .scaleEffect(landed ? 1 : 0.96)
            .opacity(landed ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { landed = true }
        }
    }

    private var head: some View {
        HStack(alignment: .center, spacing: 16) {
            AuroraFolderSwatch(tints: tile.tints, size: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(tile.name)
                    .font(Aurora.title(26))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text("\(tile.notes.count) \(tile.notes.count == 1 ? "NOTE" : "NOTES") · \(tile.captureCount) \(tile.captureCount == 1 ? "CAPTURE" : "CAPTURES")")
                        .font(Aurora.mono(10.5)).tracking(1.2)
                        .foregroundStyle(Aurora.ink3)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Aurora.ink2)
                    .frame(width: 32, height: 32)
                    .background(Aurora.surface2, in: Circle())
            }
            .buttonStyle(AuroraTapDown())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 18)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(Aurora.ink3)
                TextField("Filter \(tile.name)", text: $filter)
                    .textFieldStyle(.plain)
                    .font(Aurora.ui(14, .regular))
                    .foregroundStyle(Aurora.ink)
                if !filter.isEmpty {
                    Button { filter = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(Aurora.ink3)
                    }
                    .buttonStyle(AuroraTapDown())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Aurora.surface2.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
            .frame(maxWidth: 300)

            Spacer()

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Aurora.ink3)
            ForEach(Order.allCases) { o in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { order = o }
                } label: {
                    Text(o.label)
                        .font(Aurora.mono(12))
                        .foregroundStyle(order == o ? Aurora.ink : Aurora.ink3)
                        .padding(.bottom, 4)
                        .overlay(alignment: .bottom) {
                            if order == o {
                                Capsule().fill(Aurora.accent).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 14)
    }

    @ViewBuilder
    private var list: some View {
        if notes.isEmpty {
            VStack(spacing: 8) {
                Text(filter.isEmpty ? "Nothing in here yet." : "Nothing matches “\(filter)”.")
                    .font(Aurora.serif(19)).foregroundStyle(Aurora.ink2)
                if filter.isEmpty {
                    Text("Captures you make while this folder is the destination will land here.")
                        .font(Aurora.ui(13.5)).foregroundStyle(Aurora.ink3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(notes) { note in
                        row(note)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .scrollIndicators(.never)
        }
    }

    private func row(_ note: CanvasNoteSnapshot) -> some View {
        Button { onOpenNote(note) } label: {
            HStack(spacing: 16) {
                AuroraFolderSwatch(tints: Aurora.triad(seed: note.url.lastPathComponent), size: 50)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(note.title)
                            .font(Aurora.ui(16.5, .semibold))
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if note.hasOrganizedNote {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(Aurora.ink3)
                                .help("Has an organized write-up")
                        }
                    }
                    Text(note.excerpt.isEmpty ? "No text yet" : note.excerpt)
                        .font(Aurora.ui(13, .regular))
                        .foregroundStyle(Aurora.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                Text("\(note.captureCount) \(note.captureCount == 1 ? "capture" : "captures")")
                    .font(Aurora.mono(11.5)).tracking(0.6)
                    .foregroundStyle(Aurora.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Aurora.accent.opacity(0.14)))

                Text(stamp(note.createdAt))
                    .font(Aurora.mono(11))
                    .foregroundStyle(Aurora.ink3)
                    .frame(width: 74, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Aurora.ink3)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(AuroraHoverRow())
    }

    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return "today " + f.string(from: date)
        }
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "d MMM" : "d MMM yy"
        return f.string(from: date).lowercased()
    }
}

/// A folder's colours as a soft diagonal swatch: the same triad the ring uses,
/// so a folder looks like itself in both places.
struct AuroraFolderSwatch: View {
    let tints: [Int]
    var size: CGFloat = 46

    var body: some View {
        let colors = (tints.isEmpty ? [0, 1, 2] : tints).map { Aurora.tint($0) }
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

/// A row lights rather than shrinks. Scaling a full width row looks like the
/// list is breathing.
struct AuroraRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Aurora.surface2.opacity(0.7) : .clear)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }
}
