import SwiftUI

/// Searchable note picker (by name or folder path) reused wherever the user needs to choose
/// a save/move/forward destination: the "Saving to" pill, chunk move/forward, and the
/// capture-review popup.
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(NotefyFont.label)
                .tracking(1.1)
                .foregroundStyle(NotefyTheme.inkSoft)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(NotefyTheme.inkFaint)
                TextField("Search by name or folder…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(NotefyTheme.sandDeep, in: RoundedRectangle(cornerRadius: 8))

            if let onCreateNew {
                Button {
                    onCreateNew()
                    dismiss()
                } label: {
                    Label("New note", systemImage: "plus.circle")
                        .font(NotefyFont.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NotefyTheme.ink)
            }

            Divider()

            if results.isEmpty {
                Text(query.isEmpty ? "No notes yet." : "No notes match \u{201C}\(query)\u{201D}.")
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.inkFaint)
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
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(NotefyTheme.cardPaper)
        .onAppear { searchFocused = true }
    }

    private func row(for destination: NoteDestination) -> some View {
        let path = appState.folderPath(for: appState.folderID(for: destination.url))
        return VStack(alignment: .leading, spacing: 2) {
            Text(destination.title)
                .font(NotefyFont.body.weight(.medium))
                .foregroundStyle(NotefyTheme.ink)
                .lineLimit(1)
            if !path.isEmpty {
                Label(path, systemImage: "folder")
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
