import SwiftUI
import AppKit
import NotefyCore

private enum CanvasRoute: Equatable {
    case canvas
    case reading(URL)
}

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

struct CanvasWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var route: CanvasRoute = .canvas
    @State private var folderFilter: CanvasFolderFilter = .all
    @State private var foldersOpen = false
    @State private var settingsOpen = false
    @State private var zoom: CGFloat = 0.84
    @State private var selectedIndex = 0
    @State private var inkTransitionFrame: Int?
    @State private var inkTransitionOrigin: CGPoint?
    @FocusState private var keyboardFocused: Bool

    private var notes: [CanvasNoteSnapshot] {
        switch folderFilter {
        case .all: return appState.canvasNoteSnapshots
        case .unfiled: return appState.canvasNoteSnapshots.filter { $0.folderID == nil }
        case .folder(let id): return appState.canvasNoteSnapshots.filter { $0.folderID == id }
        }
    }

    private var folderTitle: String {
        switch folderFilter {
        case .all: return "All notes"
        case .unfiled: return "Unfiled"
        case .folder(let id): return appState.folderPath(for: id)
        }
    }

    var body: some View {
        ZStack {
            CanvasClayBackground(focused: route != .canvas, zoom: zoom)

            Group {
                switch route {
                case .canvas:
                    ChronologicalCanvas(
                        notes: notes,
                        zoom: $zoom,
                        selectedIndex: $selectedIndex,
                        moveNote: appState.moveCanvasNote,
                        openNote: openNote
                    )
                case .reading:
                    CaptureReadingView()
                        .environmentObject(appState)
                        .transition(.opacity)
                }
            }

            VStack(spacing: 0) {
                CanvasToolbar(
                    route: route,
                    folderTitle: folderTitle,
                    foldersOpen: $foldersOpen,
                    settingsOpen: $settingsOpen,
                    zoom: $zoom,
                    createNote: createNote,
                    back: { withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { route = .canvas } }
                )
                Spacer()
            }
            .zIndex(3)

            if foldersOpen {
                CanvasFolderOverlay(
                    filter: $folderFilter,
                    isOpen: $foldersOpen,
                    notes: appState.canvasNoteSnapshots
                )
                .environmentObject(appState)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
                .zIndex(5)
            }

            if let inkTransitionFrame {
                InkOpenTransition(frame: inkTransitionFrame, origin: inkTransitionOrigin)
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
        .onKeyPress(.leftArrow) { guard route == .canvas else { return .ignored }; moveSelection(-1); return .handled }
        .onKeyPress(.rightArrow) { guard route == .canvas else { return .ignored }; moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { guard route == .canvas else { return .ignored }; moveSelection(-canvasColumnCount); return .handled }
        .onKeyPress(.downArrow) { guard route == .canvas else { return .ignored }; moveSelection(canvasColumnCount); return .handled }
        .onKeyPress(.escape) {
            if route != .canvas { withAnimation { route = .canvas } }
            return .handled
        }
        .sheet(isPresented: $settingsOpen) {
            SettingsView()
                .environmentObject(appState)
                .environment(\.ground, GroundPalette.clay)
                .frame(width: 880, height: 680)
                .background(Stoneink.surfaceBed)
        }
    }

    private var canvasColumnCount: Int { 3 }

    private func moveSelection(_ delta: Int) {
        guard route == .canvas, !notes.isEmpty else { return }
        let targetIndex = min(max(selectedIndex + delta, 0), notes.count - 1)
        guard targetIndex != selectedIndex else { return }
        let selectedURL = notes[selectedIndex].url
        let targetURL = notes[targetIndex].url
        withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
            appState.swapCanvasNotes(selectedURL, targetURL)
            selectedIndex = targetIndex
        }
    }

    private func openNote(_ snapshot: CanvasNoteSnapshot, from origin: CGPoint) {
        transitionToReading(snapshot.url, from: origin)
    }

    private func createNote() {
        let folderID: UUID?
        if case .folder(let id) = folderFilter { folderID = id } else { folderID = nil }
        let destination = appState.createNewNote(inFolder: folderID)
        transitionToReading(destination.url, from: nil)
    }

    private func transitionToReading(_ url: URL, from origin: CGPoint?) {
        guard inkTransitionFrame == nil else { return }
        inkTransitionOrigin = origin

        guard !reduceMotion else {
            appState.openNote(url)
            withAnimation(.easeInOut(duration: 0.16)) { route = .reading(url) }
            return
        }

        Task { @MainActor in
            let coverFrames = 16
            let revealFrames = 20

            for frame in 0..<coverFrames {
                inkTransitionFrame = frame
                try? await Task.sleep(for: .milliseconds(28))
            }

            appState.openNote(url)
            route = .reading(url)

            for frame in coverFrames..<(coverFrames + revealFrames) {
                inkTransitionFrame = frame
                try? await Task.sleep(for: .milliseconds(28))
            }

            inkTransitionFrame = nil
            inkTransitionOrigin = nil
            keyboardFocused = true
        }
    }
}

private struct CanvasToolbar: View {
    let route: CanvasRoute
    let folderTitle: String
    @Binding var foldersOpen: Bool
    @Binding var settingsOpen: Bool
    @Binding var zoom: CGFloat
    let createNote: () -> Void
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if route == .canvas { withAnimation { foldersOpen.toggle() } } else { back() }
            } label: {
                HStack(spacing: 9) {
                    if route == .canvas {
                        CanvasBrandIcon()
                    } else {
                        Image(systemName: "arrow.left")
                    }
                    Text(route == .canvas ? folderTitle : "Canvas")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if route == .canvas { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
                }
                .padding(.horizontal, 15).frame(height: 42)
                .background(CanvasPalette.paper.opacity(0.72), in: Capsule())
                .overlay(Capsule().stroke(CanvasPalette.ink.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Spacer()
            CanvasBrandMark()
            Spacer()

            if route == .canvas {
                Button(action: createNote) {
                    Label("New note", systemImage: "square.and.pencil")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 15).frame(height: 42)
                        .foregroundStyle(CanvasPalette.paper)
                        .background(CanvasPalette.inkBlue, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
            }

            HStack(spacing: 8) {
                if route == .canvas {
                    Button { zoom = max(0.50, zoom - 0.10) } label: { Image(systemName: "minus") }
                    Text("\(Int(zoom * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).frame(width: 38)
                    Button { zoom = min(1.30, zoom + 0.10) } label: { Image(systemName: "plus") }
                    Divider().frame(height: 18).opacity(0.25)
                }
                Button { settingsOpen = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 13).frame(height: 42)
            .background(CanvasPalette.paper.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(CanvasPalette.ink.opacity(0.10)))
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }
}

private struct ChronologicalCanvas: View {
    let notes: [CanvasNoteSnapshot]
    @Binding var zoom: CGFloat
    @Binding var selectedIndex: Int
    let moveNote: (URL, URL) -> Void
    let openNote: (CanvasNoteSnapshot, CGPoint) -> Void

    private let columns = Array(repeating: GridItem(.fixed(300), spacing: 30), count: 3)

    var body: some View {
        ScrollViewReader { reader in
            ScrollView([.horizontal, .vertical]) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        CanvasNoteCard(note: note, selected: index == selectedIndex)
                            .id(note.id)
                            .onTapGesture(count: 2, coordinateSpace: .global) { location in
                                selectedIndex = index
                                openNote(note, location)
                            }
                            .onTapGesture(count: 1) {
                                withAnimation(.easeOut(duration: 0.16)) { selectedIndex = index }
                            }
                            .draggable(note.url.absoluteString) {
                                CanvasNoteCard(note: note, selected: true)
                                    .opacity(0.88)
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let value = items.first,
                                      let sourceURL = URL(string: value),
                                      sourceURL != note.url else { return false }
                                withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
                                    moveNote(sourceURL, note.url)
                                }
                                selectedIndex = index
                                return true
                            } isTargeted: { targeted in
                                if targeted { selectedIndex = index }
                            }
                    }
                }
                .padding(.horizontal, 100).padding(.vertical, 126)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(minWidth: 1120, minHeight: 780, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) {
                guard notes.indices.contains(selectedIndex) else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    reader.scrollTo(notes[selectedIndex].id, anchor: .center)
                }
            }
            .gesture(
                MagnifyGesture().onChanged { value in
                    zoom = min(max(zoom * value.magnification, 0.50), 1.30)
                }
            )
        }
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No notes here yet",
                    systemImage: "note.text",
                    description: Text("Create a note or choose another folder.")
                )
                .foregroundStyle(CanvasPalette.ink)
            }
        }
    }
}

private struct CanvasNoteCard: View {
    let note: CanvasNoteSnapshot
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(note.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()).uppercased())
                Spacer()
            }
            .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.7).opacity(0.52)
            Spacer(minLength: 18)
            Text(note.title)
                .font(.custom("NewsreaderRoman-72pt", size: 29, relativeTo: .title))
                .lineLimit(2)
            Text(note.excerpt)
                .font(.custom("NewsreaderRoman-Regular", size: 15, relativeTo: .body))
                .lineSpacing(4).opacity(0.67).lineLimit(3).padding(.top, 10)
            Spacer(minLength: 16)
            HStack {
                Text(note.folderName.isEmpty ? "UNFILED" : note.folderName.uppercased())
                    .lineLimit(1)
                Spacer()
                Label("\(note.captureCount)", systemImage: note.hasOrganizedNote ? "sparkles" : "paperclip")
            }
            .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.8).opacity(0.46)
        }
        .padding(24).frame(width: 300, height: 236)
        .background(CanvasPalette.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? CanvasPalette.inkBlue : CanvasPalette.paperEdge, lineWidth: selected ? 2 : 1))
        .rotationEffect(.degrees(Double(abs(note.url.lastPathComponent.hashValue) % 3) - 1))
        .shadow(color: CanvasPalette.warmShadow.opacity(selected ? 0.18 : 0.11), radius: selected ? 22 : 14, y: selected ? 12 : 8)
        .contentShape(Rectangle())
    }

}

private struct CaptureReadingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeCaptureID: UUID?
    @State private var tab: ReaderTab = .raw

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
                case .organized:
                    OrganizedEssayView()
                        .environmentObject(appState)
                        .padding(.top, 146)
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.28), value: tab)

            ReaderTabBar(selection: $tab)
                .padding(.top, 78)
                .zIndex(2)
        }
    }

    private var rawNoteColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.activeNoteURL.map { appState.folderPath(for: appState.folderID(for: $0)) }.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "NOTE")
                .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5).opacity(0.48)
            TextField("Untitled note", text: $appState.noteTitle)
                .textFieldStyle(.plain)
                .font(.custom("NewsreaderRoman-72pt", size: 40, relativeTo: .largeTitle))
                .onChange(of: appState.noteTitle) { appState.scheduleActiveNoteAutosave() }

            ZStack(alignment: .topLeading) {
                if activeNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write the note you want to keep beside these captures…")
                        .font(.custom("NewsreaderRoman-Regular", size: 16)).italic().opacity(0.42)
                        .padding(.top, 7).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: activeNoteBinding)
                    .id(activeCaptureID)
                    .font(.custom("NewsreaderRoman-Regular", size: 17, relativeTo: .body))
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
                        .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(selection == tab ? CanvasPalette.paper : CanvasPalette.ink.opacity(0.54))
                        .padding(.horizontal, 19).frame(height: 34)
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
                        .font(.custom("NewsreaderRoman-72pt", size: 46, relativeTo: .largeTitle))

                    if appState.isOrganizing {
                        InkWritingLoader(status: appState.recordingStatus ?? "Organizing your captures…")
                            .frame(maxWidth: .infinity).padding(.vertical, 70)
                    } else if appState.organizedDraft.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("This note has not been organized yet.")
                                .font(.custom("NewsreaderRoman-Regular", size: 22))
                            Text("Choose a structure and Noted will turn the raw note and captures into one readable page using your configured model.")
                                .font(.custom("NewsreaderRoman-Regular", size: 17)).lineSpacing(7).opacity(0.58)
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
                .font(.custom("NewsreaderRoman-72pt", size: 28, relativeTo: .title2))
                .padding(.top, 14)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.custom("NewsreaderRoman-Regular", size: 18, relativeTo: .body))
                .lineSpacing(9)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(CanvasPalette.inkBlue).frame(width: 6, height: 6)
                Text(inlineMarkdown(text))
                    .font(.custom("NewsreaderRoman-Regular", size: 18, relativeTo: .body)).lineSpacing(8)
            }
        case .checklist(let text, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(CanvasPalette.inkBlue)
                Text(inlineMarkdown(text))
                    .font(.custom("NewsreaderRoman-Regular", size: 18, relativeTo: .body)).lineSpacing(8)
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
                        .font(.custom("Instrument Serif", size: 42, relativeTo: .largeTitle))
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
                        .font(.custom("NewsreaderRoman-Regular", size: 16, relativeTo: .body))
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
                        .font(.custom("GeistMono-Regular", size: 10)).tracking(0.9)
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

private struct CanvasFolderOverlay: View {
    @EnvironmentObject private var appState: AppState
    @Binding var filter: CanvasFolderFilter
    @Binding var isOpen: Bool
    let notes: [CanvasNoteSnapshot]
    @State private var creatingFolder = false
    @State private var newFolderName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.06).ignoresSafeArea().onTapGesture { withAnimation { isOpen = false } }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("FOLDERS")
                        .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5).opacity(0.48)
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
                    .accessibilityLabel("Create folder")
                }
                .padding(.bottom, 8)

                if creatingFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(CanvasPalette.inkBlue)
                        TextField("Folder name", text: $newFolderName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .focused($nameFocused)
                            .onSubmit(createFolder)
                            .onExitCommand(perform: cancelFolder)
                        Button(action: createFolder) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(CanvasPalette.inkBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                folderButton("All notes", count: notes.count, value: .all)
                folderButton("Unfiled", count: notes.filter { $0.folderID == nil }.count, value: .unfiled)
                if !appState.workspace.folders.isEmpty { Divider().opacity(0.18).padding(.vertical, 5) }
                ForEach(appState.workspace.folders) { folder in
                    folderButton(appState.folderPath(for: folder.id), count: notes.filter { $0.folderID == folder.id }.count, value: .folder(folder.id))
                }
            }
            .padding(16).frame(width: 270)
            .background(CanvasPalette.paper.opacity(0.98), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(CanvasPalette.ink.opacity(0.10)))
            .shadow(color: CanvasPalette.ink.opacity(0.18), radius: 26, y: 13)
            .padding(.leading, 24).padding(.top, 70)
        }
    }

    private func folderButton(_ title: String, count: Int, value: CanvasFolderFilter) -> some View {
        Button {
            filter = value
            withAnimation { isOpen = false }
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text("\(count)").opacity(0.46)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12).frame(height: 40)
        }
        .buttonStyle(.plain)
        .background(filter == value ? CanvasPalette.inkBlue.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 11))
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = appState.createFolder(name: name)
        filter = .folder(id)
        newFolderName = ""
        creatingFolder = false
        withAnimation { isOpen = false }
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
        Canvas(rendersAsynchronously: true) { context, size in
            if frame < coverFrameCount {
                drawLandingSplashes(in: &context, size: size)
            } else {
                drawDissolvingInk(in: &context, size: size)
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

    private func drawDissolvingInk(in context: inout GraphicsContext, size: CGSize) {
        let revealIndex = frame - coverFrameCount + 1
        let progress = min(1, CGFloat(revealIndex) / CGFloat(revealFrameCount))

        context.drawLayer { layer in
            layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CanvasPalette.inkBlue))
            layer.blendMode = .destinationOut

            let columns = 6
            let rows = 5
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)
            let maximumRadius = hypot(cellWidth, cellHeight) * 1.48

            for row in 0..<rows {
                for column in 0..<columns {
                    let ordinal = row * columns + column
                    let stagger = CGFloat((ordinal * 7 + row * 3) % 13) / 90
                    let localProgress = max(0, min(1, (progress - stagger) / (1 - stagger)))
                    let bloom = 1 - pow(1 - localProgress, 2.4)
                    guard bloom > 0 else { continue }

                    let jitterX = CGFloat((ordinal * 37) % 31 - 15)
                    let jitterY = CGFloat((ordinal * 19) % 27 - 13)
                    let center = CGPoint(
                        x: (CGFloat(column) + 0.5) * cellWidth + jitterX,
                        y: (CGFloat(row) + 0.5) * cellHeight + jitterY
                    )
                    let radius = maximumRadius * bloom
                    layer.fill(
                        organicSplat(center: center, radius: radius, seed: ordinal + 31),
                        with: .color(.white)
                    )

                    // Offset blooms roughen each opening like pigment feathering in water.
                    let fringeRadius = radius * 0.36
                    let fringe = CGRect(
                        x: center.x + radius * 0.62 - fringeRadius,
                        y: center.y - radius * 0.48 - fringeRadius,
                        width: fringeRadius * 2,
                        height: fringeRadius * 1.4
                    )
                    layer.fill(Path(ellipseIn: fringe), with: .color(.white.opacity(0.92)))
                }
            }
        }
    }
}

private enum CanvasPalette {
    static let clay = Color(hex: 0xFBE4D6)
    static let clayLight = Color(hex: 0xFDF2EA)
    static let clayMid = Color(hex: 0xF7D4C1)
    static let clayLow = Color(hex: 0xF1C3AB)
    static let paper = Color(hex: 0xFFFBF7)
    static let paperDim = Color(hex: 0xFCF2EA)
    static let paperEdge = Color(hex: 0xF3DFD1)
    static let ink = Color(hex: 0x17142B)
    static let inkBlue = Color(hex: 0x2A2456)
    static let inkBlueDeep = Color(hex: 0x1F1A42)
    static let inkBlueLight = Color(hex: 0x5A5568)
    static let warmShadow = Color(hex: 0x7A4A2E)
}

private enum NotedInkAssets {
    static let mark = load("noted-mark")

    private static func load(_ name: String) -> NSImage? {
        let moduleURL = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "NotedInk")
            ?? Bundle.module.url(forResource: name, withExtension: "svg")
        guard let moduleURL else { return nil }
        return NSImage(contentsOf: moduleURL)
    }
}

private struct CanvasBrandMark: View {
    var body: some View {
        Text("noted")
            .font(.custom("Syne", size: 29, relativeTo: .title).weight(.semibold))
            .tracking(-1.4)
            .foregroundStyle(CanvasPalette.ink)
        .frame(width: 112, height: 42)
        .accessibilityLabel("Noted")
    }
}

private struct CanvasBrandIcon: View {
    var body: some View {
        Group {
            if let mark = NotedInkAssets.mark {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(CanvasPalette.ink)
            } else {
                Image(systemName: "folder.fill")
            }
        }
        .frame(width: 18, height: 18)
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

private struct CanvasClayBackground: View {
    let focused: Bool
    let zoom: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [CanvasPalette.clayLight, CanvasPalette.clay], startPoint: .topLeading, endPoint: .bottomTrailing)

                WavyInkField(size: proxy.size, zoom: zoom)
                    .opacity(focused ? 0.35 : 1)
                    .animation(.easeOut(duration: 0.44), value: focused)
            }
        }
        .ignoresSafeArea()
    }
}

private struct WavyInkField: View {
    let size: CGSize
    let zoom: CGFloat

    private let placements: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double, rotation: Double)] = [
        (-0.05, 0.02, 0.48, 0.10, -18),
        (0.92, 0.08, 0.38, 0.08, 22),
        (0.22, 0.78, 0.56, 0.075, -28),
        (0.98, 0.66, 0.34, 0.065, 14),
        (0.02, 1.04, 0.40, 0.06, 42),
        (0.76, 1.08, 0.50, 0.055, 128),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(placements.enumerated()), id: \.offset) { index, placement in
                CanvasInkBlob()
                    .fill(CanvasPalette.ink.opacity(placement.opacity))
                    .frame(
                        width: max(size.width, size.height) * placement.size,
                        height: max(size.width, size.height) * placement.size * (0.78 + CGFloat(index % 3) * 0.08)
                    )
                    .rotationEffect(.degrees(placement.rotation))
                    .scaleEffect(0.96 + zoom * 0.05)
                    .position(x: size.width * placement.x, y: size.height * placement.y)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }
}
