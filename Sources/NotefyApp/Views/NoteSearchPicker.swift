import SwiftUI

/// Searchable note picker (by name or folder path) reused wherever the user needs to choose
/// a save/move/forward destination: the "Saving to" pill, chunk move/forward, and the
/// capture-review popup.
///
/// Painted in the Aurora palette like the rest of the app — it used to keep the
/// old cream theme, which made it look like a different application had opened
/// on top of this one, and left it white while the app was dark.
struct NoteSearchPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let title: String
    var excluding: URL?
    let onSelect: (NoteDestination) -> Void
    var onCreateNew: (() -> Void)?

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [NoteDestination] {
        appState.searchNotes(query: query).filter { $0.url != excluding }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased())
                .font(Aurora.mono(9.5))
                .tracking(1.3)
                .foregroundStyle(Aurora.ink3)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Aurora.ink3)
                TextField("Search by name, folder or words inside", text: $query)
                    .textFieldStyle(.plain)
                    .font(Aurora.ui(13))
                    .foregroundStyle(Aurora.ink)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Aurora.surface2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Aurora.line, lineWidth: 1)
            }

            if let onCreateNew {
                Button {
                    onCreateNew()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("New note").font(Aurora.ui(13.5, .medium))
                    }
                    .foregroundStyle(Aurora.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AuroraHoverRow())
            }

            Rectangle().fill(Aurora.line).frame(height: 1)

            if results.isEmpty {
                Text(query.isEmpty ? "No notes yet." : "No notes match \u{201C}\(query)\u{201D}.")
                    .font(Aurora.ui(12.5))
                    .foregroundStyle(Aurora.ink3)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { destination in
                            Button {
                                onSelect(destination)
                                dismiss()
                            } label: {
                                row(for: destination)
                            }
                            .buttonStyle(AuroraHoverRow())
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(AuroraGround())
        .onAppear { searchFocused = true }
    }

    private func row(for destination: NoteDestination) -> some View {
        let path = appState.folderPath(for: appState.folderID(for: destination.url))
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Aurora.tint(Aurora.tintIndex(for: destination.title)))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.title)
                    .font(Aurora.ui(13.5, .medium))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                if !path.isEmpty {
                    Text(path)
                        .font(Aurora.ui(11.5))
                        .foregroundStyle(Aurora.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
