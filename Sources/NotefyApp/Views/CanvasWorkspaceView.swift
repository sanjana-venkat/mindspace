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

struct CanvasWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var route: CanvasRoute = .canvas
    @State private var folderFilter: CanvasFolderFilter = .all
    @State private var foldersOpen = false
    @State private var settingsOpen = false
    @State private var zoom: CGFloat = 0.84
    @State private var selectedIndex = 0
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
                    CaptureReadingView(back: { withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { route = .canvas } })
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
        }
        .focusable()
        .focused($keyboardFocused)
        .onAppear {
            appState.refreshHistory()
            keyboardFocused = true
        }
        .onKeyPress(.leftArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.rightArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-canvasColumnCount); return .handled }
        .onKeyPress(.downArrow) { moveSelection(canvasColumnCount); return .handled }
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
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            route = .reading(snapshot.url)
        }
    }

    private func createNote() {
        let folderID: UUID?
        if case .folder(let id) = folderFilter { folderID = id } else { folderID = nil }
        let destination = appState.createNewNote(inFolder: folderID)
        appState.openNote(destination.url)
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            route = .reading(destination.url)
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
        ScrollView([.horizontal, .vertical]) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    CanvasNoteCard(note: note, selected: index == selectedIndex)
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
        .gesture(
            MagnifyGesture().onChanged { value in
                zoom = min(max(zoom * value.magnification, 0.50), 1.30)
            }
        )
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
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? CanvasPalette.ink : CanvasPalette.ink.opacity(0.10), lineWidth: selected ? 2 : 1))
        .rotationEffect(.degrees(Double(abs(note.url.lastPathComponent.hashValue) % 3) - 1))
        .shadow(color: CanvasPalette.ink.opacity(0.13), radius: 14, y: 8)
        .contentShape(Rectangle())
    }

    private var accent: Color {
        let choices = [CanvasPalette.rose, CanvasPalette.blue, CanvasPalette.ochre]
        return choices[abs(note.url.lastPathComponent.hashValue) % choices.count]
    }
}

private struct CaptureReadingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeCaptureID: UUID?
    let back: () -> Void

    private var activeStep: ExplorationStep? {
        appState.steps.first { $0.id == activeCaptureID } ?? appState.steps.last
    }

    private var captureAnnotation: String {
        guard let step = activeStep else { return "" }
        return appState.stepAnnotations[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                organizedNoteColumn
                    .frame(width: proxy.size.width / 3)
                captureColumn
                    .frame(width: proxy.size.width * 2 / 3)
            }
        }
        .padding(.top, 72)
    }

    private var organizedNoteColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.activeNoteURL.map { appState.folderPath(for: appState.folderID(for: $0)) }.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "NOTE")
                .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5).opacity(0.48)
            TextField("Untitled note", text: $appState.noteTitle)
                .textFieldStyle(.plain)
                .font(.custom("Newsreader Display", size: 40, relativeTo: .largeTitle))
                .onSubmit(appState.saveActiveNote)

            Group {
                if appState.isOrganizing {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(appState.recordingStatus ?? "Organizing your captures…")
                            .font(.custom("Newsreader", size: 16)).opacity(0.62)
                    }
                } else if !appState.organizedDraft.isEmpty {
                    Text(organizedPreview)
                        .font(.custom("Newsreader", size: 16, relativeTo: .body))
                        .lineSpacing(6).lineLimit(14)
                        .contentTransition(.opacity)
                } else {
                    Text("Your organized note will live here. Choose a structure below and Noted will synthesize the captures with your configured model.")
                        .font(.custom("Newsreader", size: 16, relativeTo: .body)).lineSpacing(6).opacity(0.62)
                }
            }
            .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.32), value: appState.organizedDraft)

            if !captureAnnotation.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("ON THIS CAPTURE").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.2).opacity(0.42)
                    Text(captureAnnotation).font(.custom("Newsreader", size: 15)).italic().lineLimit(4)
                }
                .id(activeCaptureID)
                .transition(.opacity)
            }

            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Menu {
                    ForEach(OrganizationTemplate.allCases) { template in
                        Button {
                            appState.organizeCurrentSession(as: template)
                        } label: { Label(template.rawValue, systemImage: template.icon) }
                    }
                } label: {
                    Label(appState.organizedDraft.isEmpty ? "Organize" : "Reorganize", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14).frame(height: 39)
                        .foregroundStyle(CanvasPalette.paper)
                        .background(CanvasPalette.ink, in: Capsule())
                }
                .menuStyle(.borderlessButton).fixedSize()
                if let status = appState.recordingStatus, !appState.isOrganizing {
                    Text(status).font(.system(size: 10, design: .rounded)).lineLimit(2).opacity(0.48)
                }
            }
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

    private var organizedPreview: String {
        let paragraphs = appState.organizedDraft
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: #"^\s{0,3}(#{1,6}|[-*]>?|\d+\.)\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[`*_]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("Sources") }
        return String(paragraphs.prefix(9).joined(separator: "\n\n").prefix(900))
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
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(CanvasPalette.blue)
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
            CanvasInkBlob().fill(CanvasPalette.ink.opacity(0.09)).frame(width: 170, height: 140).offset(x: 30, y: -22).clipped()
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
            set: { appState.stepAnnotations[step.id] = $0 }
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
        .background(filter == value ? CanvasPalette.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 11))
    }
}

private enum CanvasPalette {
    static let clay = Color(hex: 0xD1A87F)
    static let clayLight = Color(hex: 0xE8CAA4)
    static let paper = Color(hex: 0xF4E8CF)
    static let ink = Color(hex: 0x1B1816)
    static let rose = Color(hex: 0xB05A4F)
    static let blue = Color(hex: 0x40616B)
    static let ochre = Color(hex: 0xB07A34)
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
    var body: some View {
        ZStack {
            LinearGradient(colors: [CanvasPalette.clayLight, CanvasPalette.clay], startPoint: .topLeading, endPoint: .bottomTrailing)
            CanvasInkBlob().fill(CanvasPalette.ink.opacity(0.14)).frame(width: 430, height: 350).rotationEffect(.degrees(-18)).offset(x: -480, y: -285)
            CanvasInkBlob().fill(CanvasPalette.rose.opacity(0.17)).frame(width: 350, height: 285).rotationEffect(.degrees(29)).offset(x: 500, y: -265)
            CanvasInkBlob().fill(CanvasPalette.blue.opacity(0.15)).frame(width: 480, height: 360).rotationEffect(.degrees(12)).offset(x: 445, y: 345)
            Circle().fill(CanvasPalette.ink.opacity(0.16)).frame(width: 13).offset(x: -330, y: 285)
            Circle().fill(CanvasPalette.ink.opacity(0.10)).frame(width: 7).offset(x: -300, y: 307)
            Circle().fill(CanvasPalette.rose.opacity(0.18)).frame(width: 17).offset(x: 350, y: -72)
        }
        .ignoresSafeArea()
    }
}
