import AppKit
import Combine
import SwiftUI

enum RecordingNotepadKind {
    case audio
    case meeting
}

@MainActor
final class RecordingNotepadController {
    private var panel: NSPanel?
    private var model: RecordingNotepadModel?
    private var pendingNotes = ""
    private var endAction: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(
        kind: RecordingNotepadKind,
        sourceApp: String,
        microphoneDB: @escaping () -> Float,
        systemDB: @escaping () -> Float,
        onEnd: @escaping () -> Void
    ) {
        close(clearNotes: true)
        let model = RecordingNotepadModel(kind: kind, sourceApp: sourceApp)
        let size = NSSize(width: 330, height: 400)
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(x: frame.minX + 26, y: frame.maxY - size.height - 44)
        let panel = CaptureKeyPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RecordingNotepadView(
            model: model,
            microphoneDB: microphoneDB,
            systemDB: systemDB,
            onEnd: { [weak self] in
                guard let self else { return }
                self.pendingNotes = model.notes
                self.panel?.orderOut(nil)
                self.endAction?()
            }
        ))
        self.model = model
        self.panel = panel
        self.endAction = onEnd
        panel.orderFrontRegardless()
    }

    func insertTimestamp() {
        model?.insertTimestamp()
        panel?.orderFrontRegardless()
    }

    func takeNotesAndClose() -> String {
        let notes = model?.notes ?? pendingNotes
        close(clearNotes: true)
        return notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func close(clearNotes: Bool) {
        panel?.close()
        panel = nil
        model?.stop()
        model = nil
        endAction = nil
        if clearNotes { pendingNotes = "" }
    }
}

@MainActor
private final class RecordingNotepadModel: ObservableObject {
    let kind: RecordingNotepadKind
    let sourceApp: String
    @Published var notes = ""
    @Published var elapsed: TimeInterval = 0
    private var timer: Timer?

    init(kind: RecordingNotepadKind, sourceApp: String) {
        self.kind = kind
        self.sourceApp = sourceApp
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    func insertTimestamp() {
        let stamp = String(format: "⏸ %d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
        if !notes.isEmpty { notes += "\n" }
        notes += "\(stamp)\n"
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private struct RecordingNotepadView: View {
    @ObservedObject var model: RecordingNotepadModel
    let microphoneDB: () -> Float
    let systemDB: () -> Float
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topLeading) {
                RuledNotepadLines()
                TextEditor(text: Binding(
                    get: { model.notes },
                    set: { model.notes = String($0.prefix(5000)) }
                ))
                .font(NotefyFont.hand)
                .foregroundStyle(NotefyTheme.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            footer
        }
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            OverlayIcon(kind: model.kind == .audio ? .audio : .meeting)
                .frame(width: 18, height: 18)
            Text(model.kind == .audio ? "COMPUTER AUDIO" : "MEETING NOTES")
                .font(NotefyFont.label).tracking(1.2)
                .foregroundStyle(NotefyTheme.ink)
            Spacer()
            Text("\(model.sourceApp) · \(clock)")
                .font(NotefyFont.caption)
                .foregroundStyle(NotefyTheme.inkFaint)
                .lineLimit(1)
            NotedLogo().frame(width: 22, height: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if model.kind == .meeting {
                    meter("YOU", microphoneDB(), NotefyTheme.marginRose)
                    meter("OTHERS", systemDB(), NotefyTheme.pebbleOlive)
                } else {
                    meter("COMPUTER AUDIO", systemDB(), NotefyTheme.pebbleOlive)
                }
            }
            HStack(spacing: 8) {
                Circle().fill(NotefyTheme.marginRose).frame(width: 7, height: 7)
                Text(model.kind == .meeting ? "CAPTURING LOCALLY · PRIVATE" : "RECORDING MAC AUDIO · PRIVATE")
                    .font(NotefyFont.caption).tracking(0.7)
                    .foregroundStyle(NotefyTheme.inkFaint)
                Spacer()
                if model.kind == .audio {
                    Button("ADD TIMESTAMP", action: model.insertTimestamp)
                        .buttonStyle(.plain).font(NotefyFont.caption)
                }
            }
            Button(action: onEnd) {
                Label("STOP & SAVE NOTE", systemImage: "stop.fill")
                    .font(NotefyFont.label).tracking(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(NotefyTheme.ink, in: Capsule())
                    .foregroundStyle(NotefyTheme.sand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording and save note")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private func meter(_ label: String, _ db: Float, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).font(NotefyFont.caption).foregroundStyle(NotefyTheme.inkSoft)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotefyTheme.ink.opacity(0.08))
                    Capsule().fill(color).frame(width: proxy.size.width * normalized(db))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var clock: String {
        String(format: "%02d:%02d:%02d", Int(model.elapsed) / 3600, (Int(model.elapsed) / 60) % 60, Int(model.elapsed) % 60)
    }

    private func normalized(_ db: Float) -> CGFloat {
        CGFloat(max(0, min(1, (db + 60) / 60)))
    }
}

private struct RuledNotepadLines: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: CGFloat(26), through: size.height, by: 27) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(NotefyTheme.inkSoft.opacity(0.16)), lineWidth: 1)
            }
        }
        .background(NotefyTheme.cardPaper)
        .allowsHitTesting(false)
    }
}
