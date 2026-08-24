import SwiftUI

private enum LibraryTab: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case folders = "Folders"
    var id: String { rawValue }
}

/// The Library: browse every note either by recency (default landing view) or grouped
/// into folders. Opening a note switches back to the live dashboard editor.
struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: LibraryTab = .recent
    @State private var expandedFolders: Set<UUID> = []

    let openNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THE ARCHIVE")
                        .font(NotefyFont.label).tracking(1.3).foregroundStyle(NotefyTheme.inkSoft)
                    Text("Your library")
                        .font(NotefyFont.pageTitle)
                        .foregroundStyle(NotefyTheme.ink)
                }
                Spacer()
                tabPicker
            }

            switch tab {
            case .recent: recentList
            case .folders: folderBrowser
            }
        }
        .padding(42)
        .onAppear { appState.refreshHistory() }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(LibraryTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue.uppercased())
                        .font(NotefyFont.label).tracking(0.8)
                        .foregroundStyle(tab == item ? NotefyTheme.ink : NotefyTheme.inkFaint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(tab == item ? NotefyTheme.cardPaper : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(NotefyTheme.sandDeep, in: Capsule())
    }

    // MARK: - Recent (default landing view: sorted by last-opened)

    private var recentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(appState.allNoteDestinationsByRecency) { destination in
                    noteCard(destination)
                }
                if appState.allNoteDestinationsByRecency.isEmpty {
                    emptyState
                }
            }
        }
    }

    // MARK: - Folders (hierarchical)

    private var folderBrowser: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(appState.folders(withParent: nil)) { folder in
                    folderSection(folder, depth: 0)
                }
                let unfiled = appState.unfiledNoteDestinations
                if !unfiled.isEmpty {
                    Text("UNFILED")
                        .font(NotefyFont.label).tracking(1.2)
                        .foregroundStyle(NotefyTheme.inkSoft)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(unfiled) { destination in
                        noteCard(destination)
                    }
                }
                if appState.folders(withParent: nil).isEmpty && unfiled.isEmpty {
                    emptyState
                }
            }
        }
    }

    private func folderSection(_ folder: NoteFolder, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if expandedFolders.contains(folder.id) {
                        expandedFolders.remove(folder.id)
                    } else {
                        expandedFolders.insert(folder.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: expandedFolders.contains(folder.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NotefyTheme.inkFaint)
                        Image(systemName: "folder.fill")
                            .foregroundStyle(NotefyTheme.inkSoft)
                        Text(folder.name)
                            .font(NotefyFont.heading)
                            .foregroundStyle(NotefyTheme.ink)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 18)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expandedFolders.contains(folder.id) {
                    ForEach(appState.folders(withParent: folder.id)) { child in
                        folderSection(child, depth: depth + 1)
                    }
                    ForEach(appState.notes(inFolder: folder.id)) { destination in
                        noteCard(destination)
                            .padding(.leading, CGFloat(depth + 1) * 18)
                    }
                }
            }
        )
    }

    private func noteCard(_ destination: NoteDestination) -> some View {
        let isActive = destination.url == appState.activeNoteURL
        return Button {
            appState.openNote(destination.url)
            openNote()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isActive ? "paperclip" : "doc.text")
                    .foregroundStyle(isActive ? NotefyTheme.marginRose : NotefyTheme.inkFaint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(destination.title)
                            .font(NotefyFont.heading)
                            .foregroundStyle(NotefyTheme.ink)
                            .lineLimit(1)
                        if appState.isPinned(destination.url) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(NotefyTheme.marginRose)
                        }
                    }
                    Text(modifiedDate(destination.url).uppercased())
                        .font(NotefyFont.caption).tracking(0.7)
                        .foregroundStyle(NotefyTheme.inkFaint)
                }
                Spacer()
            }
            .padding(13)
            .background(isActive ? NotefyTheme.pebbleTan.opacity(0.28) : NotefyTheme.cardPaper.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 520, alignment: .leading)
        .contextMenu {
            Button(appState.isPinned(destination.url) ? "Unpin" : "Pin") {
                appState.togglePinned(destination.url)
            }
            Divider()
            Button("Delete note", role: .destructive) {
                appState.deleteNote(destination.url)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 20) {
            ZStack {
                PebbleShape().fill(NotefyTheme.pebbleMauve.opacity(0.7))
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .light))
            }
            .frame(width: 100, height: 80)
            Text("No notes yet.")
                .font(NotefyFont.body)
                .foregroundStyle(NotefyTheme.inkSoft)
        }
        .padding(42)
    }

    private func modifiedDate(_ file: URL) -> String {
        DateFormatter.localizedString(from: appState.lastOpened(file), dateStyle: .medium, timeStyle: .short)
    }
}
