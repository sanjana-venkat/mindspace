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
    var onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var mode: AuroraNoteMode = .panels
    @State private var active: Int = 0
    @State private var menuTarget: AuroraCaptureTarget?

    /// Display order matches the rest of the app: `steps` is stored one way and
    /// read the other.
    private var steps: [ExplorationStep] {
        Array(appState.steps.reversed()).filter { step in
            if step.screenshotPath != nil { return true }
            let text = (step.selectedText ?? "") + (step.pageText ?? "")
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

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
                        AuroraPanels(steps: steps, active: $active, thought: thought,
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
                                   })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .coordinateSpace(name: "auroraNote")
        .animation(.smooth(duration: 0.22), value: menuTarget)
        .ignoresSafeArea()
    }

    /// Your thought about one capture, written straight back into the note.
    private func thought(_ id: UUID) -> Binding<String> {
        Binding(
            get: { appState.stepAnnotations[id] ?? "" },
            set: { appState.stepAnnotations[id] = $0; appState.scheduleActiveNoteAutosave() }
        )
    }

    private func viewIcon(_ m: AuroraNoteMode) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.28)) { mode = m }
        } label: {
            Image(systemName: m.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == m ? Aurora.ground : Aurora.ink2)
                .frame(width: 40, height: 30)
                .background(mode == m ? AnyShapeStyle(Aurora.ink) : AnyShapeStyle(Color.clear), in: Capsule())
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

            Text(appState.noteTitle)
                .font(Aurora.display(23))
                .foregroundStyle(onNight ? .white : Aurora.ink)
                .lineLimit(1)
                .frame(maxWidth: onNight ? 300 : .infinity, alignment: .leading)

            Spacer(minLength: 20)

            HStack(spacing: 10) {
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
                    Text("Organize").font(Aurora.ui(13))
                    .foregroundStyle(mode == .organized ? Aurora.ground : Aurora.ink)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(mode == .organized ? AnyShapeStyle(Aurora.ink) : AnyShapeStyle(.regularMaterial),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(mode == .organized ? .clear : Aurora.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 46).padding(.bottom, 18)
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
                Text(step.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(Aurora.mono(9.5)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.16), in: Capsule())
                Spacer(minLength: 8)
                Button { goTo(active - 1) } label: { chevron("chevron.up") }
                    .buttonStyle(.plain).disabled(active == 0)
                Button { goTo(active + 1) } label: { chevron("chevron.down") }
                    .buttonStyle(.plain).disabled(active >= steps.count - 1)
            }

            TextEditor(text: thought(step.id))
                .font(Aurora.serif(20))
                .foregroundStyle(.white)
                .lineSpacing(7)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($editing)
                .frame(minHeight: 120, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if thought(step.id).wrappedValue.isEmpty {
                        Text("What were you thinking when you saved this?")
                            .font(Aurora.serif(20))
                            .foregroundStyle(.white.opacity(0.45))
                            .allowsHitTesting(false)
                            .padding(.top, 8).padding(.leading, 5)
                    }
                }

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

    private var right: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 34) {
                        Spacer(minLength: 14)
                        ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                            AuroraCaptureView(step: step, index: i)
                                .frame(maxWidth: 780)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(i == active ? Aurora.accent.opacity(0.55) : Aurora.line,
                                                  lineWidth: i == active ? 2 : 1))
                                .blur(radius: dimmed(step) ? 4 : 0)
                                .opacity(dimmed(step) ? 0.45 : 1)
                                .auroraRightClick(in: "auroraNote") { onRightClick(step, $0) }
                                .opacity(i == active ? 1 : 0.55)
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

