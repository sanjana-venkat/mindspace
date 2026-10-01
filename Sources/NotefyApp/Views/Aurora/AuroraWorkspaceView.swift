import SwiftUI
import AppKit

/// The Aurora shell: an infinite canvas of folders, a sorted feed of the same
/// library, and the note reader. Everything it draws comes from AppState — the
/// canvas owns arrangement, never content.
struct AuroraWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    @StateObject private var canvas = AuroraCanvasState()
    @State private var mode: AuroraViewMode = .orbit
    @State private var filter: AuroraFilter = .all
    @State private var sort: AuroraSort = .name
    @State private var query = ""
    @State private var focusedFolder: String? = nil
    @State private var openNoteURL: URL? = nil
    @AppStorage(UnfiledName.key) private var unfiledName = ""
    /// Set while a title in the folder panel is being renamed, so Esc cancels
    /// the rename instead of closing the folder underneath it.
    @State private var panelRenaming = false
    @State private var cancelRenameTick = 0
    @State private var settingsOpen = false
    @State private var cancelEdits = 0
    @State private var noteMenu: AuroraNoteTarget?
    @State private var folderMenu: AuroraFolderTarget?
    @State private var themeSwipe: AuroraThemeSwipe.Move?
    /// Set when a folder has been asked to be deleted, and cleared when the
    /// question is answered either way.
    @State private var folderToDelete: AuroraFolderTarget?
    /// True while the new-folder prompt is up.
    @State private var namingFolder = false
    /// What was searched for when the open note was chosen from a result, and
    /// exactly where in the note the words were found.
    @State private var openNoteMark: String?
    @State private var openNoteStep: UUID?
    @State private var openNoteOrganized = false
    @FocusState private var searchFocused: Bool
    @AppStorage("aurora.unfiled.x") private var unfiledX: Double = 0
    @AppStorage("aurora.unfiled.y") private var unfiledY: Double = 0
    /// Bumped when the default arrangement changes, so existing workspaces get
    /// re-laid-out once instead of keeping positions from an older grid.
    @AppStorage("aurora.layout.version") private var layoutVersion: Int = 0

    // MARK: derived library

    private var tiles: [AuroraFolderTile] {
        let snapshots = appState.canvasNoteSnapshots
        var result: [AuroraFolderTile] = []

        for (i, folder) in appState.workspace.folders.enumerated() {
            let notes = snapshots.filter { $0.folderID == folder.id }
            let point = appState.folderPoint(folder.id) ?? Self.slot(i, of: tileCount)
            result.append(AuroraFolderTile(
                id: folder.id.uuidString,
                folderID: folder.id,
                name: folder.name,
                point: point,
                notes: notes,
                tints: folder.tint.map(Aurora.triad(chosen:)) ?? Self.tints(seed: folder.id.uuidString)))
        }

        let unfiled = snapshots.filter { $0.folderID == nil }
        // Always shown: it is where every capture lands first, so a new user
        // should see it in the ring before there is anything in it.
        do {
            result.append(AuroraFolderTile(
                id: "unfiled",
                folderID: nil,
                name: unfiledName.isEmpty ? UnfiledName.fallback : unfiledName,
                point: CGPoint(x: unfiledX, y: unfiledY),
                notes: unfiled,
                tints: Aurora.triad(seed: "unfiled")))
        }
        return result
    }

    /// Recent means *what you were just doing*, not "this week". A week's
    /// cutoff showed nearly the whole library, which made the filter useless —
    /// it is now the folders touched in the last day, at most two of them, and
    /// if nothing was touched today, the one folder you worked in last.
    private var visibleTiles: [AuroraFolderTile] {
        switch filter {
        case .all:
            return tiles
        case .recent:
            let today = Date().addingTimeInterval(-86_400)
            let ranked = tiles
                .compactMap { tile -> (tile: AuroraFolderTile, touched: Date)? in
                    guard let latest = tile.notes.map(\.createdAt).max() else { return nil }
                    return (tile, latest)
                }
                .sorted { $0.touched > $1.touched }
            let fresh = ranked.filter { $0.touched > today }
            let chosen = fresh.isEmpty ? Array(ranked.prefix(1)) : Array(fresh.prefix(2))
            return chosen.map(\.tile)
        }
    }

    private var focusedTile: AuroraFolderTile? {
        guard let focusedFolder else { return nil }
        return tiles.first { $0.id == focusedFolder }
    }

    private var tileCount: Int { appState.workspace.folders.count + 1 }

    /// A centred grid, so a small library sits in the middle of the canvas
    /// rather than out under the toolbar.
    private static func slot(_ i: Int, of count: Int) -> CGPoint {
        let cols = max(1, min(4, count))
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        let col = Double(i % cols), row = Double(i / cols)
        return CGPoint(x: (col - Double(cols - 1) / 2) * 312,
                       y: (row - Double(rows - 1) / 2) * 286)
    }

    private static func tints(seed: String) -> [Int] { Aurora.triad(seed: seed) }

    private var canvasLive: Bool { focusedFolder == nil && openNoteURL == nil && mode == .map }

    // MARK: body

    var body: some View {
        ZStack {
            AuroraGround()
            AuroraWindowGlass().frame(width: 0, height: 0)

            libraryLayer

            if mode == .orbit, openNoteURL == nil, let tile = focusedTile {
                // Beside the ring, not over it. Hidden while a note is open,
                // which is drawn lower and would otherwise sit under it; the
                // folder is still open, so Back returns to it.
                AuroraFolderPanel(
                    tile: tile,
                    onOpenNote: { note in open(note: note.url) },
                    onClose: { closeFolder() },
                    onRenameFolder: { name in rename(tile, to: name) },
                    onRenameNote: { note, name in appState.renameNote(note.url, to: name) },
                    renaming: $panelRenaming,
                    cancelRenameTick: cancelRenameTick)
                    .id(tile.id)
                    .blur(radius: appState.askOpen ? 26 : 0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(40)
            } else if let tile = focusedTile {
                AuroraFocusOverlay(tile: tile,
                                   onClose: { closeFolder() },
                                   onOpenNote: { open(note: $0) },
                                   onNoteRightClick: { note, point in
                                       noteMenu = AuroraNoteTarget(url: note.url, title: note.title, point: point)
                                   },
                                   // Lifting a note out closes the folder, so
                                   // the other folders are there to drop it on.
                                   onDragNoteOut: { closeFolder() })
                    .transition(.opacity)
            }

            chrome
                .blur(radius: appState.askOpen ? 26 : 0)
                .animation(.smooth(duration: 0.32), value: appState.askOpen)

            // The orbit hears you in its own ring. Anywhere else the same
            // words appear over the view, so the mic does the same thing from
            // either view instead of throwing you back to the orbit.
            if appState.isMoonListening, mode != .orbit || focusedFolder != nil {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    AuroraHeardView(transcript: appState.liveTranscript,
                                    onCancel: { appState.endMoonListening() },
                                    onSend: { text in
                                        appState.endMoonListening()
                                        appState.askNew(text)
                                    })
                        .padding(40)
                }
                .transition(.opacity)
                .zIndex(45)
            }

            if appState.askOpen {
                ZStack {
                    // Blurred and dark enough that the answer is the only
                    // thing with an edge, without the room disappearing.
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { appState.askOpen = false }
                    AuroraAskView(
                        turns: appState.askTurns,
                        onOpenSource: { source in
                            // Land on the capture the sentence came from, not
                            // the top of the note.
                            openNoteStep = source.stepID
                            openNoteOrganized = false
                            appState.askOpen = false
                            open(note: source.noteURL)
                        },
                        onClose: { appState.askOpen = false },
                        onAsk: { appState.ask($0) })
                }
                .transition(.opacity)
                .zIndex(50)
            }

            if let target = noteMenu {
                GeometryReader { geo in
                    ZStack {
                        Color.black.opacity(0.06)
                            .contentShape(Rectangle())
                            .onTapGesture { noteMenu = nil }
                        AuroraNoteActions(target: target, bounds: geo.size, style: target.style) { noteMenu = nil }
                    }
                }
                .transition(.opacity)
                .zIndex(8)
            }

            if let target = folderMenu {
                folderMenuLayer(target)
                    .transition(.opacity)
                    .zIndex(9)
            }

            if let target = folderToDelete {
                let count = noteCount(target)
                AuroraConfirm(
                    title: "Delete \u{201C}\(target.name)\u{201D}?",
                    message: count == 0
                        ? "The folder will be deleted permanently. Nothing is in it."
                        : "The folder and all its notes and captures will be deleted permanently \u{2014} \(count) note\(count == 1 ? "" : "s") in this one.",
                    onConfirm: {
                        appState.deleteFolder(target.id)
                        folderToDelete = nil
                    },
                    onCancel: { folderToDelete = nil })
                    .transition(.opacity)
                    .zIndex(30)
            }

            if namingFolder {
                AuroraPrompt(
                    title: "New topic",
                    placeholder: "Name it",
                    onConfirm: { createFolder(named: $0) },
                    onCancel: { namingFolder = false })
                    .transition(.opacity)
                    .zIndex(31)
            }

            AuroraThemeSwipe(run: $themeSwipe)
                .zIndex(60)

            if let url = openNoteURL {
                AuroraNoteView(noteURL: url,
                               searchMark: openNoteMark,
                               searchStep: openNoteStep,
                               searchInWriteUp: openNoteOrganized,
                               onClose: {
                                   openNoteURL = nil
                                   openNoteMark = nil
                                   openNoteStep = nil
                                   openNoteOrganized = false
                               })
                    .environmentObject(appState)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.smooth(duration: 0.3), value: openNoteURL)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: focusedFolder)
        .coordinateSpace(name: "auroraWorkspace")
        .animation(.smooth(duration: 0.22), value: noteMenu)
        .animation(.smooth(duration: 0.22), value: folderMenu)
        .animation(.smooth(duration: 0.2), value: folderToDelete)
        .animation(.smooth(duration: 0.2), value: namingFolder)
        .animation(.smooth(duration: 0.22), value: appState.askOpen)
        .animation(.smooth(duration: 0.22), value: appState.isMoonListening)
        .background(shortcuts)
        .onAppear { canvas.enabled = canvasLive; seedFolderPoints() }
        .onChange(of: focusedFolder) { _, _ in canvas.enabled = canvasLive }
        .onChange(of: openNoteURL) { _, _ in canvas.enabled = canvasLive }
        .onChange(of: mode) { _, _ in canvas.enabled = canvasLive }
        .onChange(of: settingsOpen) { _, _ in canvas.enabled = canvasLive }
        // A failure elsewhere can ask for Settings — a rejected key, say.
        .onChange(of: appState.isShowingSettings) { _, wants in
            guard wants else { return }
            settingsOpen = true
            appState.isShowingSettings = false
        }
        .onChange(of: noteMenu) { _, _ in canvas.enabled = canvasLive }
        .onChange(of: folderMenu) { _, _ in canvas.enabled = canvasLive }
        .sheet(isPresented: $settingsOpen) {
            AuroraSettingsView()
                .environmentObject(appState)
                .frame(width: 720, height: 620)
        }
    }

    /// Split out of `body`: as one expression the shell blew past the
    /// type-checker's budget.
    @ViewBuilder
    private var libraryLayer: some View {
        let focusing = focusedFolder != nil && mode == .map
        Group {
            if mode == .map {
                canvasLayer
            } else {
                AuroraOrbitView(
                    tiles: sortedTiles,
                    transcript: appState.liveTranscript,
                    levelDB: { appState.microphonePowerDB },
                    onOpenFolder: { tile in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            focusedFolder = tile.id
                        }
                    },
                    onListen: { appState.beginMoonListening() },
                    onStopListening: { appState.endMoonListening() },
                    listening: appState.isMoonListening,
                    onAsk: { question in appState.askNew(question) },
                    onShowAll: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .map } },
                    focusedID: focusedFolder,
                    shiftedFraction: focusedFolder == nil ? nil : AuroraFolderPanel.widthFraction)
            }
        }
        .blur(radius: appState.askOpen ? 26 : (focusing ? 9 : 0))
        .opacity(focusing ? 0.4 : 1)
        .animation(.smooth(duration: 0.42), value: focusedFolder)
        .animation(.smooth(duration: 0.32), value: appState.askOpen)
    }

    private var sortedTiles: [AuroraFolderTile] {
        switch sort {
        case .name: return visibleTiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent:
            return visibleTiles.sorted {
                ($0.notes.first?.createdAt ?? .distantPast) > ($1.notes.first?.createdAt ?? .distantPast)
            }
        case .size: return visibleTiles.sorted { $0.notes.count > $1.notes.count }
        }
    }

    // MARK: canvas

    private var canvasLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { cancelEdits += 1 }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                canvas.pan = CGSize(width: basePan.width + v.translation.width,
                                                    height: basePan.height + v.translation.height)
                            }
                            .onEnded { _ in basePan = canvas.pan }
                    )

                ZStack {
                    ForEach(visibleTiles) { tile in
                        AuroraFolderNode(tile: tile,
                                         zoom: canvas.zoom,
                                         dimmed: !matches(tile),
                                         cancelEdits: cancelEdits,
                                         onOpen: { openFolder(tile.id) },
                                         onMove: { move(tile, to: $0) },
                                         onRename: { rename(tile, to: $0) },
                                         onRightClick: tile.folderID == nil ? nil : { point in
                                             folderMenu = AuroraFolderTarget(id: tile.folderID!,
                                                                             name: tile.name,
                                                                             point: point)
                                         },
                                         onDropNotes: { file(notes: $0, into: tile) })
                            .position(x: geo.size.width / 2 + tile.point.x,
                                      y: geo.size.height / 2 + tile.point.y)
                    }
                }
                .scaleEffect(canvas.zoom, anchor: .center)
                .offset(canvas.pan)
                .animation(.smooth(duration: 0.25), value: canvas.zoom)

                if visibleTiles.isEmpty {
                    emptyCanvas.position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .background(AuroraWindowReader { canvasWindow = $0 })
            .onAppear { installMonitor(size: geo.size) }
            .onDisappear { removeMonitor() }
        }
    }

    private var emptyCanvas: some View {
        VStack(spacing: 10) {
            Text("Nothing kept yet")
                .font(Aurora.title(18)).foregroundStyle(Aurora.ink)
            Text("Press ⌘⇧K to keep what you are looking at, or name a folder below.")
                .font(Aurora.ui(13, .medium)).foregroundStyle(Aurora.ink3)
        }
    }

    private func matches(_ tile: AuroraFolderTile) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if tile.name.lowercased().contains(q) { return true }
        return tile.notes.contains { $0.title.lowercased().contains(q) || $0.excerpt.lowercased().contains(q) }
    }

    // MARK: chrome

    /// A folder open beside the ring is a focused reading state. The panel
    /// carries its own title and close, so the window's own controls go quiet.
    private var panelOpen: Bool { mode == .orbit && focusedFolder != nil }

    private var chrome: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    if let tile = focusedTile {
                        Button(action: { closeFolder() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Aurora.ink2)
                                .frame(width: 30, height: 30)
                                .background(.regularMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Aurora.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Text(tile.name).font(Aurora.title(30)).foregroundStyle(Aurora.ink)
                    } else {
                        Text("Mindspace").font(Aurora.display(30)).foregroundStyle(Aurora.ink)
                    }
                }

                if let tile = focusedTile {
                    Text("\(tile.notes.count) notes · \(tile.captureCount) captures")
                        .font(Aurora.ui(12.5, .medium)).foregroundStyle(Aurora.ink2)
                } else {
                    HStack(spacing: 8) {
                        ForEach(AuroraFilter.allCases) { f in
                            Button {
                                withAnimation(.smooth(duration: 0.25)) { filter = f }
                            } label: {
                                Text(f.label)
                                    .font(Aurora.ui(13.5))
                                    .foregroundStyle(filter == f ? Aurora.onSolid : Aurora.ink2)
                                    .padding(.horizontal, 15).padding(.vertical, 7)
                                    .background(filter == f ? AnyShapeStyle(Aurora.solid) : AnyShapeStyle(Aurora.surface2.opacity(0.85)),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.leading, 30).padding(.top, 44)
            .modifier(StepsBack(when: panelOpen))

            HStack(spacing: 10) {
                if mode == .map {
                    Button {
                        withAnimation(.spring) { canvas.reset(); basePan = .zero }
                    } label: {
                        Text("\(Int(canvas.zoom * 100))%")
                            .font(Aurora.mono(11)).foregroundStyle(Aurora.ink2)
                            .frame(width: 52).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Reset the view")
                }
                modeToggle
                Button { settingsOpen = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Aurora.ink2)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Aurora.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 44).padding(.trailing, 28)
            .modifier(StepsBack(when: panelOpen))

            // Making something new sits in the far corner, opposite the light
            // switch: both are things you reach for deliberately, neither
            // belongs in the path of the search.
            Button {
                if focusedTile != nil { create() } else { namingFolder = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(focusedTile == nil ? "New topic" : "New note")
                        .font(Aurora.ui(13.5))
                }
                .foregroundStyle(Aurora.onSolid)
                .padding(.horizontal, 15).padding(.vertical, 7)
                .background(Aurora.solid, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(AuroraTapDown())
            .help(focusedTile == nil ? "Make a topic" : "Start a note here")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 28).padding(.bottom, 30)
            .modifier(StepsBack(when: panelOpen))

            VStack {
                Spacer()
                VStack(spacing: 12) {
                    searchDock
                    // Always laid out, only hidden while typing. Removing the
                    // row moved the bar down under your cursor mid-word.
                    suggestionPills
                        .opacity(query.isEmpty ? 1 : 0)
                        .allowsHitTesting(query.isEmpty)
                }
                .padding(.bottom, 30)
                // While the moon listens it has its own Send and Cancel, and a
                // long sentence pushes them down to exactly where the pills sit.
                // An open folder is the thing you are looking at, in either
                // view. A search bar over it reads as part of the folder.
                .opacity(appState.isMoonListening || focusedFolder != nil ? 0 : 1)
                .allowsHitTesting(!(appState.isMoonListening || focusedFolder != nil))
            }
            .frame(maxWidth: .infinity)

            AuroraThemeToggle(swipe: $themeSwipe)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 28).padding(.bottom, 30)
                .modifier(StepsBack(when: panelOpen))
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeItem("circle.circle", "Orbit", .orbit)
            modeItem("square.grid.2x2", "Folders", .map)
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
    }

    private func modeItem(_ icon: String, _ label: String, _ value: AuroraViewMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = value }
        } label: {
            // The same selected state as the note's own view switcher: solid,
            // not a slightly lighter grey. Two toggles doing the same job
            // should not look like different controls.
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == value ? Aurora.onSolid : Aurora.ink2)
                .frame(width: 40, height: 30)
                .background(mode == value ? AnyShapeStyle(Aurora.solid) : AnyShapeStyle(Color.clear),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var sortRail: some View {
        HStack(spacing: 3) {
            ForEach(AuroraSort.allCases, id: \.self) { k in
                Button(k.label) { withAnimation(.smooth(duration: 0.3)) { sort = k } }
                    .buttonStyle(.plain)
                    .font(Aurora.ui(12.5))
                    .foregroundStyle(sort == k ? Aurora.accent : Aurora.ink3)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(sort == k ? Aurora.accentSoft : .clear, in: Capsule())
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
    }

    private var searchDock: some View {
        VStack(spacing: 10) {
            // Results are a response to typing, not a standing panel.
            let typed = query.trimmingCharacters(in: .whitespaces)
            let folderHits = typed.isEmpty ? [] : Array(matchingFolders(typed).prefix(3))
            let hits = typed.isEmpty ? [] : Array(appState.searchNotes(query: typed).prefix(5))
            if !typed.isEmpty {
                VStack(spacing: 2) {
                    // Return asks. The matches underneath are shortcuts to
                    // things whose name you already know.
                    Button { submit() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Aurora.accent)
                                .frame(width: 14)
                            Text("Ask your mindspace: \u{201C}\(typed)\u{201D}")
                                .font(Aurora.ui(14.5)).foregroundStyle(Aurora.ink).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("↩").font(Aurora.mono(12)).foregroundStyle(Aurora.ink3)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AuroraHoverRow())

                    if !folderHits.isEmpty || !hits.isEmpty {
                        Rectangle().fill(Aurora.line).frame(height: 1).padding(.horizontal, 10)
                    }

                    // Folders first, and marked as folders: a name you half
                    // remember is as likely to be a folder's as a note's.
                    ForEach(folderHits) { tile in
                        Button {
                            query = ""
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                focusedFolder = tile.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Aurora.tint(tile.tints.first ?? 0))
                                    .frame(width: 14)
                                Text(tile.name).font(Aurora.ui(14.5)).foregroundStyle(Aurora.ink).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(tile.notes.count) note\(tile.notes.count == 1 ? "" : "s")")
                                    .font(Aurora.ui(12.5)).foregroundStyle(Aurora.ink3)
                            }
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AuroraHoverRow())
                    }

                    if !folderHits.isEmpty && !hits.isEmpty {
                        Rectangle().fill(Aurora.line).frame(height: 1).padding(.horizontal, 10)
                    }

                    ForEach(hits) { hit in
                        let found = appState.searchHit(for: hit.url, query: typed)
                        Button {
                            openNoteMark = typed
                            openNoteStep = found?.stepID
                            openNoteOrganized = found?.organized ?? false
                            open(note: hit.url)
                            query = ""
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Aurora.tint(Aurora.tintIndex(for: hit.title)))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title).font(Aurora.ui(14.5)).foregroundStyle(Aurora.ink).lineLimit(1)
                                    // Where the words were found, when they
                                    // weren't in the title.
                                    if let snippet = found?.snippet,
                                       !hit.title.lowercased().contains(typed.lowercased()) {
                                        Text(Aurora.marked(snippet, query: typed))
                                            .font(Aurora.ui(11.5))
                                            .foregroundStyle(Aurora.ink3)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(appState.folderPath(for: appState.folderID(for: hit.url)).isEmpty
                                     ? UnfiledName.current : appState.folderPath(for: appState.folderID(for: hit.url)))
                                    .font(Aurora.ui(12.5, .regular)).foregroundStyle(Aurora.ink3).lineLimit(1)
                            }
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AuroraHoverRow())
                    }
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 26, y: 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Aurora.ink3)
                // Matches appear as you type; Return asks. The bar is the
                // same in both views, mic and all.
                    TextField(dockPlaceholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(Aurora.ui(16, .regular))
                        .foregroundStyle(Aurora.ink)
                        .focused($searchFocused)
                        .onSubmit { submit() }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Aurora.ink3)
                                .contentShape(Circle())
                        }
                        .buttonStyle(AuroraTapDown())
                        .help("Clear")
                    }
                    Button { appState.beginMoonListening() } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Aurora.ink2)
                            .frame(width: 30, height: 30)
                            .background(Aurora.surface2, in: Circle())
                    }
                    .buttonStyle(AuroraTapDown())
                    .help("Ask out loud")

                    Button { submit() } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Aurora.accent, in: Circle())
                    }
                    .buttonStyle(AuroraTapDown())
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(query.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .help("Ask your mindspace")
                }
            .padding(.horizontal, 20)
            .frame(height: 51)
            .auroraRaisedField()
        }
        .frame(maxWidth: 620)
        .animation(.smooth(duration: 0.22), value: query)
    }

    /// Folders whose name matches what is being typed.
    private func matchingFolders(_ query: String) -> [AuroraFolderTile] {
        let needle = query.lowercased()
        return sortedTiles.filter { !$0.isUnfiled && $0.name.lowercased().contains(needle) }
    }

    /// Openers made of real folders, so a suggestion never promises something
    /// the library cannot answer.
    private var suggestionPills: some View {
        let picks = sortedTiles
            .filter { !$0.isUnfiled && $0.captureCount > 0 }
            .sorted { $0.captureCount > $1.captureCount }
            .prefix(3)
        let questions = picks.isEmpty
            ? ["What did I save this week?"]
            : picks.map { "What did I save about \($0.name)?" }
        return HStack(spacing: 10) {
            ForEach(questions, id: \.self) { q in
                Button { appState.askNew(q) } label: {
                    Text(q)
                        .font(Aurora.ui(13, .regular))
                        .foregroundStyle(Aurora.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Aurora.surface.opacity(0.5)))
                        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                }
                .buttonStyle(AuroraTapDown())
            }
        }
    }

    /// The same words in both views: the bar does the same thing in both.
    private var dockPlaceholder: String { "Ask anything" }

    private var shortcuts: some View {
        ZStack {
            Button("") { back() }.keyboardShortcut(.cancelAction)
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { appState.showCapturePet() }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("") { withAnimation { mode = mode == .map ? .orbit : .map } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        .opacity(0).frame(width: 0, height: 0)
    }

    // MARK: actions

    @State private var basePan: CGSize = .zero
    @State private var monitor: Any?
    @State private var canvasWindow: NSWindow?

    private func openFolder(_ id: String) {
        query = ""
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { focusedFolder = id }
    }
    private func closeFolder() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { focusedFolder = nil }
    }
    private func open(note url: URL) {
        appState.openNote(url)
        openNoteURL = url
    }
    /// Esc, in order of what is nearest to you. One owner for the key: two
    /// buttons both claiming it left which one won down to SwiftUI.
    private func back() {
        if panelRenaming { cancelRenameTick += 1; return }
        if appState.capturePreview != nil {
            withAnimation(.smooth(duration: 0.22)) { appState.capturePreview = nil }
            return
        }
        // A dialog or a menu is the nearest thing. They claim Esc themselves
        // too, so whichever claim wins, the outcome is the same.
        if folderToDelete != nil { folderToDelete = nil; return }
        if namingFolder { namingFolder = false; return }
        if noteMenu != nil { noteMenu = nil; return }
        if folderMenu != nil { folderMenu = nil; return }
        if appState.isMoonListening { appState.endMoonListening(); return }
        if appState.askOpen { appState.askOpen = false; return }
        if openNoteURL != nil { openNoteURL = nil }
        else if focusedFolder != nil { closeFolder() }
        else if !query.isEmpty { query = "" }
    }

    private func move(_ tile: AuroraFolderTile, to p: CGPoint) {
        if let id = tile.folderID {
            appState.setFolderPoint(id, to: p)
        } else {
            unfiledX = p.x; unfiledY = p.y
        }
    }

    private func rename(_ tile: AuroraFolderTile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Unfiled is not a folder record, so its name is kept on its own.
        guard let id = tile.folderID else { unfiledName = trimmed; return }
        appState.renameFolder(id, to: trimmed)
    }

    /// Deleting a folder keeps what was in it: the notes move up to the
    /// parent folder rather than going anywhere near the trash.
    /// The right-click menu, over a scrim that closes it.
    private func folderMenuLayer(_ target: AuroraFolderTarget) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.06)
                    .contentShape(Rectangle())
                    .onTapGesture { folderMenu = nil }
                AuroraFolderActions(target: target,
                                    bounds: geo.size,
                                    onRequestDelete: { folderToDelete = $0 },
                                    onClose: { folderMenu = nil })
            }
        }
    }

    /// How many notes are in the folder being asked about, so the question can
    /// say what is actually at stake.
    private func noteCount(_ target: AuroraFolderTarget) -> Int {
        appState.canvasNoteSnapshots.filter { $0.folderID == target.id }.count
    }

    private func delete(_ tile: AuroraFolderTile) {
        guard let id = tile.folderID else { return }
        if focusedFolder == tile.id { closeFolder() }
        appState.deleteFolder(id)
    }

    /// Folders created before the canvas existed have no point; give them one
    /// the first time they are drawn so dragging starts from a real position.
    private func seedFolderPoints() {
        let count = tileCount
        if layoutVersion < 2 {
            for (i, folder) in appState.workspace.folders.enumerated() {
                appState.setFolderPoint(folder.id, to: Self.slot(i, of: count))
            }
            let p = Self.slot(count - 1, of: count)
            unfiledX = p.x; unfiledY = p.y
            layoutVersion = 2
            return
        }
        for (i, folder) in appState.workspace.folders.enumerated() where folder.x == nil {
            appState.setFolderPoint(folder.id, to: Self.slot(i, of: count))
        }
    }

    /// Return in the dock asks, in either view. It used to open the top keyword
    /// match in one view and ask in the other, so the same keystroke did two
    /// different things depending on which icon was lit.
    private func submit() {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        query = ""
        searchFocused = false
        appState.askNew(typed)
    }

    /// Files dragged notes into a folder. Anything that isn't a note this app
    /// knows about is refused, so dropping a stray file does nothing.
    private func file(notes urls: [URL], into tile: AuroraFolderTile) -> Bool {
        let known = Set(appState.historyFiles.map { $0.lastPathComponent })
        let notes = urls.filter { known.contains($0.lastPathComponent) }
        guard !notes.isEmpty else { return false }
        for url in notes { appState.moveNote(url, toFolder: tile.folderID) }
        return true
    }

    /// Inside a folder, the plus starts a note there.
    private func create() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard let tile = focusedTile else { namingFolder = true; return }
        let dest = appState.createNewNote(inFolder: tile.folderID)
        if !name.isEmpty { appState.renameNote(dest.url, to: name) }
        query = ""
        open(note: dest.url)
    }

    private func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let id = appState.createFolder(name: trimmed)
        appState.setFolderPoint(id, to: Self.slot(appState.workspace.folders.count - 1, of: tileCount))
        namingFolder = false
        query = ""
    }

    // MARK: trackpad

    private func installMonitor(size: CGSize) {
        removeMonitor()
        let state = canvas
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard state.enabled else { return event }
            // A local monitor sees the whole app, so anything living in its own
            // window — a sheet, the capture rail, a popover — has to be let
            // through untouched. Gating on state alone kept swallowing the
            // settings sheet's scroll.
            if let canvasWindow, let target = event.window, target !== canvasWindow {
                return event
            }
            let winH = event.window?.contentView?.bounds.height ?? size.height
            let cursor = CGPoint(x: event.locationInWindow.x, y: winH - event.locationInWindow.y)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            if event.type == .magnify {
                zoomBy(1 + event.magnification, cursor: cursor, center: center)
                return nil
            }
            if event.modifierFlags.contains(.command) {
                zoomBy(1 + event.scrollingDeltaY * 0.006, cursor: cursor, center: center)
                return nil
            }
            state.pan = CGSize(width: state.pan.width + event.scrollingDeltaX,
                               height: state.pan.height + event.scrollingDeltaY)
            basePan = state.pan
            return nil
        }
    }

    private func zoomBy(_ factor: CGFloat, cursor: CGPoint, center: CGPoint) {
        let next = min(2.4, max(0.35, canvas.zoom * factor))
        guard next != canvas.zoom else { return }
        let world = CGPoint(x: (cursor.x - center.x - canvas.pan.width) / canvas.zoom,
                            y: (cursor.y - center.y - canvas.pan.height) / canvas.zoom)
        canvas.pan = CGSize(width: canvas.pan.width + world.x * (canvas.zoom - next),
                            height: canvas.pan.height + world.y * (canvas.zoom - next))
        basePan = canvas.pan
        canvas.zoom = next
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

/// Hands back the NSWindow a SwiftUI view is living in.
struct AuroraWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

/// Fades a piece of chrome out and takes it out of the hit path, without
/// removing it, so nothing reflows when it comes back.
private struct StepsBack: ViewModifier {
    let when: Bool
    func body(content: Content) -> some View {
        content
            .opacity(when ? 0 : 1)
            .allowsHitTesting(!when)
            .animation(.smooth(duration: 0.25), value: when)
    }
}
