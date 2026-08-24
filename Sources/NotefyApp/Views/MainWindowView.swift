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
                    let contentHeight = proxy.size.height - 48
                    ZStack(alignment: .topLeading) {
                        // The ambient field belongs to the window, not the
                        // dashboard rectangle, so the gradients continue behind
                        // both the sidebar and the main glass workspace.
                        Circle()
                            .fill(NotefyTheme.blobPeriwinkle)
                            .frame(width: 720, height: 720)
                            .blur(radius: 100)
                            .offset(x: 40, y: -280)
                        Circle()
                            .fill(NotefyTheme.blobAmber)
                            .frame(width: 760, height: 760)
                            .blur(radius: 120)
                            .offset(x: -460, y: 300)
                        Circle()
                            .fill(NotefyTheme.blobRose)
                            .frame(width: 820, height: 820)
                            .blur(radius: 140)
                            .offset(x: 480, y: 340)

                        HStack(spacing: 24) {
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(NotefyTheme.sand)
        .clipShape(FoldedRectangle(cornerRadius: 0, foldSize: NotefyTheme.foldSize))
        .overlay(alignment: .topTrailing) { FoldAccent() }
        .preferredColorScheme(.light)
    }
}

/// Collapsible sidebar: Pinned notes, Projects (nested folders), and Recents —
/// mirroring the reference ChatGPT-style layout.
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
                    VStack(alignment: .leading, spacing: 8) {
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
        .background(NotefyTheme.sandDeep)
        .grain()
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(NotefyTheme.glassBorder, lineWidth: 1))
        .shadow(color: NotefyTheme.panelShadowColor, radius: 24, x: 0, y: 12)
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

    /// Collapsed rail: keep this quiet and icon-only. The expanded sidebar
    /// remains the place for note names; abbreviations are not meaningful at
    /// this width and compete with the capture workspace.
    private var collapsedRail: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(appState.pinnedNoteDestinations.prefix(6)) { destination in
                    collapsedNoteBadge(destination)
                }
                if !appState.pinnedNoteDestinations.isEmpty {
                    Rectangle().fill(NotefyTheme.glassBorder).frame(height: 1).padding(.vertical, 2)
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
            if isActive {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NotefyTheme.inkStrong)
                    .frame(width: 36, height: 36)
                    .background(NotefyTheme.sandDeep, in: Circle())
                    .deboss(cornerRadius: 18)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NotefyTheme.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(NotefyTheme.sandDeep, in: Circle())
                    .emboss()
            }
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
                    .foregroundStyle(NotefyTheme.inkFaint)
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
            Text("SEE ALL IN LIBRARY")
                .font(NotefyFont.label)
                .tracking(1)
                .foregroundStyle(NotefyTheme.inkFaint)
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
                .font(NotefyFont.caption)
                .foregroundStyle(NotefyTheme.inkFaint)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !collapsed {
                HStack(spacing: 14) {
                    NotedMark(tint: NotefyTheme.ink, knockout: NotefyTheme.sandDeep)
                        .frame(width: 20, height: 20)
                    Text("Noted")
                        .font(NotefyFont.sectionTitle)
                        .tracking(-0.4)
                        .foregroundStyle(NotefyTheme.ink)
                }
                Spacer()
                Button {
                    appState.createNewNote()
                    selection = .dashboard
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotefyTheme.ink)
                        .padding(8)
                        .background(NotefyTheme.sandDeep, in: Circle())
                        .emboss()
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            Button {
                collapsed.toggle()
            } label: {
                Image(systemName: collapsed ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 15))
                    .foregroundStyle(NotefyTheme.inkSoft)
            }
            .buttonStyle(.plain)
        }
    }

    /// Search receives input, so per the elevation grammar it's debossed, not
    /// raised — with the hairline glass stroke carried over from the source frame.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(NotefyTheme.inkFaint)
            TextField("Search notes...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(NotefyFont.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NotefyTheme.sandDeep)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NotefyTheme.glassBorder, lineWidth: 1))
        .debossSoft(cornerRadius: 12)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(NotefyFont.label)
            .tracking(1.2)
            .foregroundStyle(NotefyTheme.inkFaint)
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
                        .font(NotefyFont.bodyMedium)
                        .foregroundStyle(NotefyTheme.ink)
                        .lineLimit(1)
                    Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                        .font(NotefyFont.label)
                        .tracking(1)
                        .foregroundStyle(NotefyTheme.inkFaint)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotefyTheme.inkFaint)
            }
            .padding(.leading, CGFloat(depth) * 14 + 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                if isExpanded {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NotefyTheme.sandDeep)
                        .deboss(cornerRadius: 12)
                }
            }
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

    private func noteRow(_ destination: NoteDestination, depth: Int) -> some View {
        let isActive = destination.url == appState.activeNoteURL
        return Button {
            appState.openNote(destination.url)
            selection = .dashboard
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(isActive ? NotefyFont.heading : NotefyFont.bodyMedium)
                        .foregroundStyle(NotefyTheme.ink)
                        .lineLimit(1)
                    Text(DateFormatter.localizedString(from: appState.lastOpened(destination.url), dateStyle: .none, timeStyle: .short))
                        .font(NotefyFont.label)
                        .tracking(1)
                        .foregroundStyle(NotefyTheme.inkFaint)
                }
                Spacer()
                if appState.isPinned(destination.url) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(NotefyTheme.marginRose)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotefyTheme.inkFaint)
            }
            .padding(.leading, CGFloat(depth) * 14 + 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NotefyTheme.sandDeep)
                        .deboss(cornerRadius: 12)
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
                        .foregroundStyle(NotefyTheme.inkSoft)
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Text("Storage used")
                        .font(NotefyFont.caption.weight(.regular))
                        .foregroundStyle(NotefyTheme.inkSoft)
                    Spacer()
                    Text("\(appState.storageUsedPercent)%")
                        .font(NotefyFont.label)
                        .tracking(1)
                        .foregroundStyle(NotefyTheme.inkFaint)
                }
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NotefyTheme.sandDeep)
                        .debossSoft(cornerRadius: 3)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(NotefyTheme.inkMid)
                                .frame(width: proxy.size.width * CGFloat(appState.storageUsedPercent) / 100)
                        }
                }
                .frame(height: 6)

                HStack {
                    HStack(spacing: 10) {
                        Text(userInitials)
                            .font(NotefyFont.mono.weight(.semibold))
                            .foregroundStyle(NotefyTheme.inkSoft)
                            .frame(width: 36, height: 36)
                            .background(NotefyTheme.sandDeep, in: Circle())
                            .emboss()
                        Text(appState.fullUserDisplayName)
                            .font(NotefyFont.heading)
                            .foregroundStyle(NotefyTheme.ink)
                    }
                    Spacer()
                    Button {
                        selection = .settings
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundStyle(NotefyTheme.inkSoft)
                            .padding(8)
                            .background(NotefyTheme.glassFillStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NotefyTheme.glassBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, collapsed ? 0 : 12)
        .overlay(alignment: .top) {
            if !collapsed {
                Rectangle().fill(NotefyTheme.glassBorder).frame(height: 1)
            }
        }
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
