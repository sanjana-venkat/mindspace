import SwiftUI
import NotefyCore

enum AuroraNoteMode: String, CaseIterable, Identifiable {
    case panels = "Panels", organized = "Organized", grid = "Grid"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .panels: return "rectangle.split.2x1"
        case .organized: return "text.alignleft"
        case .grid: return "square.grid.3x2"
        }
    }
}

struct AuroraMidYKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, b in b }
    }
}

/// The note reader. Three ways through the same captures: side by side with
/// your own notes, structured by the model, or spread out as tiles.
struct AuroraNoteView: View {
    let noteURL: URL
    /// What was searched for, when this note was opened from a search result:
    /// the view jumps to the capture the words are in and lights them up.
    var searchMark: String? = nil
    /// The capture the search matched, when it matched one.
    var searchStep: UUID? = nil
    /// True when the match was in the write-up rather than in a capture.
    var searchInWriteUp: Bool = false
    var onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var mode: AuroraNoteMode = .panels
    @State private var active: Int = 0
    @State private var menuTarget: AuroraCaptureTarget?
    /// How much of the note fits on screen at once. Zooming out is how you see
    /// twenty captures in one glance rather than scrolling through them.
    @State private var zoom: Double = 1
    /// Where the zoom was when the current pinch started.
    @State private var pinchBase: Double = 1
    @State private var pinching = false
    /// While a pinch or a zoom step is in flight the grid is scaled as a
    /// picture by this much, and laid out at the new size once, at the end.
    /// Laying it out on every pinch event redrew every caption in every tile
    /// over a hundred times a second, which froze the window.
    @State private var liveScale: CGFloat = 1
    @State private var liveAnchor: UnitPoint = .top
    @State private var glideToken = 0
    /// The size shown in the label: where the zoom is heading, not where the
    /// layout has got to.
    private var shownZoom: Double { zoom * Double(liveScale) }
    /// Set when a search result asks for a particular capture, cleared once
    /// the panel list has scrolled to it.
    @State private var focusRequest: Int?
    /// Renaming the note from its own header.
    @State private var renamingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    /// Display order matches the rest of the app: `steps` is stored one way and
    /// read the other.
    private var steps: [ExplorationStep] { appState.stepsInViewOrder }

    var body: some View {
        ZStack {
            AuroraGround()
            if mode == .panels {
                AuroraNight(seed: Aurora.stableHash(noteURL.lastPathComponent) % 5)
                    .frame(width: AuroraPanels.columnWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                header
                Group {
                    switch mode {
                    case .panels:
                        AuroraPanels(steps: steps, active: $active, thought: thought, zoom: zoom,
                                     focus: $focusRequest,
                                     dimmedFor: menuTarget?.step.id,
                                     onRightClick: { step, point in
                                         menuTarget = AuroraCaptureTarget(step: step, point: point)
                                     })
                    case .organized:
                        AuroraOrganized(steps: steps) { i in
                            active = i
                            withAnimation(.smooth(duration: 0.3)) { mode = .panels }
                        }
                    case .grid:
                        AuroraGrid(steps: steps, active: $active, thought: thought,
                                   dimmedFor: menuTarget?.step.id,
                                   onRightClick: { step, point in
                                       menuTarget = AuroraCaptureTarget(step: step, point: point)
                                   },
                                   commit: { ordered in
                                       appState.steps = Array(ordered.reversed())
                                       appState.scheduleActiveNoteAutosave()
                                   },
                                   open: { i in
                                       active = i
                                       withAnimation(.smooth(duration: 0.3)) { mode = .panels }
                                   },
                                   preview: { i in
                                       withAnimation(.smooth(duration: 0.22)) { appState.capturePreview = i }
                                   },
                                   zoom: zoom,
                                   liveScale: liveScale,
                                   liveAnchor: liveAnchor,
                                   selection: Binding(
                                       get: { appState.selectedStepIDs },
                                       set: { appState.selectedStepIDs = $0 }
                                   ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Pinch to zoom, the same as the canvas: the captures page is
                // the other place in the app where you want to see everything
                // at once, and reaching for the minus button is not that.
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            liveAnchor = value.startAnchor
                            pinchChanged(value.magnification)
                        }
                        .onEnded { _ in pinchEnded() }
                )
            }

            if mode == .organized {
                organizeAction
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.opacity)
                    .zIndex(4)
            }

            if let target = menuTarget {
                GeometryReader { geo in
                    ZStack {
                        Color.black.opacity(0.06)
                            .contentShape(Rectangle())
                            .onTapGesture { menuTarget = nil }
                        AuroraCaptureActions(target: target, bounds: geo.size) { menuTarget = nil }
                    }
                }
                .transition(.opacity)
                .zIndex(5)
            }
        
            if appState.capturePreview != nil {
                AuroraCaptureViewer(steps: steps,
                                    index: Binding(get: { appState.capturePreview },
                                                   set: { appState.capturePreview = $0 }),
                                    thought: { thought($0).wrappedValue })
                    .transition(.opacity)
                    .zIndex(30)
            }
        }
        .coordinateSpace(name: "auroraNote")
        .onAppear {
            appState.noteMode = mode
            #if DEBUG
            pinchStress()
            #endif
        }
        .onChange(of: mode) { _, m in appState.noteMode = m }
        .onDisappear { appState.noteMode = nil }
        .animation(.smooth(duration: 0.22), value: menuTarget)
        .ignoresSafeArea()
        // The words travel with the note, so every capture can mark them.
        .environment(\.auroraSearchMark, searchMark)
        .onAppear {
            // Opened from a search result: go where the search actually found
            // the words. The search worked that out already — this no longer
            // re-derives it and risks landing somewhere else.
            guard searchMark?.isEmpty == false else { return }
            if let searchStep, let index = steps.firstIndex(where: { $0.id == searchStep }) {
                active = index
                focusRequest = index
            } else if searchInWriteUp, !appState.organizedDraft.isEmpty {
                mode = .organized
            }
        }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingTitle = false
        guard !trimmed.isEmpty, trimmed != appState.noteTitle else { return }
        appState.renameNote(noteURL, to: trimmed)
    }

    /// Your thought about one capture, written straight back into the note.
    private func thought(_ id: UUID) -> Binding<String> {
        Binding(
            get: { appState.stepAnnotations[id] ?? "" },
            set: { appState.stepAnnotations[id] = $0; appState.scheduleActiveNoteAutosave() }
        )
    }

    /// A plain button hit-tests the pixels its label actually draws, so a 10pt
    /// glyph in a 26pt frame left most of the target dead — clicks near the
    /// edge went nowhere and it felt like it needed a second try. The shape is
    /// declared explicitly, and the target given room.
    /// One step of 15%, landed on a whole percent. Adding 0.15 to a double
    /// drifted, so the label read 99% or 114% after a step or two.
    private func pinchChanged(_ magnification: CGFloat) {
        guard mode == .grid else { return }
        // The base is taken once, when the fingers land; updating it mid-pinch
        // compounds the scale and the page runs away from you.
        if !pinching {
            pinching = true
            pinchBase = zoom
        }
        let target = min(2.0, max(0.45, pinchBase * magnification))
        liveScale = CGFloat(target / zoom)
    }

    private func pinchEnded() {
        guard pinching else { return }
        pinching = false
        commitZoom((shownZoom * 100).rounded() / 100)
    }

    /// Lays the grid out at its new size in one pass, without animating the
    /// layout, and drops the picture scale in the same transaction so nothing
    /// jumps between the two.
    private func commitZoom(_ target: Double) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            zoom = target
            liveScale = 1
        }
        pinchBase = target
    }

    /// Buttons and keys: glide the picture to the new size, then lay it out.
    private func glideZoom(to target: Double) {
        // A pinch the system cancelled never reports its end; a button
        // press means it is over, so settle it rather than ignore the press.
        if pinching { pinchEnded() }
        guard abs(target - zoom) > 0.001 || liveScale != 1 else { return }
        liveAnchor = .top
        withAnimation(.smooth(duration: 0.16)) {
            liveScale = CGFloat(target / zoom)
        }
        // Lay out once the glide has landed. A timer rather than the
        // animation's completion, which can wait for the next frame that
        // happens to be drawn. Rapid presses keep only the last one.
        glideToken += 1
        let token = glideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if token == glideToken, !pinching { commitZoom(target) }
        }
    }

    #if DEBUG
    /// MINDSPACE_PINCH_STRESS=1: opens the grid and plays a pinch out and back
    /// at trackpad rate, then presses minus, timing each frame on stderr.
    private func pinchStress() {
        guard ProcessInfo.processInfo.environment["MINDSPACE_PINCH_STRESS"] != nil else { return }
        mode = .grid
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            var worst = 0.0
            var path: [Double] = []
            for i in 0...60 { path.append(1 + Double(i) / 60 * 0.9) }
            for i in 0...60 { path.append(1.9 - Double(i) / 60 * 1.4) }
            for m in path {
                let t = Date()
                pinchChanged(m)
                try? await Task.sleep(for: .milliseconds(16))
                worst = max(worst, Date().timeIntervalSince(t))
            }
            pinchEnded()
            fputs("[pinch] done zoom=\(zoom) worstFrame=\(Int(worst * 1000))ms\n", stderr)
            for _ in 0..<3 {
                stepZoom(1)
                try? await Task.sleep(for: .milliseconds(300))
                fputs("[pinch] plus -> \(zoom)\n", stderr)
            }
            for _ in 0..<3 {
                stepZoom(-1)
                try? await Task.sleep(for: .milliseconds(300))
                fputs("[pinch] minus -> \(zoom)\n", stderr)
            }
        }
    }
    #endif

    private func stepZoom(_ direction: Int) {
        if pinching { pinchEnded() }
        let next = (shownZoom * 100).rounded() + Double(direction) * 15
        glideZoom(to: min(200, max(45, next)) / 100)
    }

    private func zoomButton(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Aurora.ink : Aurora.ink3)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(AuroraTapDown())
        .disabled(!enabled)
    }

    private func viewIcon(_ m: AuroraNoteMode) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.28)) { mode = m }
        } label: {
            Image(systemName: m.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == m ? Aurora.onSolid : Aurora.ink2)
                .frame(width: 40, height: 30)
                .background(mode == m ? AnyShapeStyle(Aurora.solid) : AnyShapeStyle(Color.clear), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(m.rawValue)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            let onNight = mode == .panels
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(onNight ? .white : Aurora.ink2)
                    .frame(width: 32, height: 32)
                    .background(onNight ? AnyShapeStyle(Color.white.opacity(0.16)) : AnyShapeStyle(.regularMaterial),
                                in: Circle())
                    .overlay(Circle().strokeBorder(onNight ? .white.opacity(0.3) : Aurora.line, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Double-click the title to rename the note, the same gesture the
            // folders and the rows in the list use.
            Group {
                if renamingTitle {
                    TextField("", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(Aurora.display(23))
                        .foregroundStyle(onNight ? .white : Aurora.ink)
                        .focused($titleFocused)
                        .onSubmit { commitTitle() }
                        .onExitCommand { renamingTitle = false }
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(onNight ? AnyShapeStyle(Color.white.opacity(0.14)) : AnyShapeStyle(Aurora.surface2),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(onNight ? .white.opacity(0.4) : Aurora.focusRing, lineWidth: 1.5))
                } else {
                    Text(appState.noteTitle)
                        .font(Aurora.display(23))
                        .foregroundStyle(onNight ? .white : Aurora.ink)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            titleDraft = appState.noteTitle
                            renamingTitle = true
                            titleFocused = true
                        }
                        .help("Double-click to rename")
                }
            }
            .frame(maxWidth: onNight ? 300 : .infinity, alignment: .leading)

            Spacer(minLength: 20)

            HStack(spacing: 10) {
                // Only the grid scales. Panel view is a fixed column by
                // design, so a zoom control there is a dead knob.
                if mode == .grid {
                    HStack(spacing: 2) {
                        zoomButton("minus", enabled: shownZoom > 0.5) { stepZoom(-1) }
                            .help("Smaller  (\u{2318}\u{2212})")
                            .keyboardShortcut("-", modifiers: .command)
                        Text("\(Int((shownZoom * 100).rounded()))%")
                            .font(Aurora.mono(11)).foregroundStyle(Aurora.ink2)
                            .frame(width: 44, height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { glideZoom(to: 1) }
                            .help("Back to 100%")
                        zoomButton("plus", enabled: shownZoom < 1.95) { stepZoom(1) }
                            .help("Bigger  (\u{2318}+)")
                            .keyboardShortcut("=", modifiers: .command)
                        // \u{2318}0 resets, as in a browser.
                        Button("") { glideZoom(to: 1) }
                            .keyboardShortcut("0", modifiers: .command)
                            .frame(width: 0, height: 0).opacity(0)
                    }
                    .padding(3)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                }

                HStack(spacing: 3) {
                    viewIcon(.panels)
                    viewIcon(.grid)
                }
                .padding(4)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))

                Button {
                    withAnimation(.smooth(duration: 0.28)) { mode = .organized }
                } label: {
                    OverlayIcon(kind: .spark, tint: mode == .organized ? Aurora.onSolid : Aurora.ink)
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 38)
                        .background(mode == .organized ? AnyShapeStyle(Aurora.solid) : AnyShapeStyle(.regularMaterial),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(mode == .organized ? .clear : Aurora.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Organize this note")
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 46).padding(.bottom, 8)
        .padding(.bottom, 10)
    }

    /// Writing the note is the biggest thing you can do on this screen, so it
    /// sits where your hand already is — bottom-right, over the text, above
    /// everything else.
    @ViewBuilder
    private var organizeAction: some View {
        let fresh = appState.organizedDraft.isEmpty
        let stale = appState.organizedIsStale
        VStack(alignment: .trailing, spacing: 8) {
            if stale, !appState.isOrganizing {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Aurora.warning)
                    Text("Changed since this was written")
                        .font(Aurora.ui(11.5, .medium)).foregroundStyle(Aurora.ink2)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Aurora.warning.opacity(0.45), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Button {
                appState.showOrganized(appState.organizedTemplate, force: true)
            } label: {
                HStack(spacing: 10) {
                    if appState.isOrganizing {
                        ProgressView().controlSize(.small).tint(Aurora.onSolid)
                    } else if fresh {
                        OverlayIcon(kind: .spark, tint: Aurora.onSolid).frame(width: 17, height: 17)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold))
                    }
                    Text(appState.isOrganizing ? "Organizing…" : (fresh ? "Organize" : "Re-organize"))
                        .font(Aurora.ui(15, .bold))
                }
                .foregroundStyle(Aurora.onSolid)
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Aurora.solid, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    // The same warning as a dot, for when the banner has been
                    // scrolled past or the window is narrow.
                    if stale, !appState.isOrganizing {
                        Circle().fill(Aurora.warning)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Aurora.ground, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
            }
            .buttonStyle(AuroraPressStyle())
            .disabled(appState.isOrganizing || steps.isEmpty)
            .opacity(steps.isEmpty ? 0.5 : 1)
            .help(fresh ? "Write this note up" : "Write it again from the captures as they are now")
        }
        .padding(.trailing, 30)
        // Over the write-up the question box is pinned to the foot, so the
        // button sits above it rather than on top of it.
        .padding(.bottom, 30)
        .animation(.smooth(duration: 0.25), value: stale)
        .animation(.smooth(duration: 0.25), value: appState.isOrganizing)
    }
}

// MARK: - Panels

/// Captures scroll on the right; the thought attached to the one in view fades
/// in on the left, one at a time, editable in place.
struct AuroraPanels: View {
    static let columnWidth: CGFloat = 430

    let steps: [ExplorationStep]
    @Binding var active: Int
    var thought: (UUID) -> Binding<String>
    var zoom: Double = 1
    /// A capture to scroll to once, when the note is opened from a search.
    @Binding var focus: Int?
    var dimmedFor: UUID?
    var onRightClick: (ExplorationStep, CGPoint) -> Void

    @State private var suppressSync = false
    @FocusState private var keyboard: Bool
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: Self.columnWidth)
            right
        }
        .focusable()
        .focused($keyboard)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            guard !editing else { return .ignored }
            switch press.key {
            case .downArrow, .rightArrow: goTo(active + 1); return .handled
            case .upArrow, .leftArrow: goTo(active - 1); return .handled
            default: return .ignored
            }
        }
        .onAppear { keyboard = true }
    }

    /// Everything but the capture you right-clicked steps back.
    private func dimmed(_ step: ExplorationStep) -> Bool {
        guard let dimmedFor else { return false }
        return step.id != dimmedFor
    }

    private func goTo(_ i: Int) {
        let next = max(0, min(steps.count - 1, i))
        guard next != active else { return }
        suppressSync = true
        withAnimation(.smooth(duration: 0.35)) { active = next }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { suppressSync = false }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your thought")
                .font(Aurora.mono(10)).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 34).padding(.top, 34)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        card(i, step).opacity(i == active ? 1 : 0)
                    }
                }
                .padding(.horizontal, 34).padding(.vertical, 26)
            }
            .scrollIndicators(.never)
        }
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    /// Aurora, not confetti: vertical curtains of light leaning off true,
    /// brightest at the left edge and fading out across the panel. The hues
    /// shift with the capture you are on.
    private func card(_ i: Int, _ step: ExplorationStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Text(String(format: "%02d", i + 1))
                    .font(Aurora.mono(10)).foregroundStyle(.white.opacity(0.75))
                // Cited rather than chipped: when the words underneath are
                // someone's own thought, the time they thought it reads as an
                // attribution, not as a tag on a piece of metadata.
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(.white.opacity(0.35))
                        .frame(width: 2, height: 13)
                    Text(step.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(Aurora.serif(12).italic())
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 8)
                Button { goTo(active - 1) } label: { chevron("chevron.up") }
                    .buttonStyle(.plain).disabled(active == 0)
                Button { goTo(active + 1) } label: { chevron("chevron.down") }
                    .buttonStyle(.plain).disabled(active >= steps.count - 1)
            }

            // One editor, drawing its own prompt: the placeholder is laid out
            // by the same text container as the typing, so the caret lands
            // exactly where the prompt was.
            AuroraThoughtEditor(
                text: thought(step.id),
                placeholder: "What were you thinking when you saved this?",
                font: .auroraSerif(20),
                textColor: .white,
                lineSpacing: 7,
                inset: CGSize(width: 0, height: 2))
                .frame(minHeight: 120, alignment: .topLeading)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.14), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
    }

    /// Jumps to a capture a search asked for. The list normally follows the
    /// scroll position, so the sync is held off until the jump has landed.
    private func scroll(to request: Int?, using proxy: ScrollViewProxy) {
        guard let request, steps.indices.contains(request) else { return }
        suppressSync = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(request, anchor: .center) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            suppressSync = false
            focus = nil
        }
    }

    private var right: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 34) {
                        Spacer(minLength: 14)
                        ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                            AuroraCaptureView(step: step, index: i)
                                .frame(maxWidth: 780 * zoom)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(i == active ? Aurora.focusRing.opacity(0.75) : Aurora.line,
                                                  lineWidth: i == active ? 2 : 1))
                                .blur(radius: dimmed(step) ? 4 : 0)
                                .opacity(dimmed(step) ? 0.45 : 1)
                                .auroraRightClick(in: "auroraNote") { onRightClick(step, $0) }
                                // Readable even when not the one you're on; the
                                // ring around the active capture is what marks it.
                                .opacity(i == active ? 1 : 0.85)
                                .animation(.smooth(duration: 0.3), value: active)
                                .id(i)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: AuroraMidYKey.self,
                                                           value: [i: g.frame(in: .global).midY])
                                })
                        }
                        Spacer(minLength: 200)
                    }
                    .padding(.horizontal, 44).padding(.top, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
                .onPreferenceChange(AuroraMidYKey.self) { value in
                    guard !suppressSync else { return }
                    // Read position, not centre: at rest the first capture is
                    // the one you are on, which centring got wrong by one.
                    let box = outer.frame(in: .global)
                    let center = box.minY + box.height * 0.38
                    if let nearest = value.min(by: { abs($0.value - center) < abs($1.value - center) })?.key,
                       nearest != active {
                        withAnimation(.easeInOut(duration: 0.3)) { active = nearest }
                    }
                }
                .onChange(of: active) { _, newValue in
                    guard suppressSync else { return }
                    withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo(newValue, anchor: .center) }
                }
                .onChange(of: focus) { _, request in scroll(to: request, using: proxy) }
                .onAppear { scroll(to: focus, using: proxy) }
            }
        }
    }
}


/// A real aurora, drawn rather than faked with blurred blobs: four wavy
/// ribbons hanging vertically, each running green at the base through teal to
/// violet at the tips, drifting slowly the way a curtain does. Painted in a
/// Canvas so the shapes can actually undulate, then blurred so it reads as
/// light rather than as geometry.
struct AuroraCurtain: View {
    var seed: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A polar-light ramp, bottom to top: this is what makes it read as aurora
    // rather than as a gradient — green low, violet at the tips.
    private let green = Color(red: 0.53, green: 0.86, blue: 0.66)
    private let teal = Color(red: 0.55, green: 0.83, blue: 0.86)
    private let violet = Color(red: 0.76, green: 0.68, blue: 0.92)
    private let rose = Color(red: 0.91, green: 0.72, blue: 0.82)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.07
                for i in 0..<4 {
                    context.fill(ribbon(i, t: t, size: size), with: shading(i, size: size))
                }
            }
            .blur(radius: 26)
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.9), location: 0.45),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            )
            .opacity(0.85)
        }
    }

    /// One hanging ribbon: a vertical band whose centre line wanders and whose
    /// width breathes, sampled down the height and closed into a path.
    private func ribbon(_ i: Int, t: Double, size: CGSize) -> Path {
        let phase = Double(i) * 1.7 + Double(seed) * 0.9
        let amp = 22.0 + Double(i) * 11.0
        let baseWidth = [96.0, 58.0, 132.0, 44.0][i]
        let cx = size.width * [0.17, 0.34, 0.52, 0.26][i]

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        let samples = 26
        for s in 0...samples {
            let y = size.height * Double(s) / Double(samples)
            let wander = sin(y * 0.0062 + t + phase) * amp
                + sin(y * 0.0137 - t * 0.7 + phase * 1.3) * amp * 0.42
            let breath = baseWidth * (0.72 + 0.34 * sin(y * 0.0041 + t * 0.55 + phase))
            left.append(CGPoint(x: cx + wander - breath / 2, y: y))
            right.append(CGPoint(x: cx + wander + breath / 2, y: y))
        }

        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    private func shading(_ i: Int, size: CGSize) -> GraphicsContext.Shading {
        let tip = [violet, rose, violet, teal][(i + seed) % 4]
        return .linearGradient(
            Gradient(stops: [
                .init(color: tip.opacity(0), location: 0.0),
                .init(color: tip.opacity(0.55), location: 0.18),
                .init(color: teal.opacity(0.7), location: 0.42),
                .init(color: green.opacity(0.92), location: 0.72),
                .init(color: green.opacity(0.25), location: 0.95),
                .init(color: .clear, location: 1.0)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height))
    }
}

