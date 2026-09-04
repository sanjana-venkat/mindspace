import SwiftUI
import AppKit
import NotefyCore
import UniformTypeIdentifiers

private enum CanvasFolderFilter: Hashable {
    case all
    case unfiled
    case folder(UUID)
}

private enum ReaderTab: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case organized = "Organized"
    var id: String { rawValue }
}

/// How a note's captures are laid out. Panel is the reading posture — the
/// note pinned beside a single column you scroll through. Grid is the
/// arranging posture — every capture visible at once and draggable, which is
/// what the workspace is actually for.
private enum ReaderLayout: String, CaseIterable, Identifiable {
    case grid = "Grid view"
    case panel = "Panel view"
    var id: String { rawValue }
    var icon: String { self == .grid ? "square.grid.2x2" : "sidebar.right" }
    /// Remembered across notes and launches — a working posture, not a
    /// per-note property.
    static let storageKey = "noted.readerLayout"
}

struct CanvasWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var folderFilter: CanvasFolderFilter = .all
    @State private var foldersOpen = false
    @State private var settingsOpen = false
    @State private var inkTransitionFrame: Int?
    @State private var zoom: CGFloat = 1.0
    /// Owned here rather than in the reader so switching posture can be
    /// wrapped in the same ink wipe that switching notes uses — the overlay
    /// lives at this level.
    @AppStorage(ReaderLayout.storageKey) private var layoutRaw = ReaderLayout.panel.rawValue
    @FocusState private var keyboardFocused: Bool

    /// The note picker's label. The workspace is always inside a note now, so
    /// the useful context is which note you are in and which folder it came
    /// from — not which filter the (now removed) card wall was under.
    private var pickerTitle: String {
        let title = appState.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled note" : title
    }

    private var pickerSubtitle: String {
        guard let url = appState.activeNoteURL else { return "Unfiled" }
        let path = appState.folderPath(for: appState.folderID(for: url))
        return path.isEmpty ? "Unfiled" : path
    }

    var body: some View {
        ZStack {
            CanvasClayBackground(focused: true, zoom: 1)

            CaptureReadingView(zoom: zoom, layoutRaw: layoutRaw, setLayout: setLayout)
                .environmentObject(appState)

            VStack(spacing: 0) {
                CanvasToolbar(
                    title: pickerTitle,
                    subtitle: pickerSubtitle,
                    foldersOpen: $foldersOpen,
                    settingsOpen: $settingsOpen,
                    zoom: $zoom
                )
                Spacer()
            }
            .zIndex(3)

            if foldersOpen {
                CanvasFolderOverlay(
                    filter: $folderFilter,
                    isOpen: $foldersOpen,
                    notes: appState.canvasNoteSnapshots,
                    activeURL: appState.activeNoteURL,
                    openNote: { url in transitionToReading(url) },
                    createNote: { folderID in
                        let destination = appState.createNewNote(inFolder: folderID)
                        transitionToReading(destination.url)
                    }
                )
                .environmentObject(appState)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
                .zIndex(5)
            }

            if let inkTransitionFrame {
                InkOpenTransition(frame: inkTransitionFrame, origin: nil)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                    .zIndex(20)
            }
        }
        .focusable()
        .focused($keyboardFocused)
        .onAppear {
            appState.refreshHistory()
            keyboardFocused = true
        }
        .onKeyPress(.escape) {
            if foldersOpen { withAnimation { foldersOpen = false }; return .handled }
            return .ignored
        }
        .sheet(isPresented: $settingsOpen) {
            SettingsView()
                .environmentObject(appState)
                .environment(\.ground, GroundPalette.clay)
                .frame(width: 880, height: 680)
                .background(Stoneink.surfaceBed)
        }
    }

    /// Switching notes keeps the ink wipe the card wall used to open with —
    /// it is the one moment that still marks "you are now somewhere else".
    private func transitionToReading(_ url: URL) {
        inkWipe(interval: Self.noteWipeInterval) { appState.openNote(url) }
    }

    /// Grid and panel are two views of the same note, so the change is worth
    /// the same beat: the ink covers, the layout swaps behind it, the ink
    /// pulls back. Without it the whole page silently becomes something else.
    private func setLayout(_ option: ReaderLayout) {
        guard option.rawValue != layoutRaw else { return }
        inkWipe(interval: Self.layoutWipeInterval) { layoutRaw = option.rawValue }
    }

    /// Cover, change, reveal. The change happens at the midpoint so it is
    /// never seen happening.
    /// Opening a note is a rarer, heavier move and keeps the full beat.
    /// Flipping posture is something you do repeatedly while working, so it
    /// runs the same 36 frames at a shorter interval — same gesture, roughly
    /// two-thirds the time, so it still reads as ink rather than a cut.
    private static let noteWipeInterval = 28
    private static let layoutWipeInterval = 18

    private func inkWipe(interval: Int, _ change: @escaping () -> Void) {
        guard inkTransitionFrame == nil else { return }

        guard !reduceMotion else {
            change()
            return
        }

        Task { @MainActor in
            let coverFrames = 16
            let revealFrames = 20

            for frame in 0..<coverFrames {
                inkTransitionFrame = frame
                try? await Task.sleep(for: .milliseconds(interval))
            }

            change()

            for frame in coverFrames..<(coverFrames + revealFrames) {
                inkTransitionFrame = frame
                try? await Task.sleep(for: .milliseconds(interval))
            }

            inkTransitionFrame = nil
            keyboardFocused = true
        }
    }
}

private struct CanvasToolbar: View {
    let title: String
    let subtitle: String
    @Binding var foldersOpen: Bool
    @Binding var settingsOpen: Bool
    @Binding var zoom: CGFloat

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                // The note switcher. Two lines because the folder is context
                // for the title, not a peer of it — and the chevron is pinned
                // to the pill's trailing edge rather than trailing the title,
                // so it reads as the control's affordance instead of drifting
                // with whatever the note happens to be called.
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { foldersOpen.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        CanvasBrandIcon()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(subtitle.uppercased())
                                .font(CanvasTypography.mark(8)).tracking(1.1)
                                .opacity(0.45)
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 10)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(foldersOpen ? 180 : 0))
                            .opacity(0.55)
                    }
                    .padding(.horizontal, 15).frame(height: 46)
                    .frame(width: 250, alignment: .leading)
                    .background(CanvasPalette.paper.opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(CanvasPalette.ink.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Switch note")

                Spacer()

                // Zoom belongs with the captures now that they are what the
                // window actually holds.
                HStack(spacing: 8) {
                    Button { zoom = max(0.60, zoom - 0.10) } label: { Image(systemName: "minus") }
                        .help("Zoom out")
                    Text("\(Int(zoom * 100))%")
                        .font(CanvasTypography.mark(10))
                        .frame(width: 38)
                    Button { zoom = min(1.40, zoom + 0.10) } label: { Image(systemName: "plus") }
                        .help("Zoom in")
                    Divider().frame(height: 18).opacity(0.25)
                    Button { settingsOpen = true } label: { Image(systemName: "gearshape") }
                        .help("Settings")
                        .accessibilityLabel("Settings")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 13).frame(height: 46)
                .background(CanvasPalette.paper.opacity(0.72), in: Capsule())
                .overlay(Capsule().stroke(CanvasPalette.ink.opacity(0.10)))
            }

            CanvasBrandMark()
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }
}

private struct CaptureReadingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let zoom: CGFloat
    let layoutRaw: String
    let setLayout: (ReaderLayout) -> Void
    @State private var activeCaptureID: UUID?
    @State private var tab: ReaderTab = .raw

    private var layout: ReaderLayout { ReaderLayout(rawValue: layoutRaw) ?? .panel }

    private var activeStep: ExplorationStep? {
        appState.steps.first { $0.id == activeCaptureID } ?? appState.steps.last
    }

    private var activeNoteText: String {
        guard let step = activeStep else { return appState.rawDraft }
        return appState.stepAnnotations[step.id] ?? ""
    }

    private var activeNoteBinding: Binding<String> {
        Binding(
            get: { activeNoteText },
            set: { value in
                if let step = activeStep {
                    appState.stepAnnotations[step.id] = value
                } else {
                    appState.rawDraft = value
                }
                appState.scheduleActiveNoteAutosave()
            }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch tab {
                case .raw:
                    switch layout {
                    case .panel:
                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                rawNoteColumn
                                    .frame(width: proxy.size.width / 3)
                                captureColumn
                                    .padding(.top, 146)
                                    .frame(width: proxy.size.width * 2 / 3)
                            }
                        }
                        .transition(.opacity)
                    case .grid:
                        CaptureGridView(activeCaptureID: $activeCaptureID)
                            .environmentObject(appState)
                            .padding(.top, 146)
                            .transition(.opacity)
                    }
                case .organized:
                    OrganizedEssayView()
                        .environmentObject(appState)
                        .padding(.top, 146)
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            // Zoom scales the work, never the chrome — the tab bar and the
            // posture switch stay the size the pointer expects them to be.
            .scaleEffect(zoom, anchor: .top)
            .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.28), value: tab)
            .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.28), value: layoutRaw)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: zoom)

            ReaderTabBar(selection: $tab)
                .padding(.top, 78)
                .zIndex(2)

            // Only Raw has two postures to choose between; the essay is a
            // single reading surface either way.
            if tab == .raw {
                HStack {
                    Spacer()
                    ReaderLayoutToggle(layout: layout, setLayout: setLayout)
                }
                .padding(.horizontal, 24)
                .padding(.top, 78)
                .zIndex(2)
            }
        }
    }

    private var rawNoteColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.activeNoteURL.map { appState.folderPath(for: appState.folderID(for: $0)) }.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "NOTE")
                .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5).opacity(0.48)
            TextField("Untitled note", text: $appState.noteTitle)
                .textFieldStyle(.plain)
                .font(CanvasTypography.noteTitle)
                .onChange(of: appState.noteTitle) { appState.scheduleActiveNoteAutosave() }

            ZStack(alignment: .topLeading) {
                if activeNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write the note you want to keep beside these captures…")
                        .font(CanvasTypography.noteBody).italic().opacity(0.42)
                        .padding(.top, 7).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: activeNoteBinding)
                    .id(activeCaptureID)
                    .font(CanvasTypography.noteBody)
                    .lineSpacing(7).scrollContentBackground(.hidden)
                    .background(.clear)
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? .linear(duration: 0.10) : .easeInOut(duration: 0.24), value: activeCaptureID)
        }
        .padding(.horizontal, 38).padding(.top, 108).padding(.bottom, 32)
        .background(CanvasPalette.paper.opacity(0.32))
    }

    private var captureColumn: some View {
        GeometryReader { proxy in
            if appState.steps.isEmpty {
                ContentUnavailableView(
                    "No captures yet",
                    systemImage: "viewfinder",
                    description: Text("Use Kami or a capture shortcut to add the first source.")
                )
                .foregroundStyle(CanvasPalette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 28) {
                        ForEach(Array(appState.steps.reversed())) { step in
                            LiveCaptureCard(step: step, height: min(proxy.size.height * 0.74, 610))
                                .id(step.id)
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.28)) { activeCaptureID = step.id }
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 38).padding(.vertical, proxy.size.height * 0.13)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// The posture switch. Sits opposite the Raw/Organized tabs rather than in
/// the window toolbar, because it changes what THIS note looks like, not what
/// the app is doing.
private struct ReaderLayoutToggle: View {
    let layout: ReaderLayout
    /// The switch is wrapped in the ink wipe by the workspace, so this only
    /// reports intent.
    let setLayout: (ReaderLayout) -> Void
    @Namespace private var inkSelection

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ReaderLayout.allCases) { option in
                let active = option == layout
                Button {
                    guard !active else { return }
                    setLayout(option)
                } label: {
                    // Icon only. The label was carrying the same two words on
                    // every screen for a control you use once and then leave
                    // alone, and it made a persistent chip wider than the tab
                    // bar it sits opposite. The name lives in the tooltip.
                    Image(systemName: option.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? CanvasPalette.paper : CanvasPalette.ink.opacity(0.54))
                        .frame(width: 40, height: 34)
                        .background {
                            if active {
                                InkPillShape(variation: option == .grid ? 0 : 1)
                                    .fill(CanvasPalette.inkBlue)
                                    .matchedGeometryEffect(id: "ink-layout", in: inkSelection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.rawValue)
                .accessibilityLabel(option.rawValue)
            }
        }
        .padding(4)
        .background(CanvasPalette.paper.opacity(0.88), in: InkPillShape(variation: 2))
        .overlay(InkPillShape(variation: 2).stroke(CanvasPalette.inkBlue.opacity(0.13)))
        .shadow(color: CanvasPalette.clay.opacity(0.95), radius: 16, y: 5)
    }
}

/// Grid view: the whole note laid out at once. The note itself is the first
/// tile rather than a separate column, because in this posture it is one more
/// thing you place — captures reorder around it by drag, and the order is the
/// note's own order, persisted the same way the canvas persists note order.
private struct CaptureGridView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var activeCaptureID: UUID?

    /// The capture currently under the pointer's drag. Held here rather than
    /// read out of the drop payload so reordering can happen on hover.
    @State private var draggingID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 24)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTE")
                        .font(CanvasTypography.mark(10)).tracking(1.4)
                        .opacity(0.45)

                    TextField("Untitled note", text: $appState.noteTitle)
                        .textFieldStyle(.plain)
                        .font(CanvasTypography.noteTitle)
                        .onChange(of: appState.noteTitle) { appState.scheduleActiveNoteAutosave() }

                    // A vertical TextField rather than a TextEditor: it grows
                    // with what you write instead of reserving a fixed block
                    // of empty height, so an empty note costs one line rather
                    // than a gap the width of the page. No placeholder — the
                    // heading above already says what this is.
                    TextField("", text: Binding(
                        get: { appState.rawDraft },
                        set: { appState.rawDraft = $0; appState.scheduleActiveNoteAutosave() }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(CanvasTypography.noteBody)
                    .lineLimit(1...8)
                }
                .frame(maxWidth: 620, alignment: .leading)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(appState.steps.reversed()) { step in
                    GridCaptureTile(
                        step: step,
                        selected: step.id == activeCaptureID,
                        note: Binding(
                            get: { appState.stepAnnotations[step.id] ?? "" },
                            set: {
                                appState.stepAnnotations[step.id] = $0
                                appState.scheduleActiveNoteAutosave()
                            }
                        )
                    )
                        .id(step.id)
                        .opacity(draggingID == step.id ? 0.35 : 1)
                        // simultaneousGesture, not onTapGesture: a plain tap
                        // gesture claims the mouse-down and the drag session
                        // never starts, which is why these tiles could not be
                        // moved at all. A simultaneous recogniser lets the
                        // drag through and still selects on a clean click.
                        .simultaneousGesture(
                            TapGesture().onEnded { activeCaptureID = step.id }
                        )
                        // onDrag/onDrop rather than draggable/dropDestination:
                        // the newer pair silently refuses to start a drag on
                        // macOS when the dragged view holds rich content like
                        // an NSImage and its own tap targets, which is exactly
                        // what a capture tile is.
                        .onDrag {
                            draggingID = step.id
                            return NSItemProvider(object: step.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.utf8PlainText, .plainText, .text],
                            delegate: CaptureReorderDelegate(
                                target: step.id,
                                dragging: $draggingID,
                                move: appState.moveCapture
                            )
                        )
                }
                }
            }
            .padding(.horizontal, 38)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .onDrop(of: [.utf8PlainText, .plainText, .text], isTargeted: nil) { _ in
            // Released over the gaps between tiles: nothing to reorder
            // against, but the drag is over, so stop dimming the source.
            draggingID = nil
            return false
        }
        .overlay {
            if appState.steps.isEmpty {
                ContentUnavailableView(
                    "No captures yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Use Kami or a capture shortcut to add the first source.")
                )
                .foregroundStyle(CanvasPalette.ink)
            }
        }
    }
}

/// Reorders on hover rather than on release, so the grid rearranges under
/// the pointer and you can see where the capture will land before you let
/// go. `performDrop` only has to clear the drag state — the move already
/// happened.
private struct CaptureReorderDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            move(dragging, target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

/// A capture at grid scale: the capture fills the tile, with one mono caption
/// above and the source below — the same rule the panel-view card follows.
private struct GridCaptureTile: View {
    let step: ExplorationStep
    let selected: Bool
    /// The note you wrote against THIS capture. In panel view it lives in the
    /// left column and swaps as you scroll; here every capture carries its own
    /// alongside it, which is the whole point of seeing them all at once.
    @Binding var note: String

    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(kindLabel) · \(step.timestamp.formatted(date: .omitted, time: .shortened))".uppercased())
                Spacer()
                Image(systemName: kindIcon)
            }
            .font(CanvasTypography.mark(9)).tracking(1.0).opacity(0.45)

            if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let text = primaryText, !text.isEmpty {
                Text(text)
                    .font(CanvasTypography.cardBody)
                    .lineSpacing(5)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            ZStack(alignment: .topLeading) {
                if noteFocused {
                    TextEditor(text: $note)
                        .focused($noteFocused)
                        .font(CanvasTypography.cardBody)
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                } else {
                    Text(note.isEmpty ? "Add a note…" : note)
                        .font(CanvasTypography.cardBody)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .opacity(note.isEmpty ? 0.34 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 4).padding(.top, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { noteFocused = true }
                }
            }
            .frame(height: 54)
            .padding(.horizontal, 4)
            .background(
                CanvasPalette.inkBlue.opacity(noteFocused ? 0.07 : 0.035),
                in: RoundedRectangle(cornerRadius: 7)
            )

            Text(sourceLabel)
                .font(CanvasTypography.markRegular(9)).tracking(0.8)
                .opacity(0.50)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(18)
        .frame(height: 420)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanvasPalette.sheet(for: step.id), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? CanvasPalette.inkBlue.opacity(0.42) : CanvasPalette.ink.opacity(0.07),
                        lineWidth: 1)
        )
        // Barely there. A card should sit ON the paper, not hover above it —
        // the old 14pt shadow was the single most SaaS thing on the screen.
        .shadow(color: CanvasPalette.warmShadow.opacity(selected ? 0.10 : 0.05),
                radius: selected ? 10 : 6, y: 2)
    }

    private var primaryText: String? { step.selectedText ?? step.pageText }
    private var kindLabel: String {
        step.screenshotPath != nil ? "Capture"
            : (step.appName.localizedCaseInsensitiveContains("audio") ? "Voice" : "Text")
    }
    private var kindIcon: String {
        step.screenshotPath != nil ? "photo"
            : (step.appName.localizedCaseInsensitiveContains("audio") ? "waveform" : "text.alignleft")
    }
    private var sourceLabel: String {
        if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host.uppercased() }
        if step.appName == "Audio" { return "COMPUTER AUDIO" }
        if ["Notefy", "Noted", "notefy-app"].contains(step.appName) { return "SCREEN REGION" }
        let title = step.windowTitle.isEmpty ? step.appName : step.windowTitle
        return title.uppercased()
    }
}

private struct ReaderTabBar: View {
    @Binding var selection: ReaderTab
    @Namespace private var inkSelection

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ReaderTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { selection = tab }
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(CanvasTypography.mark(10)).tracking(1.2)
                        .foregroundStyle(selection == tab ? CanvasPalette.paper : CanvasPalette.ink.opacity(0.54))
                        .frame(width: 96, height: 34)
                        .background {
                            if selection == tab {
                                InkPillShape(variation: tab == .raw ? 0 : 1)
                                    .fill(CanvasPalette.inkBlue)
                                    .matchedGeometryEffect(id: "ink-tab", in: inkSelection)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CanvasPalette.paper.opacity(0.88), in: InkPillShape(variation: 2))
        .overlay(InkPillShape(variation: 2).stroke(CanvasPalette.inkBlue.opacity(0.13)))
        .shadow(color: CanvasPalette.clay.opacity(0.95), radius: 16, y: 5)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct OrganizedEssayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Label(appState.organizedTemplate.rawValue, systemImage: appState.organizedTemplate.icon)
                            .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1)
                            .foregroundStyle(CanvasPalette.inkBlue)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(CanvasPalette.inkBlue.opacity(0.09), in: InkPillShape(variation: 1))
                        Spacer()
                        OrganizationPicker()
                            .environmentObject(appState)
                    }

                    Text(appState.noteTitle)
                        .font(CanvasTypography.essayTitle)

                    if appState.isOrganizing {
                        InkWritingLoader(status: appState.recordingStatus ?? "Organizing your captures…")
                            .frame(maxWidth: .infinity).padding(.vertical, 70)
                    } else if appState.organizedDraft.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("This note has not been organized yet.")
                                .font(CanvasTypography.emptyTitle)
                            Text("Choose a structure and Noted will turn the raw note and captures into one readable page using your configured model.")
                                .font(CanvasTypography.noteBody).lineSpacing(7).opacity(0.58)
                            OrganizationPicker()
                                .environmentObject(appState)
                        }
                        .padding(.vertical, 45)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(essayBlocks.enumerated()), id: \.offset) { _, block in
                                EssayBlockView(block: block)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 58).padding(.vertical, 48)
                .frame(maxWidth: 820, minHeight: proxy.size.height - 48, alignment: .topLeading)
                .background(CanvasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CanvasPalette.inkBlue.opacity(0.10)))
                .shadow(color: CanvasPalette.ink.opacity(0.11), radius: 18, y: 10)
                .padding(.horizontal, max(32, (proxy.size.width - 820) / 2)).padding(.vertical, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var essayBlocks: [EssayBlock] {
        var blocks: [EssayBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in appState.organizedDraft.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                // The page already owns the note title, so avoid repeating the model title.
                flushParagraph()
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                flushParagraph()
                blocks.append(.checklist(String(line.dropFirst(6)), line.hasPrefix("- [x]")))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}

private struct OrganizationPicker: View {
    @EnvironmentObject private var appState: AppState
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Label(appState.organizedDraft.isEmpty ? "Organize" : "Reorganize", systemImage: "sparkles")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 14).frame(height: 38)
                .foregroundStyle(CanvasPalette.paper)
                .background(CanvasPalette.inkBlue, in: InkPillShape(variation: 0))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("SHAPE THIS NOTE")
                        .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(CanvasPalette.inkBlue.opacity(0.58))
                    Spacer()
                    Circle().fill(CanvasPalette.inkBlue.opacity(0.22)).frame(width: 8)
                    Circle().fill(CanvasPalette.inkBlue.opacity(0.12)).frame(width: 4)
                }
                .padding(.horizontal, 10).padding(.bottom, 6)

                ForEach(OrganizationTemplate.allCases) { template in
                    Button {
                        isOpen = false
                        appState.organizeCurrentSession(as: template)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: template.icon).frame(width: 18)
                            Text(template.rawValue)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer()
                            if appState.organizedTemplate == template {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .black))
                            }
                        }
                        .foregroundStyle(appState.organizedTemplate == template ? CanvasPalette.paper : CanvasPalette.ink)
                        .padding(.horizontal, 11).frame(height: 42)
                        .background(appState.organizedTemplate == template ? CanvasPalette.inkBlue : .clear, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12).frame(width: 248)
            .background(CanvasPalette.paper)
            .overlay(alignment: .bottomTrailing) {
                CanvasInkBlob().fill(CanvasPalette.inkBlue.opacity(0.07)).frame(width: 90, height: 70).offset(x: 16, y: 16).clipped()
                    .allowsHitTesting(false)
            }
        }
    }
}

private enum EssayBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    case checklist(String, Bool)
}

private struct EssayBlockView: View {
    let block: EssayBlock

    var body: some View {
        switch block {
        case .heading(let text):
            Text(inlineMarkdown(text))
                .font(CanvasTypography.essayHeading)
                .padding(.top, 14)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(CanvasTypography.essayBody)
                .lineSpacing(9)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(CanvasPalette.inkBlue).frame(width: 6, height: 6)
                Text(inlineMarkdown(text))
                    .font(CanvasTypography.essayBody).lineSpacing(8)
            }
        case .checklist(let text, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(CanvasPalette.inkBlue)
                Text(inlineMarkdown(text))
                    .font(CanvasTypography.essayBody).lineSpacing(8)
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct InkWritingLoader: View {
    let status: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let progress = reduceMotion ? 0.7 : (sin(t * 2.4) + 1) / 2
            VStack(spacing: 18) {
                ZStack {
                    Text("noted")
                        .font(CanvasTypography.loaderWordmark)
                        .foregroundStyle(CanvasPalette.inkBlue)
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CanvasPalette.inkBlue)
                        .rotationEffect(.degrees(-38))
                        .offset(x: CGFloat(progress) * 74 - 37, y: 30)
                    Capsule()
                        .fill(CanvasPalette.inkBlue.opacity(0.75))
                        .frame(width: CGFloat(progress) * 92 + 18, height: 3)
                        .offset(y: 31)
                }
                .frame(height: 62)
                Text(status).font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.48)
            }
        }
    }
}

private struct LiveCaptureCard: View {
    let step: ExplorationStep
    let height: CGFloat

    var body: some View {
        // The card IS the capture. Everything else is a caption around it:
        // one mono line above, one below. The thought field is deliberately
        // absent — a note belongs beside its capture, not inside it, and
        // while it lived here it pushed the screenshot down to under half
        // the card.
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(kindLabel) · \(step.timestamp.formatted(date: .omitted, time: .shortened))".uppercased())
                Spacer()
                Image(systemName: kindIcon)
            }
            .font(.custom("GeistMono-Medium", size: 10)).tracking(1.1).opacity(0.48)

            if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                // Fills the card. `scaledToFit` against an unbounded frame
                // grows the image until one axis meets the container, so the
                // whole capture stays visible — scaledToFill would fill too,
                // but by cropping the screenshot, which loses the thing the
                // user actually kept.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let text = primaryText, !text.isEmpty {
                // A text or voice capture has no image, so the words are the
                // capture and they get the same room the screenshot would.
                ScrollView {
                    Text(text)
                        .font(CanvasTypography.noteBody)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                if let url = step.url, let destination = URL(string: url) {
                    Link(sourceLabel, destination: destination)
                        .font(.custom("GeistMono-Medium", size: 10)).tracking(0.9)
                        .foregroundStyle(CanvasPalette.inkBlue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(sourceLabel)
                        .font(CanvasTypography.markRegular(10)).tracking(0.9)
                        .opacity(0.55)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                // When the capture came from a page, the source label is
                // already that page's host — printing it again as a link
                // just says the same word twice. Link the full URL instead,
                // and only when it adds something.
                if let url = step.url, let destination = URL(string: url),
                   let host = destination.host(), host.uppercased() != sourceLabel {
                    Link(host, destination: destination)
                        .font(.custom("GeistMono-Medium", size: 10))
                        .foregroundStyle(CanvasPalette.inkBlue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(24).frame(maxWidth: .infinity).frame(height: height)
        .background(CanvasPalette.paper.opacity(0.93), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CanvasPalette.ink.opacity(0.11)))
        .shadow(color: CanvasPalette.ink.opacity(0.12), radius: 18, y: 10)
    }

    private var primaryText: String? { step.selectedText ?? step.pageText }

    /// "Notefy" is the app capturing, not the thing captured — showing it
    /// as the card's headline told the user nothing. Same mapping the
    /// dashboard and the capture-review panel already use.
    private var sourceLabel: String {
        if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host.uppercased() }
        if step.appName == "Audio" { return "COMPUTER AUDIO" }
        if ["Notefy", "Noted", "notefy-app"].contains(step.appName) { return "SCREEN REGION" }
        let title = step.windowTitle.isEmpty ? step.appName : step.windowTitle
        return title.uppercased()
    }
    private var kindLabel: String { step.screenshotPath != nil ? "Capture" : (step.appName.localizedCaseInsensitiveContains("audio") ? "Voice" : "Text") }
    private var kindIcon: String { step.screenshotPath != nil ? "photo" : (step.appName.localizedCaseInsensitiveContains("audio") ? "waveform" : "text.alignleft") }
}

/// The folder list, expandable. Choosing a folder used to filter the canvas
/// and close — which meant the only way to see what was inside a folder was
/// to dismiss the list and look at the grid. Now a folder opens in place and
/// shows its notes, so this is a navigator rather than a filter menu.
///
/// The two plus buttons are deliberately different verbs and sit where their
/// scope is: the one in the header makes a FOLDER, and the one at the foot of
/// an open folder's note list makes a NOTE in that folder.
private struct CanvasFolderOverlay: View {
    @EnvironmentObject private var appState: AppState
    @Binding var filter: CanvasFolderFilter
    @Binding var isOpen: Bool
    let notes: [CanvasNoteSnapshot]
    /// The note currently open, so the list can show you where you are —
    /// this dropdown is the only navigation left.
    let activeURL: URL?
    let openNote: (URL) -> Void
    let createNote: (UUID?) -> Void

    @State private var creatingFolder = false
    @State private var newFolderName = ""
    @State private var expanded: Set<CanvasFolderFilter> = []
    @State private var didSeedExpansion = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.06).ignoresSafeArea().onTapGesture { withAnimation { isOpen = false } }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("FOLDERS")
                        .font(CanvasTypography.mark(10)).tracking(1.5).opacity(0.48)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { creatingFolder = true }
                        DispatchQueue.main.async { nameFocused = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(CanvasPalette.inkBlue.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New folder")
                    .accessibilityLabel("New folder")
                }
                .padding(.bottom, 8)

                if creatingFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(CanvasPalette.inkBlue)
                        TextField("Folder name", text: $newFolderName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .focused($nameFocused)
                            .onSubmit(createFolder)
                            .onExitCommand(perform: cancelFolder)
                        Button(action: createFolder) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(CanvasPalette.inkBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        folderSection("All notes", value: .all, notes: notes)
                        folderSection("Unfiled", value: .unfiled, notes: notes.filter { $0.folderID == nil })
                        if !appState.workspace.folders.isEmpty {
                            Divider().opacity(0.18).padding(.vertical, 5)
                        }
                        ForEach(appState.workspace.folders) { folder in
                            folderSection(
                                appState.folderPath(for: folder.id),
                                value: .folder(folder.id),
                                notes: notes.filter { $0.folderID == folder.id }
                            )
                        }
                    }
                }
                .frame(maxHeight: 420)
                .scrollIndicators(.hidden)
            }
            .padding(16).frame(width: 300)
            .background(CanvasPalette.paper.opacity(0.98), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(CanvasPalette.ink.opacity(0.10)))
            .shadow(color: CanvasPalette.ink.opacity(0.18), radius: 26, y: 13)
            .padding(.leading, 24).padding(.top, 70)
        }
        .onAppear {
            guard !didSeedExpansion else { return }
            didSeedExpansion = true
            // Land on the folder holding the open note, rather than making
            // the user hunt for where they already are.
            if let activeURL,
               let snapshot = notes.first(where: { $0.url == activeURL }) {
                expanded.insert(snapshot.folderID.map { CanvasFolderFilter.folder($0) } ?? .unfiled)
            } else {
                expanded.insert(.all)
            }
        }
    }

    @ViewBuilder
    private func folderSection(_ title: String, value: CanvasFolderFilter, notes folderNotes: [CanvasNoteSnapshot]) -> some View {
        let isExpanded = expanded.contains(value)
        VStack(alignment: .leading, spacing: 2) {
            Button {
                filter = value
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    if isExpanded { expanded.remove(value) } else { expanded.insert(value) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(0.45)
                    Text(title).lineLimit(1)
                    Spacer()
                    Text("\(folderNotes.count)")
                        .font(.custom("GeistMono-Regular", size: 11))
                        .opacity(0.46)
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(filter == value ? CanvasPalette.inkBlue.opacity(0.11) : .clear,
                        in: RoundedRectangle(cornerRadius: 11))

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(folderNotes) { note in
                        let isCurrent = note.url == activeURL
                        Button {
                            withAnimation { isOpen = false }
                            guard !isCurrent else { return }
                            openNote(note.url)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(CanvasPalette.inkBlue.opacity(isCurrent ? 0.9 : (note.captureCount > 0 ? 0.55 : 0.18)))
                                    .frame(width: 5, height: 5)
                                Text(note.title).lineLimit(1)
                                Spacer()
                                if note.captureCount > 0 {
                                    Text("\(note.captureCount)")
                                        .font(CanvasTypography.markRegular(10))
                                        .opacity(0.40)
                                }
                            }
                            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                            .padding(.horizontal, 12).frame(height: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isCurrent ? CanvasPalette.inkBlue.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Scoped to the folder it sits under, so there is never a
                    // question of where the new note lands.
                    Button {
                        withAnimation { isOpen = false }
                        if case .folder(let id) = value { createNote(id) } else { createNote(nil) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("New note").font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(CanvasPalette.inkBlue)
                        .padding(.horizontal, 12).frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = appState.createFolder(name: name)
        filter = .folder(id)
        expanded.insert(.folder(id))
        newFolderName = ""
        creatingFolder = false
    }

    private func cancelFolder() {
        newFolderName = ""
        withAnimation { creatingFolder = false }
    }
}

/// A code-drawn counterpart to a stepped PNG ink sprite: the mask advances in
/// deliberate frames, covers the canvas, then breaks apart to reveal the note.
private struct InkOpenTransition: View {
    let frame: Int
    let origin: CGPoint?

    private let coverFrameCount = 16
    private let revealFrameCount = 20

    var body: some View {
        Canvas { context, size in
            if frame < coverFrameCount {
                drawLandingSplashes(in: &context, size: size)
            } else {
                drawRecedingInk(in: &context, size: size)
            }
        }
        .background(Color.clear)
        .accessibilityHidden(true)
    }

    private func drawLandingSplashes(in context: inout GraphicsContext, size: CGSize) {
        let progress = CGFloat(frame + 1) / CGFloat(coverFrameCount)
        let center = CGPoint(
            x: min(max(origin?.x ?? size.width / 2, 0), size.width),
            y: min(max(origin?.y ?? size.height / 2, 0), size.height)
        )
        let farthestX = max(center.x, size.width - center.x)
        let farthestY = max(center.y, size.height - center.y)
        let maximumRadius = hypot(farthestX, farthestY) * 1.22

        // One continuous bloom grows from the chosen card. A broad ease-out
        // gives it the fluid acceleration of pigment dispersing in water.
        let eased = 1 - pow(1 - progress, 2.55)
        let impact = sin(progress * .pi) * 0.045
        let radius = maximumRadius * (eased + impact)
        context.fill(
            organicSplat(center: center, radius: radius, seed: 17),
            with: .color(CanvasPalette.inkBlue)
        )

        // Small droplets stay tied to the same radial wavefront, avoiding a
        // second, unrelated animation while keeping the edge organically wet.
        for index in 0..<5 where progress > CGFloat(index) * 0.035 {
            let angle = CGFloat(index) * 1.27 - 0.6
            let distance = radius * (0.70 + CGFloat(index % 2) * 0.11)
            let dropletRadius = max(2, radius * (0.018 + CGFloat(index % 3) * 0.004))
            let dropletCenter = CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance * 0.82
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: dropletCenter.x - dropletRadius,
                    y: dropletCenter.y - dropletRadius,
                    width: dropletRadius * 2,
                    height: dropletRadius * 1.55
                )),
                with: .color(CanvasPalette.inkBlue)
            )
        }
    }

    private func organicSplat(center: CGPoint, radius: CGFloat, seed: Int) -> Path {
        let pointCount = 34
        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)

        for index in 0..<pointCount {
            let angle = CGFloat(index) / CGFloat(pointCount) * 2 * .pi
            let seedPhase = CGFloat(seed) * 0.73
            let roughness = 0.88
                + sin(angle * 3 + seedPhase) * 0.08
                + sin(angle * 7 - seedPhase * 1.4) * 0.045
            let xRadius = radius * roughness
            let yRadius = radius * 0.82 * roughness
            points.append(CGPoint(
                x: center.x + cos(angle) * xRadius,
                y: center.y + sin(angle) * yRadius
            ))
        }

        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in points.indices {
            let point = points[index]
            let next = points[(index + 1) % points.count]
            let midpoint = CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2)
            path.addQuadCurve(to: midpoint, control: point)
        }
        path.closeSubpath()
        return path
    }

    /// The reveal used to punch a 6x5 grid of blooms out of the ink with a
    /// destinationOut layer. Those openings ARE the holes — thirty of them,
    /// appearing all over the screen at once, each one showing a hard-edged
    /// patch of the page behind. It also read as a completely different
    /// gesture from the cover, which is one mass growing.
    ///
    /// So the reveal is now the cover played backwards: a single body of ink
    /// contracting and drifting off, with a couple of droplets outrunning it.
    /// No layers, no blend modes, and nothing that can open a hole.
    private func drawRecedingInk(in context: inout GraphicsContext, size: CGSize) {
        let revealIndex = frame - coverFrameCount + 1
        let progress = min(1, CGFloat(revealIndex) / CGFloat(revealFrameCount))

        let center = CGPoint(
            x: min(max(origin?.x ?? size.width / 2, 0), size.width),
            y: min(max(origin?.y ?? size.height / 2, 0), size.height)
        )
        let farthestX = max(center.x, size.width - center.x)
        let farthestY = max(center.y, size.height - center.y)
        let maximumRadius = hypot(farthestX, farthestY) * 1.22

        // Holds a beat at full cover, then pulls away quickly — pigment
        // being drawn off the page rather than fading out.
        let eased = pow(progress, 1.7)
        let radius = maximumRadius * (1 - eased)
        guard radius > 0.5 else { return }

        // A slight drift as it goes, so it reads as withdrawing rather than
        // as a circle shrinking on the spot.
        let drift = eased * maximumRadius * 0.10
        let recedingCenter = CGPoint(x: center.x - drift * 0.35, y: center.y + drift)

        context.fill(
            organicSplat(center: recedingCenter, radius: radius, seed: 23),
            with: .color(CanvasPalette.inkBlue)
        )

        // Droplets that broke away as it pulled back. They shrink out rather
        // than being erased, so they never leave a gap behind them.
        for index in 0..<4 {
            let angle = CGFloat(index) * 1.61 + 0.4
            let distance = radius * (0.74 + CGFloat(index % 2) * 0.13)
            let dropletRadius = max(0, radius * (0.020 + CGFloat(index % 3) * 0.005))
            guard dropletRadius > 0.5 else { continue }
            let dropletCenter = CGPoint(
                x: recedingCenter.x + cos(angle) * distance,
                y: recedingCenter.y + sin(angle) * distance * 0.82
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: dropletCenter.x - dropletRadius,
                    y: dropletCenter.y - dropletRadius,
                    width: dropletRadius * 2,
                    height: dropletRadius * 1.55
                )),
                with: .color(CanvasPalette.inkBlue)
            )
        }
    }
}

/// Editorial Ink: warm ivory paper, near-black indigo ink, and almost
/// nothing else. The grounds shed the peach cast the clay ramp carried —
/// archival paper is warm but not pink, and the pink was reading as a
/// product colour rather than as a material.
private enum CanvasPalette {
    static let clay = Color(hex: 0xF3ECDE)      // ivory ground
    static let clayLight = Color(hex: 0xFAF5EB) // the lift within it
    static let clayMid = Color(hex: 0xEBE2D1)
    static let clayLow = Color(hex: 0xE0D5C0)
    static let paper = Color(hex: 0xFDFAF4)     // the sheet a card is cut from
    static let paperDim = Color(hex: 0xF8F2E7)
    static let paperEdge = Color(hex: 0xE9DFCC)

    static let ink = Color(hex: 0x17142B)       // near-black indigo
    static let inkBlue = Color(hex: 0x2A2456)
    static let inkBlueDeep = Color(hex: 0x1F1A42)
    /// Faded indigo — secondary states, quiet marks. Not grey: a grey here
    /// reads as disabled, a faded indigo reads as further from the pen.
    static let inkBlueLight = Color(hex: 0x6B6688)
    static let warmShadow = Color(hex: 0x6E5B3E)

    /// Cards are cut from the same sheet but not the same part of it. A tiny
    /// deterministic tonal shift per card keeps a grid from looking printed
    /// in one pass — felt only as slight unevenness, never as colour.
    static func sheet(for id: UUID) -> Color {
        let tones: [UInt32] = [0xFDFAF4, 0xFCF8F1, 0xFBF6EE, 0xFDF9F2]
        let bucket = abs(id.hashValue) % tones.count
        return Color(hex: tones[bucket])
    }
}

/// Three voices, each with a job — the Editorial Ink brief's type system.
///
/// Instrument Serif carries the editorial moments: note titles, essay
/// headings, empty states. It is a display face with real personality and
/// tight fit, which is why it is never asked to set body copy.
///
/// Geist Sans is the interface: body, controls, navigation. Neutral on
/// purpose, so the serif is the only thing raising its voice.
///
/// IBM Plex Mono is the record: timestamps, source labels, system marks.
/// Its slightly mechanical letterforms are what make a metadata line read as
/// stamped onto the page rather than written on it.
///
/// All three are PostScript names, because Font.custom fails silently to San
/// Francisco on a miss and a typo here looks like a design choice.
private enum CanvasTypography {
    // Editorial — Instrument Serif. It runs small for its point size, so the
    // sizes here are larger than the sans they replaced at the same role.
    static let wordmark = Font.custom("InstrumentSerif-Regular", size: 38, relativeTo: .title)
    static let loaderWordmark = Font.custom("InstrumentSerif-Regular", size: 52, relativeTo: .largeTitle)
    static let noteTitle = Font.custom("InstrumentSerif-Regular", size: 46, relativeTo: .largeTitle)
    static let essayTitle = Font.custom("InstrumentSerif-Regular", size: 50, relativeTo: .largeTitle)
    static let essayHeading = Font.custom("InstrumentSerif-Regular", size: 30, relativeTo: .title2)
    static let emptyTitle = Font.custom("InstrumentSerif-Regular", size: 25, relativeTo: .title3)
    static let cardTitle = Font.custom("InstrumentSerif-Regular", size: 30, relativeTo: .title)

    // Interface — Geist.
    static let noteBody = Font.custom("Geist-Regular", size: 16, relativeTo: .body)
    static let essayBody = Font.custom("Geist-Regular", size: 16, relativeTo: .body)
    static let cardBody = Font.custom("Geist-Regular", size: 14, relativeTo: .body)
    static let control = Font.custom("Geist-Medium", size: 13)

    // The record — IBM Plex Mono.
    static func mark(_ size: CGFloat = 10) -> Font {
        .custom("IBMPlexMono-Medium", size: size)
    }
    static func markRegular(_ size: CGFloat = 10) -> Font {
        .custom("IBMPlexMono-Regular", size: size)
    }
}

private enum NotedInkAssets {
    /// The splat mark: a single unbroken line that lands as an ink splash and
    /// resolves into a lowercase n. Generated from Sanjana's third concept,
    /// keyed off its background and normalised to the app's cobalt so it can
    /// be tinted as a template image on any surface.
    /// The nib: a fountain pen point, drop removed. A simple bold silhouette
    /// that still reads at 20pt, which neither the monoline splat nor the
    /// solid one managed — a mark has to survive the smallest place it runs.
    static let nib = load("noted-nib", "png")
    static let splat = load("noted-splat", "png")
    static let mark = load("noted-mark", "svg")

    private static func load(_ name: String, _ ext: String) -> NSImage? {
        let moduleURL = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "NotedInk")
            ?? Bundle.module.url(forResource: name, withExtension: ext)
        guard let moduleURL else { return nil }
        let image = NSImage(contentsOf: moduleURL)
        image?.isTemplate = true
        return image
    }
}

private struct CanvasBrandMark: View {
    var body: some View {
        Text("noted")
            .font(CanvasTypography.wordmark)
            .tracking(-0.5)
            .foregroundStyle(CanvasPalette.ink)
            .frame(width: 112, height: 42)
            .accessibilityLabel("Noted")
    }
}

private struct CanvasBrandIcon: View {
    var body: some View {
        Group {
            if let mark = NotedInkAssets.nib ?? NotedInkAssets.splat ?? NotedInkAssets.mark {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(CanvasPalette.inkBlue)
            } else {
                Image(systemName: "folder.fill")
            }
        }
        // 22pt, not the 18 the old folder glyph used: the splat carries an
        // interior counter, and below about this size the n inside it closes
        // up and the whole mark reads as a smudge.
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

private struct CanvasInkBlob: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.07, y: rect.minY + rect.height * 0.45))
        path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.03), control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.13), control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.32), control1: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.08), control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.03))
        path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY + rect.height * 0.94), control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.68), control2: CGPoint(x: rect.minX + rect.width * 0.89, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.07, y: rect.minY + rect.height * 0.45), control1: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75))
        return path
    }
}

/// A softly irregular control silhouette: legible as a button, but with the
/// slight edge tension of ink settling into paper instead of a perfect capsule.
private struct InkPillShape: Shape {
    let variation: Int

    func path(in rect: CGRect) -> Path {
        let v = variation % 3
        let topInset = v == 1 ? rect.height * 0.055 : rect.height * 0.025
        let bottomInset = v == 2 ? rect.height * 0.045 : rect.height * 0.015
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.height * 0.52, y: rect.minY + topInset))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.height * 0.43, y: rect.minY + (v == 0 ? rect.height * 0.015 : rect.height * 0.07)),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY - rect.height * 0.025),
            control2: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY + rect.height * 0.075)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.height * 0.05, y: rect.midY + rect.height * 0.05),
            control1: CGPoint(x: rect.maxX - rect.height * 0.12, y: rect.minY + rect.height * 0.05),
            control2: CGPoint(x: rect.maxX + rect.height * 0.015, y: rect.midY - rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.height * 0.50, y: rect.maxY - bottomInset),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.15),
            control2: CGPoint(x: rect.maxX - rect.height * 0.20, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.height * 0.42, y: rect.maxY - rect.height * 0.035),
            control1: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.maxY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY - rect.height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.height * 0.04, y: rect.midY - rect.height * 0.02),
            control1: CGPoint(x: rect.minX + rect.height * 0.14, y: rect.maxY - rect.height * 0.07),
            control2: CGPoint(x: rect.minX - rect.height * 0.015, y: rect.midY + rect.height * 0.20)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.height * 0.52, y: rect.minY + topInset),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16),
            control2: CGPoint(x: rect.minX + rect.height * 0.21, y: rect.minY + rect.height * 0.04)
        )
        path.closeSubpath()
        return path
    }
}

/// The blobs are gone. Six large ink shapes drifting behind the cards read
/// as decoration a template shipped with, and they were the loudest thing on
/// a screen whose actual job is to let you scan and rearrange your own work.
/// What replaces them does the same job — stop the ground being a dead flat
/// fill — without ever becoming an object: a quiet warm gradient, a fine
/// grain that reads as paper tooth rather than as shapes, and a vignette
/// that lets the corners fall away so the cards sit on a surface.
private struct CanvasClayBackground: View {
    let focused: Bool
    let zoom: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let diagonal = sqrt(proxy.size.width * proxy.size.width + proxy.size.height * proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: [CanvasPalette.clayLight, CanvasPalette.clay],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // A single wide warm lift, well off-centre and far too soft to
                // have an edge you could point at. Felt, not seen.
                RadialGradient(
                    colors: [CanvasPalette.paper.opacity(0.55), CanvasPalette.paper.opacity(0)],
                    center: UnitPoint(x: 0.30, y: 0.16),
                    startRadius: 0,
                    endRadius: diagonal * 0.72
                )

                CanvasGrain()

                RadialGradient(
                    colors: [.clear, CanvasPalette.warmShadow.opacity(0.10)],
                    center: .center,
                    startRadius: diagonal * 0.30,
                    endRadius: diagonal * 0.74
                )
            }
            // Reading dims the ground so the sheet in front of it carries the
            // eye; the canvas gets it at full strength.
            .opacity(focused ? 0.82 : 1)
            .animation(.easeOut(duration: 0.44), value: focused)
        }
        .ignoresSafeArea()
    }
}

/// Paper tooth. Sparse enough to be felt rather than seen — dense specks
/// average into a grey cast and take the warmth of the clay with them.
private struct CanvasGrain: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 17)
            let count = Int(size.width * size.height / 9)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black))
            }
        }
        .blendMode(.multiply)
        .opacity(0.030)
        .allowsHitTesting(false)
    }
}

