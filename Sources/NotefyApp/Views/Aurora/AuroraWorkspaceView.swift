import SwiftUI
import AppKit

/// The Aurora shell: an infinite canvas of folders, a sorted feed of the same
/// library, and the note reader. Everything it draws comes from AppState — the
/// canvas owns arrangement, never content.
struct AuroraWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    @StateObject private var canvas = AuroraCanvasState()
    @State private var mode: AuroraViewMode = .map
    @State private var filter: AuroraFilter = .all
    @State private var sort: AuroraSort = .name
    @State private var query = ""
    @State private var focusedFolder: String? = nil
    @State private var openNoteURL: URL? = nil
    @State private var settingsOpen = false
    @State private var cancelEdits = 0
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
                tints: Self.tints(seed: folder.id.uuidString)))
        }

        let unfiled = snapshots.filter { $0.folderID == nil }
        if !unfiled.isEmpty || appState.workspace.folders.isEmpty {
            result.append(AuroraFolderTile(
                id: "unfiled",
                folderID: nil,
                name: "Unfiled",
                point: CGPoint(x: unfiledX, y: unfiledY),
                notes: unfiled,
                tints: Aurora.triad(seed: "unfiled")))
        }
        return result
    }

    private var visibleTiles: [AuroraFolderTile] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        switch filter {
        case .all: return tiles
        case .recent: return tiles.filter { t in t.notes.contains { $0.createdAt > cutoff } }
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

            if mode == .map, let tile = focusedTile {
                AuroraFocusOverlay(tile: tile,
                                   onClose: { closeFolder() },
                                   onOpenNote: { open(note: $0) })
                    .transition(.opacity)
            }

            chrome

            if let url = openNoteURL {
                AuroraNoteView(noteURL: url, onClose: { openNoteURL = nil })
                    .environmentObject(appState)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.smooth(duration: 0.3), value: openNoteURL)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: focusedFolder)
        .background(shortcuts)
        .onAppear { canvas.enabled = canvasLive; seedFolderPoints() }
        .onChange(of: focusedFolder) { _, _ in canvas.enabled = canvasLive }
        .onChange(of: openNoteURL) { _, _ in canvas.enabled = canvasLive }
        .onChange(of: mode) { _, _ in canvas.enabled = canvasLive }
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
                AuroraFeedView(tiles: sortedTiles, query: query, sort: $sort,
                               focused: $focusedFolder,
                               onOpenNote: { open(note: $0) })
            }
        }
        .blur(radius: focusing ? 9 : 0)
        .opacity(focusing ? 0.4 : 1)
        .animation(.smooth(duration: 0.42), value: focusedFolder)
    }

    private var sortedTiles: [AuroraFolderTile] {
        switch sort {
        case .name: return visibleTiles.sorted { $0.name < $1.name }
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
                                         onRename: { rename(tile, to: $0) })
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
                                    .foregroundStyle(filter == f ? Aurora.ground : Aurora.ink2)
                                    .padding(.horizontal, 15).padding(.vertical, 7)
                                    .background(filter == f ? AnyShapeStyle(Aurora.ink) : AnyShapeStyle(Aurora.surface2.opacity(0.85)),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.leading, 30).padding(.top, 44)

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

            VStack {
                Spacer()
                searchDock.padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeItem("square.grid.2x2", "Map", .map)
            modeItem("list.bullet", "Feed", .feed)
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
    }

    private func modeItem(_ icon: String, _ label: String, _ value: AuroraViewMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = value }
        } label: {
            Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(mode == value ? Aurora.ink : Aurora.ink3)
            .frame(width: 38, height: 30)
            .background(mode == value ? Aurora.surface2 : .clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            let hits = typed.isEmpty ? [] : Array(appState.searchNotes(query: typed).prefix(7))
            if !hits.isEmpty {
                VStack(spacing: 2) {
                    ForEach(hits) { hit in
                        Button { open(note: hit.url) ; query = "" } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Aurora.tint(Aurora.tintIndex(for: hit.title)))
                                    .frame(width: 9, height: 9)
                                Text(hit.title).font(Aurora.ui(14.5)).foregroundStyle(Aurora.ink).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(appState.folderPath(for: appState.folderID(for: hit.url)).isEmpty
                                     ? "Unfiled" : appState.folderPath(for: appState.folderID(for: hit.url)))
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
                TextField(dockPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(Aurora.ui(16, .regular))
                    .foregroundStyle(Aurora.ink)
                    .focused($searchFocused)
                    .onSubmit { create() }
                Button(action: create) {
                    Text("Create")
                        .font(Aurora.ui(15, .bold))
                        .foregroundStyle(Aurora.ground)
                        .padding(.horizontal, 17).padding(.vertical, 10)
                        .background(Aurora.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.13), radius: 24, y: 10)
        }
        .frame(maxWidth: 660)
        .animation(.smooth(duration: 0.22), value: query)
    }

    private var dockPlaceholder: String {
        if let t = focusedTile { return "Search in \(t.name)" }
        return "Search captures, notes and folders"
    }

    private var shortcuts: some View {
        ZStack {
            Button("") { back() }.keyboardShortcut(.cancelAction)
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { appState.showCapturePet() }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("") { withAnimation { mode = mode == .map ? .feed : .map } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        .opacity(0).frame(width: 0, height: 0)
    }

    // MARK: actions

    @State private var basePan: CGSize = .zero
    @State private var monitor: Any?

    private func openFolder(_ id: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { focusedFolder = id }
    }
    private func closeFolder() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { focusedFolder = nil }
    }
    private func open(note url: URL) {
        appState.openNote(url)
        openNoteURL = url
    }
    private func back() {
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
        guard !trimmed.isEmpty, let id = tile.folderID else { return }
        appState.renameFolder(id, to: trimmed)
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

    private func create() {
        let name = query.trimmingCharacters(in: .whitespaces)
        if let tile = focusedTile {
            let dest = appState.createNewNote(inFolder: tile.folderID)
            if !name.isEmpty { appState.renameNote(dest.url, to: name) }
            query = ""
            open(note: dest.url)
        } else {
            guard !name.isEmpty else { searchFocused = true; return }
            let id = appState.createFolder(name: name)
            appState.setFolderPoint(id, to: Self.slot(appState.workspace.folders.count - 1, of: tileCount))
            query = ""
        }
    }

    // MARK: trackpad

    private func installMonitor(size: CGSize) {
        removeMonitor()
        let state = canvas
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard state.enabled else { return event }
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
