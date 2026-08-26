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
    @State private var route: CanvasRoute = .canvas
    @State private var folderFilter: CanvasFolderFilter = .all
    @State private var foldersOpen = false
    @State private var settingsOpen = false
    @State private var zoom: CGFloat = 0.84
    @State private var selectedIndex = 0
    @State private var inkRipple = false
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
            CanvasClayBackground()

            Group {
                switch route {
                case .canvas:
                    ChronologicalCanvas(
                        notes: notes,
                        zoom: $zoom,
                        selectedIndex: $selectedIndex,
                        openNote: openNote
                    )
                case .reading:
                    CaptureReadingView()
                        .environmentObject(appState)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
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

            InkRippleTransition(active: inkRipple)
                .allowsHitTesting(false)
                .zIndex(8)
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
                .frame(minWidth: 760, minHeight: 620)
                .background(Stoneink.surfaceBed)
        }
    }

    private var canvasColumnCount: Int { 3 }

    private func moveSelection(_ delta: Int) {
        guard route == .canvas, !notes.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), notes.count - 1)
    }

    private func openNote(_ snapshot: CanvasNoteSnapshot) {
        appState.openNote(snapshot.url)
        playInkRipple()
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            route = .reading(snapshot.url)
        }
    }

    private func createNote() {
        let folderID: UUID?
        if case .folder(let id) = folderFilter { folderID = id } else { folderID = nil }
        let destination = appState.createNewNote(inFolder: folderID)
        appState.openNote(destination.url)
        playInkRipple()
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            route = .reading(destination.url)
        }
    }

    private func playInkRipple() {
        inkRipple = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { inkRipple = false }
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
                    Image(systemName: route == .canvas ? "folder.fill" : "arrow.left")
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

            HStack(spacing: 8) {
                if route == .canvas {
                    Button { zoom = max(0.50, zoom - 0.10) } label: { Image(systemName: "minus") }
                    Text("\(Int(zoom * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).frame(width: 38)
                    Button { zoom = min(1.30, zoom + 0.10) } label: { Image(systemName: "plus") }
                    Divider().frame(height: 18).opacity(0.25)
                    Button(action: createNote) { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New note")
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
    let openNote: (CanvasNoteSnapshot) -> Void

    private let columns = Array(repeating: GridItem(.fixed(300), spacing: 30), count: 3)

    var body: some View {
        ScrollViewReader { reader in
            ScrollView([.horizontal, .vertical]) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        CanvasNoteCard(note: note, selected: index == selectedIndex)
                            .id(note.id)
                            .onTapGesture {
                                selectedIndex = index
                                openNote(note)
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
                Circle().fill(accent).frame(width: 9, height: 9)
            }
            .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.7).opacity(0.52)
            Spacer(minLength: 18)
            Text(note.title)
                .font(.custom("Newsreader Display", size: 29, relativeTo: .title))
                .lineLimit(2)
            Text(note.excerpt)
                .font(.custom("Newsreader", size: 15, relativeTo: .body))
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
        .background(CanvasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? CanvasPalette.inkBlue : CanvasPalette.ink.opacity(0.10), lineWidth: selected ? 2 : 1))
        .rotationEffect(.degrees(Double(abs(note.url.lastPathComponent.hashValue) % 3) - 1))
        .shadow(color: CanvasPalette.ink.opacity(0.13), radius: 14, y: 8)
        .contentShape(Rectangle())
    }

    private var accent: Color {
        let choices = [CanvasPalette.inkBlue, CanvasPalette.inkBlue.opacity(0.72), CanvasPalette.inkBlue.opacity(0.48)]
        return choices[abs(note.url.lastPathComponent.hashValue) % choices.count]
    }
}

private struct CaptureReadingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeCaptureID: UUID?
    @State private var tab: ReaderTab = .raw
    @State private var tabRipple = false

    private var activeStep: ExplorationStep? {
        appState.steps.first { $0.id == activeCaptureID } ?? appState.steps.last
    }

    private var captureAnnotation: String {
        guard let step = activeStep else { return "" }
        return appState.stepAnnotations[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ReaderTabBar(selection: $tab, ripple: $tabRipple)
                .padding(.top, 78).padding(.bottom, 8)

            Group {
                switch tab {
                case .raw:
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            rawNoteColumn
                                .frame(width: proxy.size.width / 3)
                            captureColumn
                                .frame(width: proxy.size.width * 2 / 3)
                        }
                    }
                    .transition(.opacity)
                case .organized:
                    OrganizedEssayView()
                        .environmentObject(appState)
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.28), value: tab)
        }
        .overlay { InkRippleTransition(active: tabRipple).allowsHitTesting(false) }
    }

    private var rawNoteColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.activeNoteURL.map { appState.folderPath(for: appState.folderID(for: $0)) }.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "NOTE")
                .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5).opacity(0.48)
            TextField("Untitled note", text: $appState.noteTitle)
                .textFieldStyle(.plain)
                .font(.custom("Newsreader Display", size: 40, relativeTo: .largeTitle))
                .onChange(of: appState.noteTitle) { appState.scheduleActiveNoteAutosave() }

            ZStack(alignment: .topLeading) {
                if appState.rawDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write the note you want to keep beside these captures…")
                        .font(.custom("Newsreader", size: 16)).italic().opacity(0.42)
                        .padding(.top, 7).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $appState.rawDraft)
                    .font(.custom("Newsreader", size: 17, relativeTo: .body))
                    .lineSpacing(7).scrollContentBackground(.hidden)
                    .background(.clear)
                    .onChange(of: appState.rawDraft) { appState.scheduleActiveNoteAutosave() }
            }
            .frame(maxHeight: 280)

            if !captureAnnotation.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("ON THIS CAPTURE").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.2).opacity(0.42)
                    Text(captureAnnotation).font(.custom("Newsreader", size: 15)).italic().lineLimit(4)
                }
                .id(activeCaptureID)
                .transition(.opacity)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 38).padding(.vertical, 32)
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
    @Binding var ripple: Bool
    @Namespace private var inkSelection

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ReaderTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    ripple = true
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { selection = tab }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { ripple = false }
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(selection == tab ? CanvasPalette.paper : CanvasPalette.ink.opacity(0.54))
                        .padding(.horizontal, 19).frame(height: 34)
                        .background {
                            if selection == tab {
                                Capsule().fill(CanvasPalette.inkBlue)
                                    .matchedGeometryEffect(id: "ink-tab", in: inkSelection)
                                    .overlay(alignment: .trailing) {
                                        Circle().fill(CanvasPalette.inkBlue.opacity(0.55)).frame(width: 8).offset(x: 4, y: -9)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CanvasPalette.paper.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(CanvasPalette.inkBlue.opacity(0.13)))
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
                            .background(CanvasPalette.inkBlue.opacity(0.09), in: Capsule())
                        Spacer()
                        organizeMenu
                    }

                    Text(appState.noteTitle)
                        .font(.custom("Newsreader Display", size: 46, relativeTo: .largeTitle))

                    if appState.isOrganizing {
                        InkWritingLoader(status: appState.recordingStatus ?? "Organizing your captures…")
                            .frame(maxWidth: .infinity).padding(.vertical, 70)
                    } else if appState.organizedDraft.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("This note has not been organized yet.")
                                .font(.custom("Newsreader", size: 22))
                            Text("Choose a structure and Noted will turn the raw note and captures into one readable page using your configured model.")
                                .font(.custom("Newsreader", size: 17)).lineSpacing(7).opacity(0.58)
                            organizeMenu
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

    private var organizeMenu: some View {
        Menu {
            ForEach(OrganizationTemplate.allCases) { template in
                Button { appState.organizeCurrentSession(as: template) } label: {
                    Label(template.rawValue, systemImage: template.icon)
                }
            }
        } label: {
            Label(appState.organizedDraft.isEmpty ? "Organize" : "Reorganize", systemImage: "sparkles")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 14).frame(height: 38)
                .foregroundStyle(CanvasPalette.paper)
                .background(CanvasPalette.inkBlue, in: Capsule())
        }
        .menuStyle(.borderlessButton).fixedSize()
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
                .font(.custom("Newsreader Display", size: 28, relativeTo: .title2))
                .padding(.top, 14)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.custom("Newsreader", size: 18, relativeTo: .body))
                .lineSpacing(9)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(CanvasPalette.inkBlue).frame(width: 6, height: 6)
                Text(inlineMarkdown(text))
                    .font(.custom("Newsreader", size: 18, relativeTo: .body)).lineSpacing(8)
            }
        case .checklist(let text, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(CanvasPalette.inkBlue)
                Text(inlineMarkdown(text))
                    .font(.custom("Newsreader", size: 18, relativeTo: .body)).lineSpacing(8)
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
    @EnvironmentObject private var appState: AppState
    let step: ExplorationStep
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(kindLabel) · \(step.timestamp.formatted(date: .omitted, time: .shortened))".uppercased())
                Spacer()
                Image(systemName: kindIcon)
            }
            .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.1).opacity(0.48)

            if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: height * 0.46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(step.windowTitle.isEmpty ? step.appName : step.windowTitle)
                    .font(.custom("Newsreader Display", size: 30, relativeTo: .title)).lineLimit(2)
                if let text = primaryText, !text.isEmpty {
                    Text(text).font(.custom("Newsreader", size: 17, relativeTo: .body)).lineSpacing(6).lineLimit(8).opacity(0.70)
                }
                if let url = step.url, let destination = URL(string: url) {
                    Link(destination.host() ?? url, destination: destination)
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(CanvasPalette.inkBlue)
                }
            }
            Spacer(minLength: 0)
            TextField("Add your thought about this capture…", text: annotationBinding)
                .textFieldStyle(.plain)
                .font(.custom("Newsreader", size: 15)).italic()
                .padding(12).background(CanvasPalette.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit(appState.saveActiveNote)
        }
        .padding(30).frame(maxWidth: .infinity).frame(height: height)
        .background(CanvasPalette.paper.opacity(0.93), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            CanvasInkBlob().fill(CanvasPalette.inkBlue.opacity(0.10)).frame(width: 170, height: 140).offset(x: 30, y: -22).clipped()
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CanvasPalette.ink.opacity(0.11)))
        .shadow(color: CanvasPalette.ink.opacity(0.12), radius: 18, y: 10)
    }

    private var primaryText: String? { step.selectedText ?? step.pageText }
    private var kindLabel: String { step.screenshotPath != nil ? "Capture" : (step.appName.localizedCaseInsensitiveContains("audio") ? "Voice" : "Text") }
    private var kindIcon: String { step.screenshotPath != nil ? "photo" : (step.appName.localizedCaseInsensitiveContains("audio") ? "waveform" : "text.alignleft") }
    private var annotationBinding: Binding<String> {
        Binding(
            get: { appState.stepAnnotations[step.id] ?? "" },
            set: {
                appState.stepAnnotations[step.id] = $0
                appState.scheduleActiveNoteAutosave()
            }
        )
    }
}

private struct CanvasFolderOverlay: View {
    @EnvironmentObject private var appState: AppState
    @Binding var filter: CanvasFolderFilter
    @Binding var isOpen: Bool
    let notes: [CanvasNoteSnapshot]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.06).ignoresSafeArea().onTapGesture { withAnimation { isOpen = false } }
            VStack(alignment: .leading, spacing: 4) {
                Text("FOLDERS").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5).opacity(0.48).padding(.bottom, 8)
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
}

private enum CanvasPalette {
    static let clay = Color(hex: 0xD1A87F)
    static let clayLight = Color(hex: 0xE8CAA4)
    static let paper = Color(hex: 0xF4E8CF)
    static let ink = Color(hex: 0x1B1816)
    static let inkBlue = Color(hex: 0x243B68)
    static let inkBlueDeep = Color(hex: 0x172A50)
    static let inkBlueLight = Color(hex: 0x4D6692)
}

private struct CanvasBrandMark: View {
    private var bundledLogo: NSImage? {
        if let named = NSImage(named: "NotedLogo") { return named }
        guard let url = Bundle.main.url(forResource: "NotedLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let bundledLogo {
                Image(nsImage: bundledLogo).resizable().scaledToFit()
            } else {
                Text("noted")
                    .font(.custom("Instrument Serif", size: 25, relativeTo: .title))
            }
        }
        .frame(height: 25)
        .accessibilityLabel("Noted")
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

private struct CanvasClayBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breathe = reduceMotion ? 1 : 1 + sin(time * 0.42) * 0.018
            let drift = reduceMotion ? 0 : sin(time * 0.31) * 7
            ZStack {
                LinearGradient(colors: [CanvasPalette.clayLight, CanvasPalette.clay], startPoint: .topLeading, endPoint: .bottomTrailing)
                InkSplashCluster(scale: breathe)
                    .frame(width: 470, height: 390).rotationEffect(.degrees(-18)).offset(x: -485 + drift, y: -285)
                InkSplashCluster(scale: 0.82 / breathe)
                    .frame(width: 390, height: 320).rotationEffect(.degrees(27)).offset(x: 510 - drift, y: -270)
                InkSplashCluster(scale: 1.05 * breathe)
                    .frame(width: 500, height: 390).rotationEffect(.degrees(11)).offset(x: 450, y: 350 + drift)
            }
        }
        .ignoresSafeArea()
    }
}

private struct InkSplashCluster: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            CanvasInkBlob()
                .fill(CanvasPalette.inkBlue.opacity(0.17))
                .scaleEffect(scale)
            Circle().fill(CanvasPalette.inkBlue.opacity(0.22)).frame(width: 17).offset(x: -185, y: 115)
            Circle().fill(CanvasPalette.inkBlue.opacity(0.15)).frame(width: 9).offset(x: -160, y: 145)
            Circle().fill(CanvasPalette.inkBlue.opacity(0.19)).frame(width: 12).offset(x: 182, y: -105)
            Capsule().fill(CanvasPalette.inkBlue.opacity(0.12)).frame(width: 44, height: 8).rotationEffect(.degrees(-28)).offset(x: 156, y: 128)
        }
    }
}

private struct InkRippleTransition: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(CanvasPalette.inkBlue.opacity(active ? 0 : 0.34), lineWidth: active ? 2 : 18)
                .frame(width: active ? 920 : 24, height: active ? 920 : 24)
            Circle()
                .stroke(CanvasPalette.inkBlueLight.opacity(active ? 0 : 0.24), lineWidth: active ? 1 : 12)
                .frame(width: active ? 670 : 16, height: active ? 670 : 16)
            CanvasInkBlob()
                .fill(CanvasPalette.inkBlue.opacity(active ? 0 : 0.12))
                .frame(width: active ? 300 : 18, height: active ? 250 : 15)
                .rotationEffect(.degrees(active ? 28 : 0))
        }
        .opacity(active ? 1 : 0)
        .animation(reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.72), value: active)
    }
}
