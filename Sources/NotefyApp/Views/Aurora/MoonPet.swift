import SwiftUI
import AppKit

/// The moon: a small companion that sits on the desktop while you work and
/// files what you capture.
///
/// It is not a window you manage. It has no title bar, no close button and no
/// place in the window list — you drag it wherever it suits you, it stays put
/// across spaces, and it reacts when something is caught: it takes the capture,
/// tucks it into the folder it is holding, and the count on the folder goes up.
/// The point is to make the filing visible, so a run of screenshots feels like
/// handing things to someone rather than dropping them into a void.
/// What the moon can do for you. The capture rail used to be a separate slab
/// of buttons floating beside it; now the moon *is* the control — hover it and
/// its actions come out around it.
struct MoonPetActions {
    var captureRegion: () -> Void = {}
    var capturePage: () -> Void = {}
    var captureText: () -> Void = {}
    var audio: (SessionAudioSource) -> Void = { _ in }
    var meeting: () -> Void = {}
    var openApp: () -> Void = {}
}

struct MoonPetView: View {
    /// What the moon is doing. Each pose has its own drawing.
    enum Pose: Equatable {
        case idle
        /// Holding the folder out — the resting pose during a session.
        case holding
        /// Something was just caught.
        case catching
        /// It has written something down: the end of a recording.
        case pleased
    }

    /// The four things it can do, and the two ways each of the first two can
    /// be done. Clicking a ring icon opens its pair rather than firing blind.
    enum Action: Equatable, Hashable {
        case screenshot, text, audio, meeting

        var icon: OverlayIcon.Kind {
            switch self {
            case .screenshot: return .capture
            case .text: return .text
            case .audio: return .audio
            case .meeting: return .meeting
            }
        }

        var label: String {
            switch self {
            case .screenshot: return "Screen capture"
            case .text: return "Selected text"
            case .audio: return "Record audio"
            case .meeting: return "Meeting notes"
            }
        }

        var hasChoices: Bool { self == .screenshot || self == .audio }
    }

    @ObservedObject var state: MoonPetState
    var actions = MoonPetActions()
    /// Reports a drag of the moon's body: true while it is being carried,
    /// false when it is set down. The panel works out where to go from the
    /// pointer itself — measuring against a view that is being moved is a
    /// feedback loop, and it shook.
    var onDrag: (Bool) -> Void = { _ in }
    /// True while the ring is out, so the panel can widen what it hit-tests.
    var onExpanded: (Bool) -> Void = { _ in }

    @State private var hovering: Set<String> = []
    @State private var release: Task<Void, Never>?
    /// Stays true through the grace period after the pointer leaves, so the
    /// ring is still there — and still clickable — while you travel to it.
    @State private var lingering = false
    private var hover: Bool { !hovering.isEmpty }
    @State private var open: Action?
    @State private var hoveredAction: Action?
    /// True from the moment a drag starts until the mouse comes back to rest.
    @State private var dragging = false

    /// How far the ring sits from the moon's middle.
    private let ring: CGFloat = 74

    /// Picking the moon up is not asking for its controls.
    private var expanded: Bool { (hover || lingering || open != nil) && !dragging }

    var body: some View {
        ZStack {
            // The ring, laid out around the moon.
            ForEach(Array(Self.ringOrder.enumerated()), id: \.element) { index, action in
                ringButton(action, at: position(index, of: Self.ringOrder.count, radius: ring))
            }

            moon

            // Above the moon, and clear of it: the label used to be pinned to
            // its icon, so whichever icons sat on the far side had their words
            // read back across the moon's face and disappear behind it.
            if let hoveredAction, open == nil, expanded {
                label(for: hoveredAction)
            }

            if let open, open.hasChoices {
                choices(for: open)
            }
        }
        .frame(width: 640, height: 340)
        .onChange(of: expanded) { _, value in onExpanded(value) }
        // SwiftUI does not reliably send an exit for a view that disappears
        // under the pointer — which is every ring icon, every time the ring
        // folds — so a stale entry could keep the moon believing it was still
        // being hovered, and the bubble stayed up for good.
        .onChange(of: state.pointerInside) { _, inside in
            guard !inside else { return }
            release?.cancel()
            hovering.removeAll()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                lingering = false
                open = nil
                hoveredAction = nil
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: open)
    }

    /// Notes what the pointer is over. Leaving is given a beat before the ring
    /// folds away, so the gap between the moon and an icon isn't a cliff.
    private func track(_ id: String, _ inside: Bool) {
        release?.cancel()
        if inside {
            state.pointerInside = true
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                _ = hovering.insert(id)
                lingering = true
            }
            return
        }
        hovering.remove(id)
        guard hovering.isEmpty else { return }
        // The ring used to vanish the instant the pointer left the moon, which
        // is the moment you start travelling towards an icon — the gap between
        // the two is dead space that belongs to neither. It holds instead.
        release = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, hovering.isEmpty else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                lingering = false
                open = nil
            }
        }
    }

    // MARK: the moon

    private var moon: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // It never sits still: a slow bob, a little sway, and a tilt
                // that breathes with it, so the thing on your desktop reads as
                // alive rather than as a sticker. Hovering tips it back, as if
                // it were looking up at you.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let idling = !dragging
                    let bob = idling ? sin(t * 1.15) * 5.5 : 0
                    let sway = idling ? sin(t * 0.63 + 1.1) * 3.0 : 0
                    let tilt = idling ? sin(t * 0.78) * 2.4 : 0
                    let breath = idling ? 1 + sin(t * 1.15) * 0.018 : 1.04

                    MoonPetFigure(pose: state.pose, art: state.art)
                        .frame(width: 80, height: 80)
                        .scaleEffect(breath * (expanded ? 1.06 : 1))
                        .rotationEffect(.degrees(tilt + (expanded ? -9 : 0)), anchor: .bottom)
                        .offset(x: sway, y: bob + (expanded ? -6 : 0))
                        // The shadow stays under it and tightens as it rises,
                        // which is what sells the hover.
                        .background(alignment: .bottom) {
                            Ellipse()
                                .fill(.black.opacity(0.16 - bob * 0.008))
                                .frame(width: 46 - bob * 0.9, height: 9)
                                .blur(radius: 6)
                                .offset(y: 8)
                        }
                }
                // A capture landing gives it a nudge, like catching
                // something with a little weight to it.
                .scaleEffect(state.pose == .catching ? 1.08 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: state.pose)
                // Dragging happens on the body only.
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { _ in
                            if !dragging {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                    dragging = true
                                    open = nil
                                }
                            }
                            onDrag(true)
                        }
                        .onEnded { _ in
                            onDrag(false)
                            // A beat before the ring may come back, so letting
                            // go doesn't immediately fan the icons out again.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(320))
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragging = false }
                            }
                        }
                )

                // No count badge. It sat outside the moon's hit target, so it
                // could not be clicked, and a number is a worse answer than a
                // sentence: what was saved, and where it went, goes in the
                // bubble underneath.

                // The capture itself, flying in and being tucked away.
                if state.pose == .catching {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Aurora.tint(state.tint))
                        .frame(width: 26, height: 20)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        .transition(.asymmetric(
                            insertion: .offset(x: 40, y: -34).combined(with: .opacity),
                            removal: .offset(x: -6, y: 14).combined(with: .scale(scale: 0.4)).combined(with: .opacity)))
                        .offset(x: -8, y: 46)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 96, height: 92)
            .contentShape(Circle())
            .onHover { inside in track("moon", inside) }

        }
        // The name hangs off the bottom rather than sitting under it in a
        // stack: laid out in line, it shunted the moon upward every time it
        // appeared, so the moon hopped as the pointer crossed its own ring.
        .overlay(alignment: .bottom) {
            if let line = state.label {
                Text(line)
                    .font(Aurora.ui(11, .medium))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
                    .offset(y: 30)
            }
        }
        .animation(.smooth(duration: 0.25), value: state.label)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: state.filed)
    }

    // MARK: the ring

    private static let ringOrder: [Action] = [.screenshot, .text, .audio, .meeting]

    /// Where the ring lays itself out. Normally an arc over the moon; pushed
    /// against the right of the screen it swings round to the left side, and
    /// the other way at the left edge — otherwise half the icons open off the
    /// edge of the display where they cannot be seen or reached.
    private var arc: (start: Double, end: Double) {
        if !state.roomRight { return (118, 242) }
        if !state.roomLeft { return (62, -62) }
        // Against the top of the screen the icons hang underneath instead, and
        // against the bottom they keep their usual place overhead.
        if !state.roomAbove { return (192, 348) }
        return (168, 12)
    }

    func ringPosition(_ index: Int, of count: Int, radius: CGFloat) -> CGPoint {
        position(index, of: count, radius: radius)
    }

    private func position(_ index: Int, of count: Int, radius: CGFloat) -> CGPoint {
        let span = arc
        let step = count > 1 ? (span.start - span.end) / Double(count - 1) : 0
        let degrees = span.start - step * Double(index)
        let radians = degrees * .pi / 180
        return CGPoint(x: cos(radians) * radius, y: -sin(radians) * radius)
    }

    private func ringButton(_ action: Action, at point: CGPoint) -> some View {
        Button {
            if action.hasChoices {
                open = (open == action) ? nil : action
            } else {
                open = nil
                run(action)
            }
        } label: {
            OverlayIcon(kind: action.icon, tint: open == action ? Aurora.onSolid : Aurora.ink)
                .frame(width: 15, height: 15)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(open == action ? AnyShapeStyle(Aurora.solid) : AnyShapeStyle(.regularMaterial))
                        .overlay(Circle().strokeBorder(Aurora.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
                .contentShape(Circle())
        }
        .buttonStyle(AuroraTapDown())
        .help(action.label)
        // The rail used to say what each icon did; the ring says it too, in
        // the same black capsule, on the side the icon is leaning towards.
        .scaleEffect(hoveredAction == action ? 1.12 : 1)
        .onHover { inside in
            withAnimation(.smooth(duration: 0.15)) { hoveredAction = inside ? action : nil }
            track("ring-\(action)", inside)
        }
        // They fly out of the moon and fall back into it.
        .offset(x: expanded ? point.x : 0, y: expanded ? point.y : 0)
        .opacity(expanded ? 1 : 0)
        .scaleEffect(expanded ? 1 : 0.4)
    }

    /// What the icon under the cursor does, reading outward from its own side
    /// of the ring: capture and text to the left, audio and meeting notes to
    /// the right. Only an edge of the screen overrules that.
    private func label(for action: Action) -> some View {
        let index = Self.ringOrder.firstIndex(of: action) ?? 0
        let point = position(index, of: Self.ringOrder.count, radius: ring)
        var right = point.x >= 0
        if right && !state.roomRight { right = false }
        if !right && !state.roomLeft { right = true }

        // Starts clear of the icons, not just the moon: the ring sits at 74
        // with 16pt buttons on it, so anything closer than 90 reads as being
        // underneath them.
        let column: CGFloat = 220
        let start: CGFloat = 98
        let centre = start + column / 2

        return Text(action.label.uppercased())
            .font(Aurora.mono(9.5)).tracking(1)
            .foregroundStyle(Aurora.onSolid)
            .fixedSize()
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Aurora.solid, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .frame(width: column, alignment: right ? .leading : .trailing)
            .offset(x: right ? centre : -centre, y: point.y)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .allowsHitTesting(false)
    }

    /// The two ways to do the thing you just picked, in words.
    @ViewBuilder
    private func choices(for action: Action) -> some View {
        let index = Self.ringOrder.firstIndex(of: action) ?? 0
        let anchor = position(index, of: Self.ringOrder.count, radius: ring + 44)
        let pairs: [(String, OverlayIcon.Kind, () -> Void)] = action == .screenshot
            ? [("FULL WINDOW", .window, actions.capturePage),
               ("PARTIAL SHOT", .region, actions.captureRegion)]
            : [("YOUR AUDIO", .microphone, { actions.audio(.microphone) }),
               ("SYSTEM AUDIO", .systemAudio, { actions.audio(.systemAudio) })]

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                Button {
                    open = nil
                    pair.2()
                } label: {
                    HStack(spacing: 7) {
                        OverlayIcon(kind: pair.1, tint: Aurora.onSolid)
                            .frame(width: 14, height: 14)
                        Text(pair.0)
                            .font(Aurora.mono(9.5)).tracking(1)
                            .foregroundStyle(Aurora.onSolid)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Aurora.solid, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                    .contentShape(Capsule())
                }
                .buttonStyle(AuroraTapDown())
                .onHover { inside in track("choice-\(pair.0)", inside) }
            }
        }
        .fixedSize()
        .offset(x: anchor.x, y: anchor.y)
        .transition(.scale(scale: 0.8, anchor: .center).combined(with: .opacity))
    }

    private func run(_ action: Action) {
        switch action {
        case .text: actions.captureText()
        case .meeting: actions.meeting()
        case .screenshot: actions.captureRegion()
        case .audio: actions.audio(.systemAudio)
        }
    }
}

/// What the moon is doing, shared between the panel and the app.
@MainActor
final class MoonPetState: ObservableObject {
    @Published var pose: MoonPetView.Pose = .idle
    /// How many captures it has filed this session.
    @Published var filed = 0
    /// A passing line — "Filed to Reading", "Listening…".
    @Published var label: String?
    /// Where things are going right now. Not a standing caption — the moon
    /// mentions it when it changes and then goes quiet.
    @Published var folderName: String? = "Mindspace"
    /// The colour of the capture currently flying in.
    @Published var tint = 0
    /// The four drawings, when they have been supplied.
    @Published var art: MoonPetArt = .load()
    /// Whether there is screen either side of the moon for a label to read
    /// into — recomputed every time it is moved, not frozen at birth.
    @Published var roomLeft = true
    @Published var roomRight = true
    @Published var roomAbove = true
    @Published var roomBelow = true
    /// Set false by the panel when the pointer leaves for real.
    @Published var pointerInside = false

    private var settle: Task<Void, Never>?
    private var quiet: Task<Void, Never>?

    /// A capture landed.
    func caught(_ what: String, tint: Int) {
        self.tint = tint
        filed += 1
        pose = .catching
        say(what)
        settleBack(after: 1.6, to: .holding)
    }

    func listening(_ what: String) {
        pose = .pleased
        say(what)
        settleBack(after: 2.2, to: .holding)
    }

    func startSession(folder: String) {
        folderName = folder
        filed = 0
        pose = .holding
        say("Filing into \(folder)")
        settleBack(after: 2.4, to: .holding)
    }

    /// The note captures are going to has changed. Worth one mention.
    func destinationChanged(to title: String) {
        let previous = folderName
        folderName = title
        guard previous != nil, previous != title else { return }
        say("Saving to \(title)", forSeconds: 5)
    }

    /// Says something, and stops saying it after a while. Long enough to catch
    /// while you are looking at what you just captured; not so long that the
    /// moon sits there holding a sign about something you did ten minutes ago.
    func say(_ text: String, forSeconds seconds: Double = 8) {
        label = text
        quiet?.cancel()
        quiet = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.label = nil
        }
    }

    /// The pose relaxes; what it said stays on the bubble. A message that
    /// vanishes after two seconds is a message you will miss while you are
    /// looking at the thing you just captured.
    private func settleBack(after seconds: Double, to pose: MoonPetView.Pose) {
        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.pose = self.filed > 0 ? pose : .idle
        }
    }
}

/// The moon's four poses, loaded from the app bundle when they are there.
///
/// Drawn ones stand in until then, so the pet works without waiting on art —
/// drop `moon-idle`, `moon-holding`, `moon-catching` and `moon-pleased` (PNG,
/// transparent) into `Sources/NotefyApp/Resources/Pet/` and they take over.
struct MoonPetArt {
    var idle: Image?
    var holding: Image?
    var catching: Image?
    var pleased: Image?

    var isDrawn: Bool { idle == nil }

    static func load() -> MoonPetArt {
        MoonPetArt(
            idle: image("moon-idle"),
            holding: image("moon-holding"),
            catching: image("moon-catching"),
            pleased: image("moon-pleased"))
    }

    private static func image(_ name: String) -> Image? {
        let tries = [("png", "Pet"), ("png", nil), ("heic", "Pet"), ("heic", nil)]
        for (ext, folder) in tries {
            let url = folder.map { Bundle.module.url(forResource: name, withExtension: ext, subdirectory: $0) }
                ?? Bundle.module.url(forResource: name, withExtension: ext)
            if let url, let nsImage = NSImage(contentsOf: url), nsImage.size.height > 0 {
                return Image(nsImage: nsImage)
            }
        }
        return nil
    }
}

/// The moon itself: the supplied drawing when there is one, otherwise a
/// stand-in drawn from the same idea — a soft round body with a face, holding
/// a folder.
struct MoonPetFigure: View {
    let pose: MoonPetView.Pose
    let art: MoonPetArt

    var body: some View {
        if let supplied = drawing {
            supplied
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        } else {
            DrawnMoon(pose: pose)
        }
    }

    private var drawing: Image? {
        switch pose {
        case .idle: return art.idle
        case .holding: return art.holding ?? art.idle
        case .catching: return art.catching ?? art.holding ?? art.idle
        case .pleased: return art.pleased ?? art.holding ?? art.idle
        }
    }
}

/// The stand-in. Deliberately simple: a pearl of a body, two eyes, a mouth
/// that changes with the mood, and a folder in its hands once it has something
/// to hold.
private struct DrawnMoon: View {
    let pose: MoonPetView.Pose

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let eye = side * 0.085

            ZStack {
                // Feet, just visible under the body.
                ForEach([-1.0, 1.0], id: \.self) { side1 in
                    Ellipse()
                        .fill(Color(red: 0.98, green: 0.96, blue: 0.9))
                        .frame(width: side * 0.16, height: side * 0.1)
                        .offset(x: side * 0.22 * side1, y: side * 0.44)
                }

                Circle()
                    .fill(
                        LinearGradient(colors: [
                            Color(red: 1.0, green: 0.99, blue: 0.95),
                            Color(red: 0.93, green: 0.94, blue: 0.99),
                            Color(red: 0.86, green: 0.89, blue: 0.99),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                // Cheeks.
                ForEach([-1.0, 1.0], id: \.self) { side1 in
                    Ellipse()
                        .fill(Color(red: 0.98, green: 0.78, blue: 0.76).opacity(0.75))
                        .frame(width: side * 0.13, height: side * 0.08)
                        .offset(x: side * 0.21 * side1, y: side * 0.06)
                }

                // Eyes.
                ForEach([-1.0, 1.0], id: \.self) { side1 in
                    Capsule()
                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                        .frame(width: eye, height: eye * (pose == .catching ? 1.35 : 1.1))
                        .offset(x: side * 0.12 * side1, y: -side * 0.04)
                }

                mouth(side: side)

                if pose != .idle {
                    // The folder it is holding, with the capture tucked in.
                    RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                        .fill(LinearGradient(colors: [
                            Color(red: 0.96, green: 0.82, blue: 0.45),
                            Color(red: 0.92, green: 0.73, blue: 0.36),
                        ], startPoint: .top, endPoint: .bottom))
                        .frame(width: side * 0.34, height: side * 0.26)
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: side * 0.02, style: .continuous)
                                .fill(Color(red: 0.98, green: 0.88, blue: 0.6))
                                .frame(width: side * 0.16, height: side * 0.05)
                                .offset(x: -side * 0.08, y: -side * 0.03)
                        }
                        .rotationEffect(.degrees(-6))
                        .offset(y: side * 0.24)
                        .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
                }

                if pose == .pleased {
                    Image(systemName: "star.fill")
                        .font(.system(size: side * 0.14))
                        .foregroundStyle(Color(red: 0.98, green: 0.83, blue: 0.4))
                        .offset(x: side * 0.34, y: -side * 0.33)
                }
            }
            .frame(width: side, height: side)
        }
    }

    @ViewBuilder
    private func mouth(side: CGFloat) -> some View {
        switch pose {
        case .idle, .holding:
            // A small closed smile.
            Path { path in
                path.move(to: CGPoint(x: -side * 0.05, y: 0))
                path.addQuadCurve(to: CGPoint(x: side * 0.05, y: 0),
                                  control: CGPoint(x: 0, y: side * 0.05))
            }
            .stroke(Color(red: 0.12, green: 0.13, blue: 0.16), style: .init(lineWidth: side * 0.022, lineCap: .round))
            .frame(width: side * 0.1, height: side * 0.05)
            .offset(y: side * 0.08)
        case .catching, .pleased:
            // An open one.
            Ellipse()
                .fill(Color(red: 0.72, green: 0.24, blue: 0.2))
                .frame(width: side * 0.09, height: side * 0.07)
                .offset(y: side * 0.09)
        }
    }
}
