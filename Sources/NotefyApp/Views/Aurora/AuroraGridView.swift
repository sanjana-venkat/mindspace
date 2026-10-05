import SwiftUI
import NotefyCore
import UniformTypeIdentifiers

/// Every capture-and-thought pair as a tile on a 3 × N grid.
/// Drag to rearrange, or hold shift and use the arrow keys.
struct AuroraGrid: View {
    let steps: [ExplorationStep]
    @Binding var active: Int
    var thought: (UUID) -> Binding<String>
    var dimmedFor: UUID?
    var onRightClick: (ExplorationStep, CGPoint) -> Void
    /// Called once, when the drag ends — not on every hover.
    var commit: ([ExplorationStep]) -> Void
    var open: (Int) -> Void
    /// Double-click: the capture full size, over a dark room.
    var preview: (Int) -> Void = { _ in }
    var zoom: Double = 1
    /// A pinch or zoom step in flight: the grid is drawn scaled by this, not
    /// laid out again, until the gesture ends.
    var liveScale: CGFloat = 1
    var liveAnchor: UnitPoint = .top
    @Binding var selection: Set<UUID>

    @State private var dragging: UUID?
    @State private var order: [ExplorationStep] = []
    @FocusState private var keyboard: Bool
    /// How much room the grid has, measured rather than assumed — the column
    /// count is derived from it.
    @State private var available: CGFloat = 1200

    /// A tile at 100%.
    private static let baseTile: CGFloat = 330
    private static let gutter: CGFloat = 18

    /// Zooming changes the size of a tile, smoothly; the number of columns is
    /// then whatever fits. Tiles keep that width instead of stretching to fill
    /// the window, which is what threw the first and last column out to the
    /// edges when the count stepped down.
    private var tileWidth: CGFloat { Self.baseTile * zoom }
    private var columns: Int {
        let room = max(Self.baseTile, available)
        return max(1, min(8, Int(floor((room + Self.gutter) / (tileWidth + Self.gutter)))))
    }

    /// What the grid draws: the live local order while a drag is in flight, the
    /// note's own order otherwise. Rewriting the published array on every hover
    /// is what made this crawl — each pass rewrote the note and scheduled a save.
    private var items: [ExplorationStep] { order.isEmpty ? steps : order }

    struct Entry { let index: Int; let step: ExplorationStep }

    /// One tile in a row: one column wide, or two for a wide screenshot.
    private struct Slot: Identifiable {
        let entry: Entry
        let span: Int
        var id: UUID { entry.step.id }
    }

    /// Wider than this and a screenshot would be a thin strip in one column, so
    /// it takes two. Never more: a tile that crosses the whole grid stops it
    /// reading as a grid.
    private static let wideAspect: CGFloat = 1.9

    /// Every picture box is this shape, so every tile in a row is the same
    /// height and the rows line up. A screenshot fills it from the top and is
    /// cropped past it, since the top of a page is the part that says what it
    /// is.
    private var boxHeight: CGFloat { (tileWidth * 0.625).rounded() }

    /// The caption under the picture, fixed, for the same reason.
    private static let captionHeight: CGFloat = 96

    private var rowWidth: CGFloat {
        CGFloat(columns) * tileWidth + CGFloat(max(0, columns - 1)) * Self.gutter
    }

    private func width(span: Int) -> CGFloat {
        CGFloat(span) * tileWidth + CGFloat(span - 1) * Self.gutter
    }

    private func isWide(_ step: ExplorationStep) -> Bool {
        guard columns >= 2, let path = step.screenshotPath,
              let a = ScreenshotStore.aspect(path) else { return false }
        return a >= Self.wideAspect
    }

    /// Rows, filled left to right in the note's own order. A wide screenshot
    /// that will not fit in what is left of a row starts the next one.
    private var rows: [[Slot]] {
        var out: [[Slot]] = []
        var row: [Slot] = []
        var used = 0
        for (i, step) in items.enumerated() {
            let span = isWide(step) ? 2 : 1
            if used + span > columns, !row.isEmpty {
                out.append(row); row = []; used = 0
            }
            row.append(Slot(entry: Entry(index: i, step: step), span: span))
            used += span
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    @ViewBuilder
    private func placed(_ entry: Entry, width: CGFloat) -> some View {
        tile(entry.index, entry.step)
            .frame(width: width)
            // A tile keeps its capture identity while moving, but its ordinal
            // is positional. Include the position in the view identity so
            // SwiftUI cannot retain the old badge label.
            .id("\(entry.step.id.uuidString)-\(entry.index)")
            .onDrag {
                dragging = entry.step.id
                return NSItemProvider(object: entry.step.id.uuidString as NSString)
            }
            .onDrop(of: [UTType.text],
                    delegate: AuroraTileDrop(target: entry.step.id,
                                             dragging: $dragging,
                                             reorder: reorder,
                                             finish: { commit(items) }))
    }


    /// The offscreen renderer cannot draw inside a ScrollView, so while it
    /// runs the tiles are laid out flat. Always false in a real window.
    static var drawsUnscrolled = false

    private var tiles: some View {
        VStack(alignment: .leading, spacing: Self.gutter) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Self.gutter) {
                    ForEach(row) { slot in
                        placed(slot.entry, width: width(span: slot.span))
                    }
                }
            }
        }
        .frame(width: rowWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 34).padding(.top, 30).padding(.bottom, 40)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if Self.drawsUnscrolled { tiles } else { ScrollView { tiles } }
            }
            .scrollIndicators(.never)
            .scaleEffect(liveScale, anchor: liveAnchor)
            .clipped()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { available = geo.size.width - 68 }
                        .onChange(of: geo.size.width) { _, width in available = width - 68 }
                }
            }
            .focusable()
            .focused($keyboard)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press) }
            .onAppear { keyboard = true; order = steps }
            .onChange(of: steps.map(\.id)) { _, _ in if dragging == nil { order = steps } }
            .animation(.snappy(duration: 0.2), value: items.map(\.id))

            footer
        }
    }

    private func tile(_ i: Int, _ step: ExplorationStep) -> some View {
        let isActive = i == active
        let note = thought(step.id).wrappedValue
        let picked = selection.contains(step.id)
        return Button {
            // The second click of a double-click opens the viewer. The first
            // has already selected the tile, which is what a double-click on
            // a Mac does anyway.
            if NSApp.currentEvent?.clickCount == 2, selection.isEmpty {
                preview(i)
                return
            }
            // While a selection is running, a click adds to it rather than
            // opening — otherwise you'd have to right-click every capture.
            if !selection.isEmpty {
                if picked { selection.remove(step.id) } else { selection.insert(step.id) }
            } else if isActive {
                open(i)
            } else {
                active = i
                keyboard = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Text captures get the same box and only as many lines as fit
                // it: unbounded, their wash grew to whatever height was around.
                AuroraCaptureView(step: step, index: i,
                                  textLimit: max(2, Int((boxHeight - 32) / 23)),
                                  imageHeight: boxHeight)
                VStack(alignment: .leading, spacing: 8) {
                    if note.isEmpty {
                        Text("No thought yet")
                            .font(Aurora.ui(11.5, .medium)).foregroundStyle(Aurora.ink3)
                    } else {
                        Text(note)
                            .font(Aurora.serif(14))
                            .foregroundStyle(Aurora.ink)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    Text(URL(string: step.url ?? "")?.host ?? step.appName)
                        .font(Aurora.mono(9.5)).foregroundStyle(Aurora.ink3).lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: Self.captionHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Aurora.surface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(picked ? Aurora.accent : (isActive ? Aurora.focusRing : Aurora.line),
                              lineWidth: (picked || isActive) ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if !selection.isEmpty {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(picked ? Aurora.accent : Aurora.ink3)
                        .background(Circle().fill(Aurora.surface).padding(2))
                        .padding(10)
                }
            }
            .scaleEffect(isActive ? 1.015 : 1)
            .opacity(dragging == step.id ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .blur(radius: dimmed(step) ? 4 : 0)
        .opacity(dimmed(step) ? 0.45 : 1)
        .auroraRightClick(in: "auroraNote") { onRightClick(step, $0) }
        .animation(.smooth(duration: 0.22), value: isActive)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            key("drag", "rearrange")
            key("⇧ + ← →", "move this tile")
            key("← → ↑ ↓", "select")
            key("↩", "open in Panels")
            key("double-click", "view full size")
            Spacer()
        }
        .padding(.horizontal, 34).padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Aurora.line).frame(height: 1) }
    }

    private func key(_ k: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Text(k)
                .font(Aurora.mono(10)).foregroundStyle(Aurora.ink2)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Aurora.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
            Text(label).font(Aurora.ui(11, .medium)).foregroundStyle(Aurora.ink3)
        }
    }

    private func dimmed(_ step: ExplorationStep) -> Bool {
        guard let dimmedFor else { return false }
        return step.id != dimmedFor
    }

    private func reorder(_ dragged: UUID, _ target: UUID) {
        var current = items
        guard let from = current.firstIndex(where: { $0.id == dragged }),
              let to = current.firstIndex(where: { $0.id == target }),
              from != to else { return }
        let step = current.remove(at: from)
        current.insert(step, at: to)
        order = current
        active = to
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        var delta = 0
        switch press.key {
        case .leftArrow: delta = -1
        case .rightArrow: delta = 1
        case .upArrow: delta = -columns
        case .downArrow: delta = columns
        case .return: open(active); return .handled
        default: return .ignored
        }
        let target = max(0, min(items.count - 1, active + delta))
        if press.modifiers.contains(.shift) {
            var current = items
            let step = current.remove(at: min(active, current.count - 1))
            current.insert(step, at: target)
            withAnimation(.snappy(duration: 0.2)) { order = current; active = target }
            commit(current)
        } else {
            withAnimation(.smooth(duration: 0.18)) { active = target }
        }
        return .handled
    }
}

private struct AuroraTileDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let reorder: (UUID, UUID) -> Void
    let finish: () -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        reorder(dragging, target)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        finish()
        return true
    }
}
