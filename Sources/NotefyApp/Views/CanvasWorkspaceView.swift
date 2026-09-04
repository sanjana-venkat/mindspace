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
    /// The frame counts the running wipe was started with, so the overlay
    /// maps progress against the same numbers the loop is stepping.
    @State private var inkCoverFrames = 16
    @State private var inkRevealFrames = 20
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
                InkOpenTransition(frame: inkTransitionFrame,
                                  origin: nil,
                                  coverFrames: inkCoverFrames,
                                  revealFrames: inkRevealFrames)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                    .zIndex(20)
            }
        }
        .focusable()
        .focusEffectDisabled()
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
        inkWipe(cover: 16, reveal: 20, interval: Self.noteWipeInterval) {
            appState.openNote(url)
        }
    }

    /// Grid and panel are two views of the same note, so the change is worth
    /// the same beat: the ink covers, the layout swaps behind it, the ink
    /// pulls back. Without it the whole page silently becomes something else.
    private func setLayout(_ option: ReaderLayout) {
        guard option.rawValue != layoutRaw else { return }
        // Twelve frames, not thirty-six. Shaving the interval had stopped
        // helping: Task.sleep does not deliver 4ms, so the frame COUNT was
        // setting the duration, not the number I kept lowering.
        inkWipe(cover: 5, reveal: 7, interval: Self.layoutWipeInterval) {
            layoutRaw = option.rawValue
        }
    }

    /// Cover, change, reveal. The change happens at the midpoint so it is
    /// never seen happening.
    /// Opening a note is a rarer, heavier move and keeps the full beat.
    /// Flipping posture is something you do repeatedly while working, so it
    /// runs the same 36 frames at a shorter interval — same gesture, roughly
    /// two-thirds the time, so it still reads as ink rather than a cut.
    private static let noteWipeInterval = 28
    /// Flipping posture happens constantly while working, so it runs the
    /// same gesture at roughly a third of the note-switch duration — about
    /// 290ms end to end. Any slower and it is a wait, not a transition.
    private static let layoutWipeInterval = 8

    private func inkWipe(cover: Int, reveal: Int, interval: Int, _ change: @escaping () -> Void) {
        guard inkTransitionFrame == nil else { return }

        guard !reduceMotion else {
            change()
            return
        }

        inkCoverFrames = cover
        inkRevealFrames = reveal

        Task { @MainActor in
            let coverFrames = cover
            let revealFrames = reveal

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

/// Chrome with the containers removed. The pills, the capsule toolbars and
/// the filled toggle were generic app chrome — they belong to any Electron
/// app. What is left is line icons on the page, and a printer's mark under
/// whichever one is active.
private struct CanvasToolbar: View {
    let title: String
    let subtitle: String
    @Binding var foldersOpen: Bool
    @Binding var settingsOpen: Bool
    @Binding var zoom: CGFloat

    var body: some View {
        // The wordmark owns the window's actual centre. Left in the HStack it
        // was pushed off it: the breadcrumb caps at 320 and the chrome at
        // 420, so the spacers do not balance and "noted" sat left of the tab
        // bar below it.
        ZStack {
            HStack(alignment: .center) {
                breadcrumb
                Spacer()
                chrome
            }
            wordmark
        }
        .padding(.horizontal, CanvasPalette.pageMargin)
        .padding(.top, 26)
    }

    /// No pill. The folder sits in meta italic, the note in the text face, a
    /// caret after it — set on the page rather than in a container.
    private var breadcrumb: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { foldersOpen.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(subtitle)
                    .font(CanvasTypography.meta())
                    .foregroundStyle(CanvasPalette.ink55)
                Text(title)
                    .font(CanvasTypography.text(15))
                    .foregroundStyle(CanvasPalette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(CanvasPalette.ink55)
                    .rotationEffect(.degrees(foldersOpen ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 320, alignment: .leading)
    }

    /// Mark and wordmark as one lockup. On its own in the breadcrumb the nib
    /// read as a toolbar icon; set beside the word at the optical size of the
    /// cap height, with real air between them, it reads as a masthead.
    /// Wordmark only for now — the mark is out until it is redrawn.
    private var wordmark: some View {
        Text("noted")
            .font(CanvasTypography.wordmark)
            .tracking(-0.02 * 28)
            .foregroundStyle(CanvasPalette.ink)
            .accessibilityLabel("Noted")
    }

    /// Zoom, the layout toggles and settings share one baseline at 22px
    /// apart. The toggles used to float in their own row below, which read
    /// as a second toolbar.
    /// Two rows, right-aligned to the same edge: zoom and settings above,
    /// the posture toggles directly beneath them.
    private var chrome: some View {
        HStack(alignment: .center, spacing: 22) {
            lineButton("minus", label: "Zoom out") { zoom = max(0.60, zoom - 0.10) }
            Text("\(Int(zoom * 100))%")
                .font(CanvasTypography.data())
                .foregroundStyle(CanvasPalette.ink45)
                .monospacedDigit()
            lineButton("plus", label: "Zoom in") { zoom = min(1.40, zoom + 0.10) }
            lineButton("gearshape", label: "Settings") { settingsOpen = true }
        }
        .frame(maxWidth: 420, alignment: .trailing)
    }

    private func lineButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(CanvasPalette.ink70)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The active-state mark: a 6px ink dot beneath the control, the way a
/// printer marks a plate. Not a filled button.
private struct PrintersMark: View {
    let active: Bool
    var body: some View {
        Circle()
            .fill(CanvasPalette.ink)
            .frame(width: 6, height: 6)
            .opacity(active ? 1 : 0)
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
    @State private var captureTick = 0

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

            ZStack {
                ReaderTabBar(selection: $tab)
                HStack {
                    Spacer()
                    ReaderLayoutToggle(layout: layout, setLayout: setLayout)
                }
                .padding(.horizontal, CanvasPalette.pageMargin)
            }
            .padding(.top, 88)
            .zIndex(2)

            // Where a new capture arrives — the top of the stream.
            InkCaptureBloom(trigger: captureTick)
                .padding(.top, 150)
                .frame(maxWidth: .infinity, alignment: .center)
                .zIndex(1)

        }
        .onChange(of: appState.steps.count) { previous, current in
            if current > previous { captureTick += 1 }
        }
    }

    /// A typeset text column: title, a short drop rule, then body on a 62ch
    /// measure. No eyebrow — the title's size is the hierarchy.
    private var rawNoteColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Untitled note", text: $appState.noteTitle)
                .textFieldStyle(.plain)
                .font(CanvasTypography.noteTitleReader)
                .tracking(-0.02 * 56)
                .foregroundStyle(CanvasPalette.ink)
                .onChange(of: appState.noteTitle) { appState.scheduleActiveNoteAutosave() }

            Rectangle()
                .fill(CanvasPalette.ink)
                .frame(width: 56, height: 1.5)

            ZStack(alignment: .topLeading) {
                if activeNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write the note you want to keep beside these captures…")
                        .font(CanvasTypography.meta(14))
                        .foregroundStyle(CanvasPalette.ink30)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: activeNoteBinding)
                    .id(activeCaptureID)
                    .font(CanvasTypography.text())
                    .lineSpacing(CanvasTypography.leading(15.5))
                    .foregroundStyle(CanvasPalette.ink)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
        .padding(.horizontal, CanvasPalette.pageMargin)
        .padding(.top, 108).padding(.bottom, 32)
        // The column divider is a single hairline, not a fill.
        .overlay(alignment: .trailing) {
            Rectangle().fill(CanvasPalette.ink12).frame(width: 1)
        }
    }

    /// Fragments as marginalia: the same plates as grid view, narrower.
    private var captureColumn: some View {
        Group {
            if appState.steps.isEmpty {
                VStack(spacing: 10) {
                    Text("Nothing captured yet")
                        .font(CanvasTypography.display(24, 300))
                        .foregroundStyle(CanvasPalette.ink)
                    Text("Use Kami or a capture shortcut to add the first fragment.")
                        .font(CanvasTypography.meta(14))
                        .foregroundStyle(CanvasPalette.ink55)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: CanvasPalette.gutter) {
                        ForEach(Array(appState.steps.reversed())) { step in
                            GridCaptureTile(
                                step: step,
                                selected: step.id == activeCaptureID,
                                placement: .marginal,
                                note: Binding(
                                    get: { appState.stepAnnotations[step.id] ?? "" },
                                    set: {
                                        appState.stepAnnotations[step.id] = $0
                                        appState.scheduleActiveNoteAutosave()
                                    }
                                )
                            )
                            .id(step.id)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.16)) { activeCaptureID = step.id }
                            }
                        }
                    }
                    .padding(.horizontal, CanvasPalette.pageMargin)
                    .padding(.vertical, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// The posture switch. Sits opposite the Raw/Organized tabs rather than in
/// the window toolbar, because it changes what THIS note looks like, not what
/// the app is doing.
/// The posture switch, given the same treatment as Raw/Organized.
///
/// It used to mark the active side with a 6px printer's dot underneath,
/// which was the editorial brief's instruction and was genuinely too quiet:
/// two near-identical grey glyphs with a speck under one of them does not
/// tell you which view you are in. It now carries the same filled ink shape
/// the tab bar uses — a track, and the live side sitting in ink — so the two
/// controls read as one family and the state is unmissable.
private struct ReaderLayoutToggle: View {
    let layout: ReaderLayout
    let setLayout: (ReaderLayout) -> Void
    @Namespace private var inkSelection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReaderLayout.allCases) { option in
                let active = option == layout
                Button {
                    guard !active else { return }
                    setLayout(option)
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(active ? CanvasPalette.paperPlate : CanvasPalette.ink55)
                        .frame(width: 38, height: 26)
                        .background {
                            if active {
                                // Calmer than Raw's blob and busier than a
                                // plain capsule: the same ink, one step down
                                // in voice, because this is chrome and the
                                // tab bar is the brand moment.
                                // Clean pills here: this is chrome, and the
                                // wandering edge is reserved for the tab bar,
                                // which is the brand moment.
                                Capsule()
                                    .fill(CanvasPalette.accent)
                                    .matchedGeometryEffect(id: "ink-layout", in: inkSelection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.rawValue)
                .accessibilityLabel(option.rawValue)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(CanvasPalette.paperPlate.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(CanvasPalette.ink12, lineWidth: 1))
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: layout)
    }
}

/// Grid view: the whole note laid out at once. The note itself is the first
/// tile rather than a separate column, because in this posture it is one more
/// thing you place — captures reorder around it by drag, and the order is the
/// note's own order, persisted the same way the canvas persists note order.
private struct CaptureGridView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var activeCaptureID: UUID?

    @State private var draggingID: UUID?
    @FocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    head
                    masonry(width: proxy.size.width)
                }
                .padding(.horizontal, CanvasPalette.pageMargin)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
            // Focusable so the arrow keys reach it — but without the system
            // focus ring, which on a full-width scroll view draws as a blue
            // rule straight across the page the moment anything is selected.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { nudge(-1) }
            .onKeyPress(.rightArrow) { nudge(1) }
            .onDrop(of: [.utf8PlainText, .plainText, .text], isTargeted: nil) { _ in
                draggingID = nil
                return false
            }
        }
        .overlay {
            if appState.steps.isEmpty { emptyState }
        }
    }

    /// Headline, then a short drop rule. No eyebrow: the title's size IS the
    /// hierarchy, which is the whole correction here.
    private var head: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Untitled note", text: $appState.noteTitle)
                .textFieldStyle(.plain)
                .font(CanvasTypography.noteTitleGrid)
                .tracking(CanvasTypography.titleTracking)
                .foregroundStyle(CanvasPalette.ink)
                .focused($titleFocused)
                .onChange(of: appState.noteTitle) { appState.scheduleActiveNoteAutosave() }

            Rectangle()
                .fill(CanvasPalette.ink)
                .frame(width: 56, height: 1.5)

            TextField("", text: Binding(
                get: { appState.rawDraft },
                set: { appState.rawDraft = $0; appState.scheduleActiveNoteAutosave() }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(CanvasTypography.text())
            .lineSpacing(CanvasTypography.bodyLineSpacing)
            .foregroundStyle(CanvasPalette.ink)
            .lineLimit(1...10)
            .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
        }
        .padding(.top, 8)
    }

    /// Content-sized plates in columns, so a two-line fragment is a two-line
    /// plate instead of a tall empty box. SwiftUI has no masonry, and a
    /// LazyVGrid row is only as short as its tallest cell — hence real
    /// columns, filled round-robin.
    private func masonry(width: CGFloat) -> some View {
        let available = width - CanvasPalette.pageMargin * 2
        // Denser than the brief's breakpoints: reordering only means
        // something when you can see enough plates at once to compare them.
        let columns = available >= 940 ? 3 : (available >= 620 ? 2 : 1)
        let ordered = Array(appState.steps.reversed())
        return HStack(alignment: .top, spacing: CanvasPalette.gutter) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: CanvasPalette.gutter) {
                    ForEach(Array(ordered.enumerated()).filter { $0.offset % columns == column },
                            id: \.element.id) { _, step in
                        plate(step)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func plate(_ step: ExplorationStep) -> some View {
        GridCaptureTile(
            step: step,
            selected: step.id == activeCaptureID,
            note: binding(for: step)
        )
        .id(step.id)
        .opacity(draggingID == step.id ? 0.35 : 1)
        .simultaneousGesture(TapGesture().onEnded { activeCaptureID = step.id })
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

    private func binding(for step: ExplorationStep) -> Binding<String> {
        Binding(
            get: { appState.stepAnnotations[step.id] ?? "" },
            set: {
                appState.stepAnnotations[step.id] = $0
                appState.scheduleActiveNoteAutosave()
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing captured yet")
                .font(CanvasTypography.display(26, 300))
                .foregroundStyle(CanvasPalette.ink)
            Text("Use Kami or a capture shortcut to add the first fragment.")
                .font(CanvasTypography.meta(14))
                .foregroundStyle(CanvasPalette.ink55)
        }
    }

    private func nudge(_ delta: Int) -> KeyPress.Result {
        guard !appState.steps.isEmpty else { return .ignored }
        guard let id = activeCaptureID else {
            activeCaptureID = appState.steps.reversed().first?.id
            return .handled
        }
        withAnimation(.easeOut(duration: 0.16)) {
            _ = appState.nudgeCapture(id, by: delta)
        }
        return .handled
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
/// The editor's slip: the note you wrote, laid on the clipping and taped
/// down. Paper a shade lighter than the card it sits on, a fraction off
/// The fragment marks from assets/fragment-glyphs.svg, drawn as paths at a
/// 1px stroke on a 14x14 box. Line icons only — the brief bans filled icons,
/// and a filled glyph beside italic meta would read as a badge.
private struct FragmentGlyph: View {
    enum Kind { case voice, capture, text, audio }
    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 14
            func p(_ build: (inout Path) -> Void) -> Path {
                var path = Path(); build(&path)
                return path.applying(CGAffineTransform(scaleX: s, y: s))
            }
            let stroke = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            let shading = GraphicsContext.Shading.color(CanvasPalette.ink70)

            switch kind {
            case .voice:
                context.stroke(p { path in
                    for (x, half) in [(2.5, 0.5), (5.0, 2.5), (7.0, 4.0), (9.0, 2.5), (11.5, 0.5)] {
                        path.move(to: CGPoint(x: x, y: 7 - half))
                        path.addLine(to: CGPoint(x: x, y: 7 + half))
                    }
                }, with: shading, style: stroke)
            case .capture:
                context.stroke(p { path in
                    path.move(to: CGPoint(x: 2, y: 4.5)); path.addLine(to: CGPoint(x: 2, y: 2)); path.addLine(to: CGPoint(x: 4.5, y: 2))
                    path.move(to: CGPoint(x: 9.5, y: 2)); path.addLine(to: CGPoint(x: 12, y: 2)); path.addLine(to: CGPoint(x: 12, y: 4.5))
                    path.move(to: CGPoint(x: 12, y: 9.5)); path.addLine(to: CGPoint(x: 12, y: 12)); path.addLine(to: CGPoint(x: 9.5, y: 12))
                    path.move(to: CGPoint(x: 4.5, y: 12)); path.addLine(to: CGPoint(x: 2, y: 12)); path.addLine(to: CGPoint(x: 2, y: 9.5))
                    path.addEllipse(in: CGRect(x: 5.4, y: 5.4, width: 3.2, height: 3.2))
                }, with: shading, style: stroke)
            case .text:
                context.stroke(p { path in
                    for (y, x2) in [(3.5, 11.5), (7.0, 11.5), (10.5, 8.0)] {
                        path.move(to: CGPoint(x: 2.5, y: y)); path.addLine(to: CGPoint(x: x2, y: y))
                    }
                }, with: shading, style: stroke)
            case .audio:
                context.stroke(p { path in
                    path.move(to: CGPoint(x: 2.5, y: 5.5)); path.addLine(to: CGPoint(x: 4.5, y: 5.5))
                    path.addLine(to: CGPoint(x: 7.5, y: 3)); path.addLine(to: CGPoint(x: 7.5, y: 11))
                    path.addLine(to: CGPoint(x: 4.5, y: 8.5)); path.addLine(to: CGPoint(x: 2.5, y: 8.5))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: 9.5, y: 5.2))
                    path.addQuadCurve(to: CGPoint(x: 9.5, y: 8.8), control: CGPoint(x: 11.2, y: 7))
                    path.move(to: CGPoint(x: 11.2, y: 3.5))
                    path.addQuadCurve(to: CGPoint(x: 11.2, y: 10.5), control: CGPoint(x: 14.4, y: 7))
                }, with: shading, style: stroke)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// A plate on a page, not a card.
///
/// No shadow, no fixed height, no dead space: it sizes to its content so a
/// two-line fragment is a two-line plate. Hierarchy is size and position, so
/// there is no eyebrow and no plate number. Rules appear inside it only where
/// both sides have content, which is the difference between a rule that
/// encodes structure and a rule that decorates.
private struct GridCaptureTile: View {
    /// Where the plate is standing.
    ///
    /// In the grid it is the whole record, so it carries its own annotation
    /// and a full plate edge. In panel view the left column already IS the
    /// note for the active capture — printing it again on the plate showed
    /// the same words twice — and the capture is the thing being read, so
    /// the wrapper gets out of its way.
    enum Placement { case grid, marginal }

    let step: ExplorationStep
    let selected: Bool
    var placement: Placement = .grid
    @Binding var note: String

    @FocusState private var noteFocused: Bool
    @State private var hovering = false
    @AppStorage(GroundSurface.storageKey) private var surfaceRaw = GroundSurface.paper.rawValue

    // Split into parts deliberately: as one expression the plate body blew
    // past the type-checker's budget.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            if placement == .grid { caption }
            footer
        }
        .padding(CanvasPalette.platePad)
        .frame(maxWidth: .infinity, alignment: .leading)
        // On glass a plate is a SECOND pane — more opaque than the window,
        // and a selected one lifts by getting more solid still rather than
        // by growing a shadow.
        .background(plateFill)
        .clipShape(RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous)
                .stroke(borderColor, lineWidth: selected ? 1.5 : (placement == .marginal ? 0.5 : 1))
        )
        // The glass edge: a 1px top highlight. This inset is the only shadow
        // anywhere in the app.
        .overlay(alignment: .top) {
            if glass {
                Rectangle()
                    .fill(GlassTokens.plateEdge)
                    .frame(height: 1)
                    .padding(.horizontal, 1)
            }
        }
        // Hover moves the hairline and nothing else. No lift, no scale, no
        // shadow — those are what made these read as a SaaS card kit.
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private var header: some View {
        HStack(spacing: 8) {
            FragmentGlyph(kind: glyphKind)
            Text(metaLine)
                .font(CanvasTypography.meta())
                .foregroundStyle(CanvasPalette.ink55)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
            // Images bleed to the plate's inner width, framed by the same
            // hairline as the plate and with no radius of their own.
            // Capped, so a tall screenshot cannot run a column off the
            // screen and push every other plate out of view. The user's own
            // note is never capped — only the captured material is.
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 260)
                .clipped()
                .overlay(Rectangle().stroke(CanvasPalette.ink12, lineWidth: 1))
        } else if let body = primaryText, !body.isEmpty {
            Text(body)
                .font(CanvasTypography.text())
                .lineSpacing(CanvasTypography.leading(15.5))
                .foregroundStyle(CanvasPalette.ink)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                // 62ch, whatever the plate's width. A wider plate gets air
                // beside the column rather than a longer line.
                .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Your words, marked as yours. Italic alone did not separate them from
    /// the captured material — they read as more of the same fragment. They
    /// now sit in the accent wash behind a marginal rule, which is how an
    /// annotation is set on a printed page: the reader's hand in the margin,
    /// distinct from the text it comments on.
    ///
    /// Never truncated. This is the one thing on the plate the user wrote.
    @ViewBuilder
    private var caption: some View {
        if !note.isEmpty || noteFocused {
            marginalia(bar: CanvasPalette.accent) {
                Group {
                    if noteFocused {
                        TextField("", text: $note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($noteFocused)
                            .lineLimit(1...20)
                    } else {
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { noteFocused = true }
                    }
                }
                .font(CanvasTypography.meta(14))
                .lineSpacing(CanvasTypography.leading(14))
                .foregroundStyle(CanvasPalette.ink70)
            }
        } else {
            // The empty slot still shows its rule, so you can see where the
            // annotation goes before there is one.
            marginalia(bar: CanvasPalette.ink12) {
                Text("Add a note…")
                    .font(CanvasTypography.meta(14))
                    .lineSpacing(CanvasTypography.leading(14))
                    .foregroundStyle(CanvasPalette.ink30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { noteFocused = true }
            }
        }
    }

    /// The footer rule exists only when there is a footer to separate.
    @ViewBuilder
    private var footer: some View {
        if !sourceLabel.isEmpty || urlString != nil {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(CanvasPalette.ink12).frame(height: 1)
                // Title and URL are different kinds of thing, so they get
                // different lines rather than fighting over one baseline.
                VStack(alignment: .leading, spacing: 5) {
                    Text(sourceLabel)
                        .font(CanvasTypography.meta())
                        .lineSpacing(CanvasTypography.leading(12.5))
                        .foregroundStyle(CanvasPalette.ink55)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
                    if let urlString {
                        // Mono survives here and nowhere else: a URL is
                        // literally machine data.
                        Text(urlString)
                            .font(CanvasTypography.data())
                            .foregroundStyle(CanvasPalette.ink45)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }
            .padding(.top, 4)
        }
    }

    private var glass: Bool { (GroundSurface(rawValue: surfaceRaw) ?? .paper) == .glass }

    /// Marginalia, not a box. The bar runs the height of the text and no
    /// further, there is no fill on paper, and on glass the separation comes
    /// from the accent wash — never a neutral grey, which is what made this
    /// read as a disabled input.
    @ViewBuilder
    private func marginalia<C: View>(bar: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(bar).frame(width: 1.5)
            content()
                .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glass ? CanvasPalette.accentWashGlass : Color.clear)
    }

    private var plateFill: Color {
        guard glass else {
            // Marginal plates sit back: the fill still has to carry the text,
            // but it stops competing with the capture inside it.
            return placement == .marginal
                ? CanvasPalette.paperPlate.opacity(0.62)
                : CanvasPalette.paperPlate
        }
        if selected { return GlassTokens.paperPlateSelected }
        // On glass the fill is legibility, not decoration, so it barely
        // softens — a translucent plate over a moving desktop is unreadable.
        return placement == .marginal
            ? GlassTokens.paperPlate.opacity(0.92)
            : GlassTokens.paperPlate
    }

    private var borderColor: Color {
        if selected { return CanvasPalette.accent }
        let base = glass ? GlassTokens.ink12 : CanvasPalette.ink12
        let rest = placement == .marginal ? base.opacity(0.5) : base
        return hovering ? CanvasPalette.ink30 : rest
    }

    private var primaryText: String? { step.selectedText ?? step.pageText }

    private var glyphKind: FragmentGlyph.Kind {
        if step.screenshotPath != nil { return .capture }
        if step.appName.localizedCaseInsensitiveContains("audio") { return .audio }
        if step.appName == "Notefy Voice" { return .voice }
        return .text
    }

    /// Sentence case, no middle dots, tabular time.
    private var metaLine: String {
        let kind: String
        switch glyphKind {
        case .capture: kind = "Capture"
        case .audio: kind = "Audio"
        case .voice: kind = "Voice"
        case .text: kind = "Text"
        }
        let time = step.timestamp
            .formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
            .lowercased()
        return "\(kind), \(time)"
    }

    private var urlString: String? {
        guard let url = step.url, let host = URL(string: url)?.host, !host.isEmpty else { return nil }
        return host
    }

    private var sourceLabel: String {
        if step.appName == "Audio" { return "Computer audio" }
        if ["Notefy", "Noted", "notefy-app"].contains(step.appName) { return "Screen region" }
        let title = step.windowTitle.isEmpty ? step.appName : step.windowTitle
        return title
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
                                ZStack {
                                    // Raw is ink that has just landed, edge
                                    // still wandering. Organized is that same
                                    // ink resolved into a contained pill —
                                    // fragment becoming composition, which is
                                    // the thing the two tabs actually mean.
                                    InkTabShape(dispersion: tab == .raw ? 1 : 0, seed: 2.1)
                                        .fill(CanvasPalette.inkBlue)
                                        .matchedGeometryEffect(id: "ink-tab", in: inkSelection)

                                    // Two specks thrown clear on landing. They
                                    // belong to Raw only, and they are what the
                                    // ink gives up when it resolves.
                                    if tab == .raw {
                                        Circle()
                                            .fill(CanvasPalette.inkBlue.opacity(0.55))
                                            .frame(width: 3.5, height: 3.5)
                                            .offset(x: -54, y: -15)
                                        Circle()
                                            .fill(CanvasPalette.inkBlue.opacity(0.35))
                                            .frame(width: 2.5, height: 2.5)
                                            .offset(x: 50, y: 16)
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CanvasPalette.paper.opacity(0.88), in: InkPillShape(variation: 2))
        .overlay(InkPillShape(variation: 2).stroke(CanvasPalette.inkBlue.opacity(0.13)))
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
                            .font(CanvasTypography.meta())
                            .foregroundStyle(CanvasPalette.ink55)
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
                                .font(CanvasTypography.noteBody).lineSpacing(CanvasTypography.leading(15.5)).opacity(0.58)
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
                .background(CanvasPalette.paperPlate, in: RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous).stroke(CanvasPalette.ink12))
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
            // The blob shape stays — it echoes the splatter. The label now
            // matches the Raw/Organized labels in face and case, and the
            // filled sparkle is gone: no filled icons anywhere.
            Text(appState.organizedDraft.isEmpty ? "ORGANIZE" : "REORGANIZE")
                .font(CanvasTypography.data(11))
                .tracking(1.3)
                .padding(.horizontal, 18).frame(height: 38)
                .foregroundStyle(CanvasPalette.paper)
                .background(CanvasPalette.accent, in: InkTabShape(dispersion: 1, seed: 2.1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Shape this note")
                        .font(CanvasTypography.meta())
                        .foregroundStyle(CanvasPalette.ink55)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.bottom, 6)

                ForEach(OrganizationTemplate.allCases) { template in
                    Button {
                        isOpen = false
                        appState.organizeCurrentSession(as: template)
                    } label: {
                        // No filled row and no pill: the chosen template is
                        // marked by the printer's dot, like every other
                        // active state in the app.
                        HStack(spacing: 10) {
                            Circle()
                                .fill(CanvasPalette.ink)
                                .frame(width: 6, height: 6)
                                .opacity(appState.organizedTemplate == template ? 1 : 0)
                            Image(systemName: template.icon)
                                .font(.system(size: 12, weight: .light))
                                .foregroundStyle(CanvasPalette.ink70)
                                .frame(width: 16)
                            Text(template.rawValue)
                                .font(CanvasTypography.text(14, appState.organizedTemplate == template ? 500 : 400))
                            Spacer()
                        }
                        .foregroundStyle(CanvasPalette.ink)
                        .padding(.horizontal, 11).frame(height: 36)
                        .contentShape(Rectangle())
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
                .lineSpacing(CanvasTypography.leading(15.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
        case .bullet(let text):
            // Hanging punctuation: the marker sits in the gutter and the
            // text runs flush, so a wrapped second line aligns with the
            // first rather than under the dot.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Circle()
                    .fill(CanvasPalette.ink)
                    .frame(width: 5, height: 5)
                    .frame(width: 18, alignment: .leading)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                Text(inlineMarkdown(text))
                    .font(CanvasTypography.essayBody)
                    .lineSpacing(CanvasTypography.leading(15.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: CanvasPalette.measure, alignment: .leading)
            }
        case .checklist(let text, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(CanvasPalette.inkBlue)
                Text(inlineMarkdown(text))
                    .font(CanvasTypography.essayBody).lineSpacing(CanvasTypography.leading(15.5))
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
                Text(status)
                    .font(CanvasTypography.meta())
                    .foregroundStyle(CanvasPalette.ink55)
            }
        }
    }
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
                    Text("Folders")
                        .font(CanvasTypography.meta())
                        .foregroundStyle(CanvasPalette.ink55)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { creatingFolder = true }
                        DispatchQueue.main.async { nameFocused = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(CanvasPalette.ink70)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
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
                            .font(CanvasTypography.text(14))
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
                    .background(CanvasPalette.inkBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous))
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
            .background(CanvasPalette.paperPlate, in: RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CanvasPalette.plateRadius, style: .continuous).stroke(CanvasPalette.ink12))
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
                        .font(.system(size: 8, weight: .light))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(CanvasPalette.ink45)
                    // Section headers are italic meta, not bold sans.
                    Text(title)
                        .font(CanvasTypography.meta())
                        .foregroundStyle(CanvasPalette.ink55)
                        .lineLimit(1)
                    Spacer()
                    Text("\(folderNotes.count)")
                        .font(CanvasTypography.meta(11))
                        .foregroundStyle(CanvasPalette.ink45)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12).frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(folderNotes) { note in
                        let isCurrent = note.url == activeURL
                        Button {
                            withAnimation { isOpen = false }
                            guard !isCurrent else { return }
                            openNote(note.url)
                        } label: {
                            HStack(spacing: 10) {
                                // The open note is marked by a printer's dot
                                // in the left gutter and a heavier weight —
                                // never by a filled row.
                                Circle()
                                    .fill(CanvasPalette.ink)
                                    .frame(width: 6, height: 6)
                                    .opacity(isCurrent ? 1 : 0)
                                Text(note.title)
                                    .font(CanvasTypography.text(14, isCurrent ? 500 : 400))
                                    .foregroundStyle(CanvasPalette.ink)
                                    .lineLimit(1)
                                Spacer()
                                if note.captureCount > 0 {
                                    Text("\(note.captureCount)")
                                        .font(CanvasTypography.meta(11))
                                        .foregroundStyle(CanvasPalette.ink45)
                                        .monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 12).frame(height: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Scoped to the folder it sits under, so there is never a
                    // question of where the new note lands.
                    Button {
                        withAnimation { isOpen = false }
                        if case .folder(let id) = value { createNote(id) } else { createNote(nil) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .light))
                                .frame(width: 6)
                            Text("New note").font(CanvasTypography.text(14))
                            Spacer()
                        }
                        .foregroundStyle(CanvasPalette.ink55)
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
    /// Supplied by the caller: a short wipe and a long one step through
    /// different numbers of frames, and progress is a fraction of whichever
    /// is running.
    var coverFrames: Int = 16
    var revealFrames: Int = 20

    private var coverFrameCount: Int { coverFrames }
    private var revealFrameCount: Int { revealFrames }

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

/// Editorial ink tokens, taken from tokens.css. These are the only colours
/// in the app — no invented hexes, no tints, no gradients, no washes beyond
/// the one accent wash.
private enum CanvasPalette {
    static let paper = Color(hex: 0xF1EDE4)
    /// A 2% lift for plates. Never white — white would make them dialogs.
    static let paperPlate = Color(hex: 0xF4F0E8)

    /// Warm print black, never #000 and never #111.
    static let ink = Color(hex: 0x1C1B19)
    static let ink70 = Color(hex: 0x1C1B19, opacity: 0.70)
    static let ink55 = Color(hex: 0x1C1B19, opacity: 0.55)
    static let ink45 = Color(hex: 0x1C1B19, opacity: 0.45)
    static let ink30 = Color(hex: 0x1C1B19, opacity: 0.30)
    /// Hairlines. Structure is carried by these, not by shadow.
    static let ink12 = Color(hex: 0x1C1B19, opacity: 0.12)

    /// The one accent. It appears in the ink blob, the active plate's
    /// hairline, and links — nowhere else, and never above ~10% of the
    /// visual weight of a screen.
    static let accent = Color(hex: 0x2B2A63)
    static let accentWash = Color(hex: 0x2B2A63, opacity: 0.08)
    /// On glass the marginalia needs a whisper of separation; on paper the
    /// bar alone carries it.
    static let accentWashGlass = Color(hex: 0x2B2A63, opacity: 0.06)

    // Names the rest of the file still reaches for, mapped onto the tokens
    // rather than left as a second, competing palette.
    static let clay = paper
    static let clayLight = paper
    static let clayMid = paper
    static let clayLow = paperPlate
    static let paperDim = paperPlate
    static let paperEdge = ink12
    static let slip = paperPlate
    static let tape = ink12
    static let inkBlue = accent
    static let inkBlueDeep = accent
    static let inkBlueLight = ink55
    static let warmShadow = ink30

    // Layout
    static let pageMargin: CGFloat = 40
    static let gutter: CGFloat = 24
    static let platePad: CGFloat = 24
    static let plateRadius: CGFloat = 6
    /// 62ch at the body size — the measure a typeset column holds.
    static let measure: CGFloat = 560
}

/// Four roles, four settings — and the discipline is in what each one is NOT
/// allowed to do.
///
/// Display is Fraunces at LIGHT weight and a display optical size, which is
/// the correction that matters most here: a Black Didone at 120px was the
/// loudest thing on the page and competed with the ink blob. Premium
/// editorial display is high-contrast but light, set smaller, tracked tight.
///
/// Text is Newsreader for everything a person reads. Meta is that same face
/// in ITALIC — not mono, not caps — because tracked-out mono eyebrows on
/// every card are the single clearest tell of generated UI.
///
/// Data is mono, and mono appears nowhere except literal machine strings:
/// URLs, file paths, region names.
///
/// All faces are the free fallbacks named in the brief, and all four were
/// already bundled — nothing here needs a licence.
private enum CanvasTypography {
    private static let wght: UInt32 = 0x77676874
    private static let opsz: UInt32 = 0x6F70737A
    private static let soft: UInt32 = 0x534F4654
    private static let wonk: UInt32 = 0x574F4E4B

    private static func varied(_ name: String, _ size: CGFloat, _ axes: [UInt32: CGFloat]) -> Font {
        var variations: [CFNumber: CFNumber] = [:]
        for (tag, value) in axes { variations[tag as CFNumber] = value as CFNumber }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name,
            kCTFontVariationAttribute: variations
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// Fraunces, display optical size, softness off, wonk off. Never Black,
    /// never Bold.
    /// Display weight goes 300 -> 600. The brief said never bold and that
    /// was right for a Didone; Fraunces at 300 just reads thin, and at 600
    /// with the display optical size the contrast between stem and hairline
    /// is what carries it rather than sheer mass.
    static func display(_ size: CGFloat, _ weight: CGFloat = 600) -> Font {
        varied("Fraunces-9ptBlack", size, [wght: weight, opsz: 144, soft: 0, wonk: 0])
    }
    static func text(_ size: CGFloat = 15.5, _ weight: CGFloat = 400) -> Font {
        varied("NewsreaderRoman-Regular", size, [wght: weight, opsz: 16])
    }
    /// Meta is the text face in italic. Sentence case, always.
    static func meta(_ size: CGFloat = 12.5) -> Font {
        .custom("NewsreaderItalic-Italic", size: size)
    }
    /// Machine strings only.
    static func data(_ size: CGFloat = 11) -> Font {
        .custom("GeistMono-Regular", size: size)
    }

    // Roles the rest of the file names.
    static let wordmark = display(28, 600)
    static let loaderWordmark = display(44, 600)
    static let noteTitleReader = display(56, 600)
    static let noteTitleGrid = display(44, 600)
    static let noteTitle = display(44, 600)
    static let essayTitle = display(56, 600)
    static let essayHeading = display(28, 400)
    static let emptyTitle = display(26, 600)
    static let cardTitle = text(15.5, 500)

    static let noteBody = text(15.5)
    static let essayBody = text(15.5)
    static let cardBody = text(15.5)
    static let control = text(15)

    /// −0.02em at the sizes above, and leading pulled to 1.0.
    static let titleTracking: CGFloat = -0.02 * 44
    static let titleLineSpacing: CGFloat = -10
    /// line-height 1.55 expressed as SwiftUI's extra leading. Every text
    /// element inside a plate uses this; display titles are the only
    /// exception, and they set their own negative leading.
    static func leading(_ size: CGFloat) -> CGFloat { size * 0.55 }
    static let bodyLineSpacing: CGFloat = leading(15.5)

    // Kept so existing metadata call sites compile while they are converted
    // to `meta`; both now resolve to the text face in italic rather than to
    // tracked-out mono.
    static func mark(_ size: CGFloat = 12.5) -> Font { meta(size) }
    static func markRegular(_ size: CGFloat = 12.5) -> Font { meta(size) }
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
            .tracking(-1.0)
            .foregroundStyle(CanvasPalette.ink)
            .frame(width: 112, height: 42)
            .accessibilityLabel("Noted")
    }
}

/// The Noted mark, drawn at whatever size it is asked for.
///
/// It was reading as a toolbar icon because it was only ever used AS one —
/// 22pt, boxed in beside a label. It is a template image, so weight here is
/// just how much of the ink is let through: light for the masthead, full for
/// the small placements where a thin nib would disappear.
struct NotedCanvasMark: View {
    enum Weight { case light, full }
    var size: CGFloat = 22
    var weight: Weight = .full
    var tint: Color = CanvasPalette.ink

    var body: some View {
        Group {
            if let mark = NotedInkAssets.nib ?? NotedInkAssets.splat ?? NotedInkAssets.mark {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint.opacity(weight == .light ? 0.82 : 1))
            } else {
                Image(systemName: "pencil.tip")
                    .font(.system(size: size * 0.8, weight: .light))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct CanvasBrandIcon: View {
    var body: some View { NotedCanvasMark(size: 20) }
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
/// The Raw / Organized pill, with irregularity as an animatable property.
///
/// `dispersion` 1 is ink that has just landed — the outline wanders off the
/// capsule. `dispersion` 0 is that same ink resolved into a contained,
/// intentional form. Because it is `animatableData`, moving between the two
/// tabs interpolates the SHAPE rather than cross-fading two of them, so the
/// control performs the thing the two tabs mean: messy thought settling into
/// structured thought. The interaction is untouched — this is the same pill
/// in the same place doing the same job.
/// One quiet bloom when a capture lands — the app saying "that is on the
/// page now" in its own material rather than with a toast. Fires once per
/// capture, is over in well under a second, and does not run at all under
/// reduced motion.
private struct InkCaptureBloom: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var grow: CGFloat = 0.35

    var body: some View {
        CanvasInkBlob()
            .fill(CanvasPalette.inkBlue.opacity(0.14))
            .frame(width: 104, height: 88)
            .scaleEffect(grow)
            .opacity(visible ? 1 : 0)
            .blur(radius: 1.5)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        guard !reduceMotion, trigger > 0 else { return }
        grow = 0.35
        visible = true
        // Spreads, then soaks in. Two curves rather than one, because ink
        // does not fade at the rate it spreads.
        withAnimation(.easeOut(duration: 0.44)) { grow = 1.2 }
        withAnimation(.easeIn(duration: 0.34).delay(0.30)) { visible = false }
    }
}

/// The stroke under whatever is being written in. It is drawn with the same
/// wander as the selected card's edge, so an active field reads as underlined
/// by hand rather than outlined by the toolkit.
private struct InkUnderline: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3))
                let steps = 40
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let y = 3 + sin(t * .pi * 3.1) * 0.9 + sin(t * .pi * 7.3) * 0.4
                    path.addLine(to: CGPoint(x: w * t, y: y))
                }
            }
            .trim(from: 0, to: active ? 1 : 0)
            .stroke(CanvasPalette.inkBlue.opacity(0.42),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.30), value: active)
        }
        .frame(height: 7)
        .allowsHitTesting(false)
    }
}

private struct InkTabShape: Shape {
    var dispersion: CGFloat
    var seed: CGFloat = 0

    var animatableData: CGFloat {
        get { dispersion }
        set { dispersion = newValue }
    }

    /// Walks the perimeter of a capsule by arc length, so displacing a point
    /// along its outward normal thickens the outline evenly instead of
    /// bunching up at the caps.
    private func capsulePoint(_ t: CGFloat, _ rect: CGRect) -> CGPoint {
        let r = rect.height / 2
        let straight = max(0, rect.width - 2 * r)
        let arc = CGFloat.pi * r
        let total = 2 * straight + 2 * arc
        var d = t * total
        if d < straight { return CGPoint(x: rect.minX + r + d, y: rect.minY) }
        d -= straight
        if d < arc {
            let a = -CGFloat.pi / 2 + (d / arc) * .pi
            return CGPoint(x: rect.maxX - r + cos(a) * r, y: rect.midY + sin(a) * r)
        }
        d -= arc
        if d < straight { return CGPoint(x: rect.maxX - r - d, y: rect.maxY) }
        d -= straight
        let a = CGFloat.pi / 2 + (d / arc) * .pi
        return CGPoint(x: rect.minX + r + cos(a) * r, y: rect.midY + sin(a) * r)
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 1, rect.height > 1 else { return Path() }
        let samples = 96
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        for i in 0..<samples {
            let t = CGFloat(i) / CGFloat(samples)
            let p = capsulePoint(t, rect)
            var nx = p.x - rect.midX, ny = p.y - rect.midY
            let len = max(0.0001, sqrt(nx * nx + ny * ny))
            nx /= len; ny /= len
            // Three octaves: a slow wander, a wobble, and a fine tooth. Fixed
            // frequencies so every pill reads as the same ink.
            let a = t * 2 * .pi
            let wob = sin(a * 3 + seed) * 0.60
                + sin(a * 7 - seed * 1.7) * 0.28
                + sin(a * 13 + seed * 0.6) * 0.14
            let amp = dispersion * rect.height * 0.09 * wob
            points.append(CGPoint(x: p.x + nx * amp, y: p.y + ny * amp))
        }
        var path = Path()
        let first = points[0], last = points[samples - 1]
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in points.indices {
            let c = points[i]
            let n = points[(i + 1) % samples]
            path.addQuadCurve(to: CGPoint(x: (c.x + n.x) / 2, y: (c.y + n.y) / 2), control: c)
        }
        path.closeSubpath()
        return path
    }
}

/// A rounded rectangle whose edge wanders very slightly — the selected
/// capture's outline. Uniform strokes read as UI chrome; this reads as a
/// line someone drew round the thing they were looking at.
private struct InkEdgeRect: Shape {
    var corner: CGFloat = 12
    var amplitude: CGFloat = 0.9
    var seed: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let base = Path(roundedRect: rect, cornerRadius: corner)
        let samples = 160
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        for i in 0..<samples {
            let t = CGFloat(i) / CGFloat(samples)
            guard let p = base.trimmedPath(from: t, to: min(1, t + 0.0001)).currentPoint else { continue }
            var nx = p.x - rect.midX, ny = p.y - rect.midY
            let len = max(0.0001, sqrt(nx * nx + ny * ny))
            nx /= len; ny /= len
            let a = t * 2 * .pi
            let wob = sin(a * 5 + seed) * 0.6 + sin(a * 11 - seed) * 0.4
            let amp = amplitude * wob
            points.append(CGPoint(x: p.x + nx * amp, y: p.y + ny * amp))
        }
        guard points.count > 3 else { return base }
        var path = Path()
        let first = points[0], last = points[points.count - 1]
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in points.indices {
            let c = points[i]
            let n = points[(i + 1) % points.count]
            path.addQuadCurve(to: CGPoint(x: (c.x + n.x) / 2, y: (c.y + n.y) / 2), control: c)
        }
        path.closeSubpath()
        return path
    }
}

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
/// Flat paper and one texture. The gradient lift and the vignette are gone:
/// a printed page is evenly lit, and the tonal shading was doing the job a
/// hairline should do.
private struct CanvasClayBackground: View {
    let focused: Bool
    let zoom: CGFloat
    @AppStorage(GroundSurface.storageKey) private var surfaceRaw = GroundSurface.paper.rawValue

    private var surface: GroundSurface { GroundSurface(rawValue: surfaceRaw) ?? .paper }

    var body: some View {
        ZStack {
            GroundSurfaceView(surface: surface, paper: CanvasPalette.paper)
            // Grain is a paper property. A frosted pane has no tooth, so on
            // glass it is removed entirely rather than merely faded — the
            // sheen is the only surface cue there.
            if surface == .paper { PaperGrain() }
        }
        .ignoresSafeArea()
    }
}

/// assets/paper-grain.svg, as a multiply overlay at 3%. It is the one
/// texture in the app; nothing else gets one.
private struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 23)
            let count = Int(size.width * size.height / 8)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                             with: .color(CanvasPalette.ink))
            }
        }
        .blendMode(.multiply)
        .opacity(0.03)
        .allowsHitTesting(false)
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

