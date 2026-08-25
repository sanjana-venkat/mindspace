import SwiftUI

enum NotefySection: String, CaseIterable, Identifiable {
    case dashboard = "Current note"
    case history = "Library"
    case settings = "Settings"
    var id: String { rawValue }
}

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: NotefySection = .dashboard
    @State private var sidebarCollapsed = false

    var body: some View {
        Group {
            if appState.isShowingPermissionOnboarding {
                PermissionOnboardingView(
                    permissionCenter: appState.permissionCenter,
                    onFinished: appState.finishPermissionOnboarding
                )
            } else {
                GeometryReader { proxy in
                    // Extra top clearance: with the title bar hidden, the
                    // traffic lights float directly over our own content, so
                    // the sidebar and dashboard both need real room to clear them.
                    let topInset: CGFloat = 76
                    let contentHeight = proxy.size.height - topInset - 24
                    HStack(spacing: Stoneink.sp5) {
                        Sidebar(selection: $selection, collapsed: $sidebarCollapsed, proxyHeight: contentHeight)
                        Group {
                            switch selection {
                            case .dashboard: DashboardView()
                            case .history: HistoryView(openNote: { selection = .dashboard })
                            case .settings: SettingsView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, topInset)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        // The bed: the ground slab. Darker than the cards resting on it —
        // a worn work surface, not a light "airy" background. This
        // inversion is the single most load-bearing decision in the system.
        .background(Stoneink.surfaceBed)
        .overlay(GrogOverlay().allowsHitTesting(false))
        .preferredColorScheme(.light)
    }
}

/// Collapsible sidebar: Pinned notes, Projects (nested folders), and Recents.
/// The sidebar itself is a slab resting on the bed.
private struct Sidebar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: NotefySection
    @Binding var collapsed: Bool
    let proxyHeight: CGFloat

    @State private var expandedFolders: Set<UUID> = []
    @State private var renamingNote: NoteDestination?
    @State private var renameText = ""
    @State private var showRenameNote = false
    @State private var renamingFolder: NoteFolder?
    @State private var showRenameFolder = false
    @State private var showNewFolder = false
    @State private var newFolderParent: UUID?
    @State private var newFolderName = ""
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if !collapsed {
                searchBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                            defaultSections
                        } else {
                            searchResults
                        }
                    }
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity)
                .clipped()
            } else {
                collapsedRail
            }

            footer
        }
        .padding(20)
        .frame(width: collapsed ? 64 : 280, height: proxyHeight, alignment: .top)
        .clipped()
        .background(Stoneink.surfaceSlab)
        .overlay(GrogOverlay().allowsHitTesting(false))
        .clipShape(ThrownRect.lg)
        .depthSlab(ThrownRect.lg)
        .animation(.easeInOut(duration: 0.18), value: collapsed)
        .alert("Rename note", isPresented: $showRenameNote) {
            TextField("Note name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renamingNote { appState.renameNote(renamingNote.url, to: renameText) }
            }
        }
        .alert("Rename folder", isPresented: $showRenameFolder) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renamingFolder { appState.renameFolder(renamingFolder.id, to: renameText) }
            }
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                appState.createFolder(name: newFolderName, parentID: newFolderParent)
                newFolderName = ""
            }
        }
    }

    private var recentUnpinned: [NoteDestination] {
        appState.allNoteDestinationsByRecency.filter { !appState.isPinned($0.url) }
    }

    /// Collapsed rail: quiet and icon-only.
    private var collapsedRail: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(appState.pinnedNoteDestinations.prefix(6)) { destination in
                    collapsedNoteBadge(destination)
                }
                if !appState.pinnedNoteDestinations.isEmpty {
                    Rectangle().fill(Stoneink.score).frame(height: 1).padding(.vertical, 2)
                }
                ForEach(recentUnpinned.prefix(6)) { destination in
                    collapsedNoteBadge(destination)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func collapsedNoteBadge(_ destination: NoteDestination) -> some View {
        let isActive = destination.url == appState.activeNoteURL
        Button {
            appState.openNote(destination.url)
            selection = .dashboard
        } label: {
            Image(systemName: isActive ? "doc.text.fill" : "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Stoneink.cobalt600 : Stoneink.clay500)
                .frame(width: 36, height: 36)
                .background(isActive ? Stoneink.surfacePress : Color.clear)
                .clipShape(ThrownRect.sm)
                .modifier(ConditionalPress(isActive: isActive))
        }
        .buttonStyle(.plain)
        .help(destination.title)
    }

    @ViewBuilder
    private var defaultSections: some View {
        if !appState.pinnedNoteDestinations.isEmpty {
            sectionLabel("Pinned")
            ForEach(appState.pinnedNoteDestinations) { destination in
                noteRow(destination, depth: 0)
            }
        }

        HStack {
            sectionLabel("Projects")
            Spacer()
            Button {
                newFolderParent = nil
                newFolderName = ""
                showNewFolder = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Stoneink.clay500)
            }
            .buttonStyle(.plain)
        }
        ForEach(appState.folders(withParent: nil)) { folder in
            folderRow(folder, depth: 0)
        }

        sectionLabel("Recents")
        ForEach(recentUnpinned.prefix(8)) { destination in
            noteRow(destination, depth: 0)
        }
        Button {
            selection = .history
        } label: {
            Text("See all in library")
                .font(StoneFont.markMedium())
                .tracking(Stoneink.trMark * 11)
                .foregroundStyle(Stoneink.textMuted)
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = appState.searchNotes(query: searchQuery)
        sectionLabel("\(results.count) match\(results.count == 1 ? "" : "es")")
        ForEach(results) { destination in
            noteRow(destination, depth: 0)
        }
        if results.isEmpty {
            Text("No notes match \u{201C}\(searchQuery)\u{201D}.")
                .font(StoneFont.body())
                .foregroundStyle(Stoneink.textMuted)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !collapsed {
                HStack(spacing: 12) {
                    StoneinkMark()
                        .frame(width: 20, height: 20)
                    Text("Noted")
                        .font(StoneFont.title())
                        .foregroundStyle(Stoneink.textPrimary)
                }
                Spacer()
                Button {
                    appState.createNewNote()
                    selection = .dashboard
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Stoneink.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Stoneink.surfaceSlab)
                        .clipShape(ThrownRect.sm)
                        .depthSlab(ThrownRect.sm)
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            Button {
                collapsed.toggle()
            } label: {
                Image(systemName: collapsed ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 15))
                    .foregroundStyle(Stoneink.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// A well cut into the clay — inputs and search are pressed, never raised.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Stoneink.clay500)
            TextField("Search notes", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(StoneFont.body())
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Stoneink.surfacePress)
        .clipShape(ThrownRect.press)
        .depthPress(ThrownRect.press)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(StoneFont.markMedium())
            .tracking(Stoneink.trMark * 11)
            .foregroundStyle(Stoneink.textMuted)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func folderRow(_ folder: NoteFolder, depth: Int) -> AnyView {
        AnyView(folderRowContent(folder, depth: depth))
    }

    @ViewBuilder
    private func folderRowContent(_ folder: NoteFolder, depth: Int) -> some View {
        let isExpanded = expandedFolders.contains(folder.id)
        let noteCount = appState.notes(inFolder: folder.id).count
        Button {
            if isExpanded { expandedFolders.remove(folder.id) } else { expandedFolders.insert(folder.id) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(StoneFont.bodyMedium())
                        .foregroundStyle(Stoneink.textPrimary)
                        .lineLimit(1)
                    Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                        .font(StoneFont.mark())
                        .tracking(Stoneink.trMark * 11)
                        .foregroundStyle(Stoneink.textMuted)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Stoneink.clay500)
            }
            .padding(.leading, CGFloat(depth) * 14 + 10)
            .padding(.trailing, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(isExpanded ? Stoneink.surfaceSlab : Color.clear)
            .clipShape(ThrownRect.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("New note here") {
                appState.createNewNote(inFolder: folder.id)
                selection = .dashboard
            }
            Button("New subfolder…") {
                newFolderParent = folder.id
                newFolderName = ""
                showNewFolder = true
            }
            Button("Rename…") {
                renamingFolder = folder
                renameText = folder.name
                showRenameFolder = true
            }
            Divider()
            Button("Delete folder", role: .destructive) {
                appState.deleteFolder(folder.id)
            }
        }

        if isExpanded {
            ForEach(appState.folders(withParent: folder.id)) { child in
                folderRow(child, depth: depth + 1)
            }
            ForEach(appState.notes(inFolder: folder.id)) { destination in
                noteRow(destination, depth: depth + 1)
            }
        }
    }

    /// Active: cobalt bloom fill + 2px cobalt rule on the left edge —
    /// the selected-state grammar used everywhere in this system.
    private func noteRow(_ destination: NoteDestination, depth: Int) -> some View {
        let isActive = destination.url == appState.activeNoteURL
        return Button {
            appState.openNote(destination.url)
            selection = .dashboard
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(StoneFont.bodyMedium())
                        .foregroundStyle(Stoneink.textPrimary)
                        .lineLimit(1)
                    Text(DateFormatter.localizedString(from: appState.lastOpened(destination.url), dateStyle: .none, timeStyle: .short))
                        .font(StoneFont.mark())
                        .tracking(Stoneink.trMark * 11)
                        .foregroundStyle(Stoneink.textMuted)
                }
                Spacer()
                if appState.isPinned(destination.url) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Stoneink.amber600)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Stoneink.clay500)
            }
            .padding(.leading, CGFloat(depth) * 14 + 10)
            .padding(.trailing, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(isActive ? Stoneink.cobalt050 : Color.clear)
            .clipShape(Capsule())
            .overlay(alignment: .leading) {
                if isActive {
                    Capsule().fill(Stoneink.cobalt600).frame(width: 2).padding(.vertical, 6).padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(appState.isPinned(destination.url) ? "Unpin" : "Pin") {
                appState.togglePinned(destination.url)
            }
            Button("Rename…") {
                renamingNote = destination
                renameText = destination.title
                showRenameNote = true
            }
            Menu("Move to folder") {
                Button("Unfiled") { appState.moveNote(destination.url, toFolder: nil) }
                ForEach(allFoldersFlattened, id: \.id) { entry in
                    Button(entry.path) { appState.moveNote(destination.url, toFolder: entry.id) }
                }
            }
            Divider()
            Button("Delete note", role: .destructive) {
                appState.deleteNote(destination.url)
            }
        }
    }

    private var allFoldersFlattened: [(id: UUID, path: String)] {
        func walk(_ parent: UUID?) -> [(id: UUID, path: String)] {
            appState.folders(withParent: parent).flatMap { folder -> [(id: UUID, path: String)] in
                [(folder.id, appState.folderPath(for: folder.id))] + walk(folder.id)
            }
        }
        return walk(nil)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: collapsed ? 12 : 10) {
            if collapsed {
                Button {
                    selection = .settings
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Stoneink.textSecondary)
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Text("Storage used")
                        .font(StoneFont.body())
                        .foregroundStyle(Stoneink.textSecondary)
                    Spacer()
                    Text("\(appState.storageUsedPercent)%")
                        .font(StoneFont.mark())
                        .tracking(Stoneink.trMark * 11)
                        .foregroundStyle(Stoneink.textMuted)
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(Stoneink.surfacePress)
                        .depthStamp(Capsule())
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Stoneink.cobalt600)
                                .frame(width: max(6, proxy.size.width * CGFloat(appState.storageUsedPercent) / 100))
                        }
                }
                .frame(height: 6)

                HStack {
                    HStack(spacing: 10) {
                        Text(userInitials)
                            .font(StoneFont.markMedium())
                            .foregroundStyle(Stoneink.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(Stoneink.surfaceSlab)
                            .clipShape(Circle())
                            .depthSlab(Circle())
                        Text(appState.fullUserDisplayName)
                            .font(StoneFont.bodyMedium())
                            .foregroundStyle(Stoneink.textPrimary)
                    }
                    Spacer()
                    Button {
                        selection = .settings
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundStyle(Stoneink.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Stoneink.surfaceSlab)
                            .clipShape(ThrownRect.sm)
                            .depthSlab(ThrownRect.sm)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, collapsed ? 0 : 12)
        .scoreLineTop2(hidden: collapsed)
    }

    private var userInitials: String {
        appState.fullUserDisplayName
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct ConditionalPress: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive {
            content.depthPress(ThrownRect.sm)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func scoreLineTop2(hidden: Bool) -> some View {
        if hidden {
            self
        } else {
            self.overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Stoneink.score).frame(height: 1)
                    Rectangle().fill(Color.stoneEdgeLight).frame(height: 1)
                }
            }
        }
    }
}

/// The grog overlay — porcelain tooth. A stable procedural noise field,
/// multiplied at very low opacity. Applied to the bed and every slab;
/// never to a translucent/blurred surface (there are none in this system).
struct GrogOverlay: View {
    var opacity: Double = Stoneink.grogOpacity
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 11)
            let count = Int(size.width * size.height / 7)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(rect), with: .color(.black))
            }
        }
        .blendMode(.multiply)
        .opacity(opacity)
    }
}
