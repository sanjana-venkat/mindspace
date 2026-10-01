import SwiftUI
import AppKit
import NotefyCore

/// One capture, full size, in a dark room.
///
/// A tile in the grid is a glance; this is for reading the screenshot. The
/// arrows, the arrow keys and a two-finger swipe all step through the note's
/// captures in the same order as the grid, so you can leaf through them like
/// photos without going back to the tiles in between.
struct AuroraCaptureViewer: View {
    let steps: [ExplorationStep]
    @Binding var index: Int?
    var thought: (UUID) -> String

    @FocusState private var focused: Bool
    @State private var swipe: Any?
    @State private var swipeAccumulated: CGFloat = 0
    @State private var swipeSpent = false
    @State private var direction: Edge = .trailing

    private var current: Int { min(max(index ?? 0, 0), max(steps.count - 1, 0)) }
    private var step: ExplorationStep? { steps.indices.contains(current) ? steps[current] : nil }
    private var canGoBack: Bool { current > 0 }
    private var canGoOn: Bool { current < steps.count - 1 }

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.035, blue: 0.045).opacity(0.94)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            if let step {
                VStack(spacing: 18) {
                    header(step)
                    picture(step)
                        .id(step.id)
                        .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                                removal: .opacity))
                    caption(step)
                }
                .padding(.horizontal, 110)
                .padding(.vertical, 36)
            }

            HStack {
                arrow("chevron.left", enabled: canGoBack) { go(-1) }
                Spacer()
                arrow("chevron.right", enabled: canGoOn) { go(1) }
            }
            .padding(.horizontal, 28)
        }
        .animation(.smooth(duration: 0.26), value: current)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { go(-1); return .handled }
        .onKeyPress(.rightArrow) { go(1); return .handled }
        .onAppear {
            focused = true
            installSwipe()
        }
        .onDisappear { removeSwipe() }
    }

    // MARK: pieces

    private func header(_ step: ExplorationStep) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", current + 1) + "  /  " + String(format: "%02d", steps.count))
                .font(Aurora.mono(12)).tracking(1)
                .foregroundStyle(.white.opacity(0.85))
            Text(source(step))
                .font(Aurora.mono(11.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer()
            Text(step.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(Aurora.mono(11))
                .foregroundStyle(.white.opacity(0.45))
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(AuroraTapDown())
            .help("Close (Esc)")
        }
    }

    @ViewBuilder
    private func picture(_ step: ExplorationStep) -> some View {
        if let path = step.screenshotPath, let image = ScreenshotStore.image(path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Clicking the picture itself does nothing, so it never closes
                // the viewer out from under you.
                .contentShape(Rectangle())
                .onTapGesture {}
        } else {
            // A text capture is shown as what it is: the words.
            ScrollView {
                Text(step.selectedText ?? step.pageText ?? step.windowTitle)
                    .font(Aurora.serif(22))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {}
        }
    }

    @ViewBuilder
    private func caption(_ step: ExplorationStep) -> some View {
        let note = thought(step.id)
        if !note.isEmpty {
            Text(note)
                .font(Aurora.serif(18))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: 760)
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.25))
                .frame(width: 48, height: 48)
                .background(.white.opacity(enabled ? 0.1 : 0.04), in: Circle())
        }
        .buttonStyle(AuroraTapDown())
        .disabled(!enabled)
    }

    private func source(_ step: ExplorationStep) -> String {
        if let host = URL(string: step.url ?? "")?.host { return host }
        return step.appName
    }

    // MARK: moving

    private func go(_ delta: Int) {
        let next = current + delta
        guard steps.indices.contains(next) else { return }
        direction = delta > 0 ? .trailing : .leading
        index = next
    }

    private func close() { index = nil }

    /// Two fingers sideways on a trackpad, one capture per swipe. The swipe is
    /// spent once it moves the viewer, so a long flick does not run through
    /// the whole note, and momentum after the fingers lift is ignored.
    private func installSwipe() {
        removeSwipe()
        swipe = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard index != nil, event.hasPreciseScrollingDeltas else { return event }
            // Up and down belong to whatever is under the pointer, a long text
            // capture for one; only sideways movement is a swipe.
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            if event.momentumPhase != [] { return nil }
            if event.phase == .began {
                swipeAccumulated = 0
                swipeSpent = false
            }
            swipeAccumulated += event.scrollingDeltaX
            if !swipeSpent, abs(swipeAccumulated) > 70 {
                swipeSpent = true
                // Natural scrolling: fingers moving left bring the next one in.
                go(swipeAccumulated < 0 ? 1 : -1)
            }
            if event.phase == .ended || event.phase == .cancelled {
                swipeAccumulated = 0
                swipeSpent = false
            }
            return nil
        }
    }

    private func removeSwipe() {
        if let swipe { NSEvent.removeMonitor(swipe) }
        swipe = nil
    }
}
