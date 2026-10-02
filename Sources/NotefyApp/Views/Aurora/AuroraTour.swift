import SwiftUI

/// Where things are, for the first-run walkthrough. Views mark themselves with
/// `.tourAnchor("moon")` and the tour points at wherever they actually are,
/// so moving a control never leaves a tip pointing at empty space.
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourAnchor(_ id: String) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// A handful of tips, one at a time, each pointing at the thing it explains.
/// Shown once, after setup; Settings can show it again.
struct AuroraTour: View {
    struct Step {
        let anchor: String?
        let title: String
        let body: String
        let edge: Edge?
    }

    static let steps: [Step] = [
        Step(anchor: "moon", title: "Tap the moon to speak",
             body: "Ask a question out loud. It listens on your Mac and writes your words as you talk.",
             edge: .trailing),
        Step(anchor: "ring", title: "Each arc is a topic",
             body: "The longer the arc, the more you have kept there. Click one and its notes fan out beside the moon.",
             edge: .trailing),
        Step(anchor: "ask", title: "Ask from any screen",
             body: "Click Ask or press \u{2318}F. Answers come only from what you saved, each with the capture it came from.",
             edge: .top),
        Step(anchor: "toggle", title: "Ring or list",
             body: "Switch to a list when you have many topics. The search filters it as you type.",
             edge: .bottom),
        Step(anchor: "new", title: "Make a topic",
             body: "Start a new topic here. Inside a topic, the same button starts a new note.",
             edge: .top),
        Step(anchor: nil, title: "The moon on your desktop",
             body: "Point at the moon on your desktop to grab the screen, highlight text, record a thought or take meeting notes, without leaving what you are doing.",
             edge: nil)
    ]

    let anchors: [String: Anchor<CGRect>]
    @Binding var step: Int?
    var onFinish: () -> Void

    private static let width: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            if let i = step, Self.steps.indices.contains(i) {
                let s = Self.steps[i]
                let rect = s.anchor.flatMap { anchors[$0] }.map { geo[$0] }
                ZStack {
                    spotlight(rect, in: geo.size)
                    bubble(s, index: i)
                        .modifier(Place(rect: rect, edge: s.edge, size: geo.size, width: Self.width))
                        .id(i)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: step)
            }
        }
    }

    /// The room dims a little and the thing being explained stays lit, ringed.
    private func spotlight(_ rect: CGRect?, in size: CGSize) -> some View {
        let hole = rect?.insetBy(dx: -10, dy: -10)
        return ZStack {
            CutOut(hole: hole)
                .fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture {}
            if let hole {
                RoundedRectangle(cornerRadius: min(hole.height / 2, 24), style: .continuous)
                    .strokeBorder(Aurora.accent, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func bubble(_ s: Step, index i: Int) -> some View {
        let last = i == Self.steps.count - 1
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.title)
                .font(Aurora.ui(15.5, .semibold))
                .foregroundStyle(Aurora.ink)
            Text(s.body)
                .font(Aurora.ui(13.5, .regular))
                .foregroundStyle(Aurora.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text("\(i + 1) of \(Self.steps.count)")
                    .font(Aurora.mono(11))
                    .foregroundStyle(Aurora.ink3)
                Spacer()
                if !last {
                    Button("Skip") { onFinish() }
                        .buttonStyle(.plain)
                        .font(Aurora.ui(13, .medium))
                        .foregroundStyle(Aurora.ink2)
                }
                Button {
                    if last { onFinish() } else { step = i + 1 }
                } label: {
                    Text(last ? "Got it" : "Next")
                        .font(Aurora.ui(13, .semibold))
                        .foregroundStyle(Aurora.onSolid)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Aurora.solid, in: Capsule())
                }
                .buttonStyle(AuroraTapDown())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: Self.width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Aurora.readableGlass))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        }
    }

    /// Puts the bubble beside its target on the given side, kept on screen.
    private struct Place: ViewModifier {
        let rect: CGRect?
        let edge: Edge?
        let size: CGSize
        let width: CGFloat

        func body(content: Content) -> some View {
            let half = width / 2, gap: CGFloat = 22, margin: CGFloat = 16
            func clampX(_ x: CGFloat) -> CGFloat { min(max(x, half + margin), size.width - half - margin) }
            guard let r = rect, let edge else {
                return AnyView(content.position(x: size.width / 2, y: size.height / 2))
            }
            switch edge {
            case .top:
                let bottom = r.minY - gap
                return AnyView(VStack { Spacer(minLength: 0); content }
                    .frame(width: width, height: max(0, bottom))
                    .position(x: clampX(r.midX), y: bottom / 2))
            case .bottom:
                let top = r.maxY + gap
                return AnyView(VStack { content; Spacer(minLength: 0) }
                    .frame(width: width, height: max(0, size.height - top))
                    .position(x: clampX(r.midX), y: top + (size.height - top) / 2))
            case .trailing:
                let x = r.maxX + gap + half
                if x + half + margin <= size.width {
                    return AnyView(content.position(x: x, y: r.midY))
                }
                return AnyView(content.position(x: clampX(r.minX - gap - half), y: r.midY))
            case .leading:
                return AnyView(content.position(x: clampX(r.minX - gap - half), y: r.midY))
            }
        }
    }
}

/// The whole window with one rounded hole, for the spotlight.
private struct CutOut: Shape {
    let hole: CGRect?
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if let hole {
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: min(hole.height / 2, 24), height: min(hole.height / 2, 24)),
                             style: .continuous)
        }
        return p
    }
}
