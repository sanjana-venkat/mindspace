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
        let size = NSSize(width: 420, height: 480)
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
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AuroraAppearance.storageKey) private var appearanceRaw = AuroraAppearance.system.rawValue

    private var appearance: AuroraAppearance {
        AuroraAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        ZStack {
            AuroraVisualEffect()
            Aurora.surface.opacity(scheme == .dark ? 0.92 : 0.88)
            AuroraGrain.tile
                .resizable(resizingMode: .tile)
                .blendMode(scheme == .dark ? .screen : .multiply)
                .opacity(scheme == .dark ? 0.07 : 0.12)

            VStack(alignment: .leading, spacing: 16) {
                header
                recordingSignal
                noteField
                footer
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.20), radius: 34, y: 16)
        .padding(12)
        .background(AuroraWindowGlass())
        .preferredColorScheme(appearance.scheme)
    }

    private var header: some View {
        HStack(spacing: 10) {
            OverlayIcon(kind: model.kind == .audio ? .audio : .meeting)
                .frame(width: 17, height: 17)
            Text(model.kind == .audio ? "COMPUTER AUDIO" : "MEETING NOTES")
                .font(Aurora.mono(10.5)).tracking(1.5)
                .foregroundStyle(Aurora.ink)
            Spacer()
            Text(model.sourceApp)
                .font(Aurora.ui(11.5, .medium))
                .foregroundStyle(Aurora.ink2)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Aurora.surface2, in: Capsule())
        }
        .contentShape(Rectangle())
    }

    private var recordingSignal: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(shortClock)
                    .font(Aurora.display(42))
                    .foregroundStyle(Aurora.ink)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Aurora.accent).frame(width: 7, height: 7)
                    Text("RECORDING · PRIVATE")
                        .font(Aurora.mono(9.5)).tracking(1.1)
                        .foregroundStyle(Aurora.ink2)
                }
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<32, id: \.self) { index in
                    Capsule()
                        .fill(index < activeBars ? Aurora.accent : Aurora.line)
                        .frame(height: signalHeight(index))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)

            HStack(spacing: 12) {
                if model.kind == .meeting {
                    meter("YOU", microphoneDB())
                    meter("OTHERS", systemDB())
                } else {
                    meter("MAC AUDIO", systemDB())
                }
            }
        }
        .padding(16)
        .background(Aurora.accentSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Aurora.accent.opacity(0.35), lineWidth: 1))
    }

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if model.notes.isEmpty {
                Text("Add a thought, or mark a moment with a timestamp…")
                    .font(Aurora.serif(16))
                    .foregroundStyle(Aurora.ink3)
                    .padding(.horizontal, 15).padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: Binding(
                get: { model.notes },
                set: { model.notes = String($0.prefix(5000)) }
            ))
            .font(Aurora.serif(16))
            .foregroundStyle(Aurora.ink)
            .scrollContentBackground(.hidden)
            .padding(9)
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        .background(Aurora.surface2.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.kind == .audio {
                Button(action: model.insertTimestamp) {
                    Label("TIMESTAMP", systemImage: "bookmark")
                        .font(Aurora.mono(9.5)).tracking(1)
                        .foregroundStyle(Aurora.ink2)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Aurora.surface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                }
                .buttonStyle(AuroraPressStyle())
            }

            Button(action: onEnd) {
                Label("STOP & SAVE", systemImage: "stop.fill")
                    .font(Aurora.mono(10.5)).tracking(1.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Aurora.ink, in: Capsule())
                    .foregroundStyle(Aurora.ground)
            }
            .buttonStyle(AuroraPressStyle())
            .accessibilityLabel("Stop recording and save note")
        }
    }

    private func meter(_ label: String, _ db: Float) -> some View {
        HStack(spacing: 7) {
            Text(label).font(Aurora.mono(8.5)).tracking(0.8).foregroundStyle(Aurora.ink2)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Aurora.line)
                    Capsule().fill(Aurora.accent).frame(width: proxy.size.width * normalized(db))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var shortClock: String {
        String(format: "%d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60)
    }

    private var activeBars: Int {
        max(2, Int(normalized(model.kind == .meeting ? max(microphoneDB(), systemDB()) : systemDB()) * 32))
    }

    private func signalHeight(_ index: Int) -> CGFloat {
        let rhythm: [CGFloat] = [0.34, 0.62, 0.88, 0.48, 1, 0.72, 0.42]
        return 7 + rhythm[index % rhythm.count] * 23
    }

    private func normalized(_ db: Float) -> CGFloat {
        CGFloat(max(0, min(1, (db + 60) / 60)))
    }
}
