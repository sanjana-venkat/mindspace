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

    @State private var dragging: UUID?
    @State private var order: [ExplorationStep] = []
    @FocusState private var keyboard: Bool
    private let columns = 3

    /// What the grid draws: the live local order while a drag is in flight, the
    /// note's own order otherwise. Rewriting the published array on every hover
    /// is what made this crawl — each pass rewrote the note and scheduled a save.
    private var items: [ExplorationStep] { order.isEmpty ? steps : order }

    struct Entry { let index: Int; let step: ExplorationStep }

    /// Columns are fixed; heights are not. Tiles go across before they go
    /// down — 01 02 03 on the top row, 04 05 06 under it — so the numbering
    /// always matches what you're looking at. Packing by shortest column
    /// balanced the layout better but scrambled the order, and the order is
    /// the thing people are actually reading.
    private var masonry: [[Entry]] {
        var cols: [[Entry]] = Array(repeating: [], count: columns)
        for (i, step) in items.enumerated() {
            cols[i % columns].append(Entry(index: i, step: step))
        }
        return cols
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(spacing: 18) {
                            ForEach(masonry[column], id: \.step.id) { entry in
                                tile(entry.index, entry.step)
                                    // A tile keeps its capture identity while moving, but its
                                    // ordinal is positional. Include the position in the view
                                    // identity so SwiftUI cannot retain the old badge label.
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
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, 34).padding(.top, 30).padding(.bottom, 40)
            }
            .scrollIndicators(.never)
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
        return Button {
            if isActive { open(i) } else { active = i; keyboard = true }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                AuroraCaptureView(step: step, index: i, textLimit: 14,
                                  imageHeight: step.screenshotPath != nil ? 170 : nil)
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(URL(string: step.url ?? "")?.host ?? step.appName)
                        .font(Aurora.mono(9.5)).foregroundStyle(Aurora.ink3).lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Aurora.surface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isActive ? Aurora.focusRing : Aurora.line, lineWidth: isActive ? 2 : 1))
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
