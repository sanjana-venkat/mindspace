import AppKit
import Combine
import SwiftUI

enum RecordingNotepadKind {
    /// What the Mac is playing.
    case audio
    /// What you are saying, and nothing else.
    case voice
    /// Both sides of a conversation.
    case meeting
}

@MainActor
final class RecordingNotepadController {
    private var panel: NSPanel?
    private var model: RecordingNotepadModel?
    private var pendingNotes = ""
    private var endAction: (() -> Void)?
    private weak var transcript: LiveTranscriptEngine?
    private var discardAction: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(
        kind: RecordingNotepadKind,
        sourceApp: String,
        microphoneDB: @escaping () -> Float,
        systemDB: @escaping () -> Float,
        onEnd: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        close(clearNotes: true)
        FocusKeeper.remember()
        let model = RecordingNotepadModel(kind: kind, sourceApp: sourceApp)
        let size = NSSize(width: 452, height: 700)
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
        if let transcript { model.transcript = transcript }
        panel.contentView = NSHostingView(rootView: RecordingNotepadView(
            model: model,
            microphoneDB: microphoneDB,
            systemDB: systemDB,
            onEnd: { [weak self] in
                guard let self else { return }
                self.pendingNotes = model.notes
                self.panel?.orderOut(nil)
                self.handBackFocus()
                self.endAction?()
            },
            onDiscard: { [weak self] in
                guard let self else { return }
                // Nothing is kept: no notes carried out, no note written.
                self.pendingNotes = ""
                self.panel?.orderOut(nil)
                self.handBackFocus()
                self.discardAction?()
            }
        ))
        self.model = model
        self.panel = panel
        self.endAction = onEnd
        self.discardAction = onDiscard
        panel.orderFrontRegardless()
    }

    /// Returns to whatever was in front before the recording began.
    private func handBackFocus() {
        FocusKeeper.restore()
    }

    func insertTimestamp() {
        model?.insertTimestamp()
        panel?.orderFrontRegardless()
    }

    /// The running transcript is owned by AppState — the panel only watches it.
    func attach(transcript: LiveTranscriptEngine) {
        self.transcript = transcript
        model?.transcript = transcript
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
    /// Set once the recording starts; the panel reads its lines directly.
    @Published var transcript: LiveTranscriptEngine?
    private var timer: Timer?

    init(kind: RecordingNotepadKind, sourceApp: String) {
        self.kind = kind
        self.sourceApp = sourceApp
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    func insertTimestamp() {
        let stamp = String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
        if !notes.isEmpty, !notes.hasSuffix("\n") { notes += "\n" }
        notes += "\(stamp) "
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
    let onDiscard: () -> Void
    @State private var confirmingDiscard = false
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
                .opacity(0.12)

            VStack(alignment: .leading, spacing: 16) {
                header
                recordingSignal
                liveTranscript
                noteField
                footer
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
        // Asking a question about the recording dims the whole card, not the
        // part of it the button happens to live in.
        .overlay {
            if confirmingDiscard {
                AuroraConfirm(
                    title: "Throw this recording away?",
                    message: "The audio and anything written beside it go. Nothing is saved.",
                    confirmLabel: "Yes, discard",
                    onConfirm: {
                        confirmingDiscard = false
                        onDiscard()
                    },
                    onCancel: { confirmingDiscard = false })
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.20), radius: 26, y: 12)
        // A 26pt shadow needs more than 12pt of room, or the panel's edge cuts
        // it off square down both sides.
        .padding(26)
        .background(AuroraWindowGlass())
        .preferredColorScheme(appearance.scheme)
    }

    private var header: some View {
        HStack(spacing: 10) {
            OverlayIcon(kind: kindIcon)
                .frame(width: 17, height: 17)
            Text(kindTitle)
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
                switch model.kind {
                case .meeting:
                    meter("YOU", microphoneDB())
                    meter("OTHERS", systemDB())
                case .voice:
                    meter("YOU", microphoneDB())
                case .audio:
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
        AuroraThoughtEditor(
            text: Binding(get: { model.notes }, set: { model.notes = $0 }),
            placeholder: "Add a thought, or mark a moment with a timestamp…",
            font: .auroraSerif(16),
            textColor: NSColor(Aurora.ink),
            limit: 5000,
            inset: CGSize(width: 14, height: 13))
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        .background(Aurora.surface2.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // Every recording can be marked, meetings included — that was the
            // one mode where the button was missing.
            // Marking a moment is a peer of stopping, not a footnote to it:
            // same height, same weight, no icon competing with the word.
            Button(action: model.insertTimestamp) {
                Text(stampLabel)
                    .font(Aurora.mono(10.5)).tracking(1.1)
                    .foregroundStyle(Aurora.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Aurora.surface2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(AuroraPressStyle())
            .help("Write the moment you're at into your notes")

            Button(action: onEnd) {
                Label("STOP & SAVE", systemImage: "stop.fill")
                    .font(Aurora.mono(10.5)).tracking(1.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Aurora.ink, in: Capsule())
                    .foregroundStyle(Aurora.ground)
                    .contentShape(Capsule())
            }
            .buttonStyle(AuroraPressStyle())
            .accessibilityLabel("Stop recording and save note")

            // Not every recording is worth keeping, and the only way out used
            // to be to save one and delete it afterwards.
            Button { confirmingDiscard = true } label: {
                Text("DISCARD")
                    .font(Aurora.mono(10.5)).tracking(1.1)
                    .foregroundStyle(Aurora.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(Capsule().strokeBorder(Aurora.danger.opacity(0.5), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(AuroraPressStyle())
            .accessibilityLabel("Discard this recording")
        }
    }

    /// What it is hearing, as it hears it. Rough on purpose — the note's real
    /// transcript is made from the full recording once you stop.
    @ViewBuilder
    private var liveTranscript: some View {
        if let engine = model.transcript {
            LiveTranscriptPanel(engine: engine, meeting: model.kind == .meeting)
        }
    }

    private var kindIcon: OverlayIcon.Kind {
        switch model.kind {
        case .audio: return .systemAudio
        case .voice: return .audio
        case .meeting: return .meeting
        }
    }

    private var kindTitle: String {
        switch model.kind {
        case .audio: return "COMPUTER AUDIO"
        case .voice: return "YOUR AUDIO"
        case .meeting: return "MEETING NOTES"
        }
    }

    private var stampLabel: String { "TIMESTAMP" }

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
        let db: Float
        switch model.kind {
        case .meeting: db = max(microphoneDB(), systemDB())
        case .voice: db = microphoneDB()
        case .audio: db = systemDB()
        }
        return max(2, Int(normalized(db) * 32))
    }

    private func signalHeight(_ index: Int) -> CGFloat {
        let rhythm: [CGFloat] = [0.34, 0.62, 0.88, 0.48, 1, 0.72, 0.42]
        return 7 + rhythm[index % rhythm.count] * 23
    }

    private func normalized(_ db: Float) -> CGFloat {
        CGFloat(max(0, min(1, (db + 60) / 60)))
    }
}

/// The transcript has to observe the engine itself — watching the notepad's
/// model would never see a new line arrive.
private struct LiveTranscriptPanel: View {
    @ObservedObject var engine: LiveTranscriptEngine
    let meeting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("LIVE TRANSCRIPT")
                    .font(Aurora.mono(9.5)).tracking(1.3)
                    .foregroundStyle(Aurora.ink2)
                Spacer()
                Text(status)
                    .font(Aurora.mono(9)).tracking(0.8)
                    .foregroundStyle(Aurora.ink3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(engine.lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(line.clock)
                                    .font(Aurora.mono(9.5))
                                    .foregroundStyle(Aurora.ink3)
                                    .frame(width: 32, alignment: .leading)
                                if meeting {
                                    Text(line.voice.label)
                                        .font(Aurora.mono(8.5)).tracking(0.8)
                                        .foregroundStyle(line.voice == .you ? Aurora.accent : Aurora.ink3)
                                        .frame(width: 40, alignment: .leading)
                                }
                                Text(line.text)
                                    .font(Aurora.serif(13.5))
                                    .foregroundStyle(Aurora.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .id(line.id)
                        }
                        // What is being said right now, still being decoded.
                        // It replaces itself as the words arrive and turns
                        // into a line above when the sentence ends.
                        ForEach(ghosts, id: \.0) { voice, text in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                // No clock yet — this sentence hasn't finished
                                // being said. It reads from the left edge
                                // rather than sitting in an empty column.
                                if meeting {
                                    Text(voice.label)
                                        .font(Aurora.mono(8.5)).tracking(0.8)
                                        .foregroundStyle(voice == .you ? Aurora.accent.opacity(0.6) : Aurora.ink3.opacity(0.7))
                                        .frame(width: 40, alignment: .leading)
                                }
                                Text(text)
                                    .font(Aurora.serif(13.5))
                                    .foregroundStyle(Aurora.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .id("ghost-\(voice.label)")
                        }

                        if engine.lines.isEmpty && ghosts.isEmpty {
                            Text(emptyLine)
                                .font(Aurora.ui(11.5, .medium))
                                .foregroundStyle(Aurora.ink3)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onChange(of: engine.lines.count) { _, _ in
                    if let last = engine.lines.last {
                        withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: ghosts.count) { _, _ in
                    if let last = ghosts.last {
                        withAnimation(.smooth(duration: 0.2)) {
                            proxy.scrollTo("ghost-\(last.0.label)", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(height: 150)
        .background(Aurora.surface2.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
    }

    /// The half-spoken sentences, in a stable order so they don't jump about.
    private var ghosts: [(LiveTranscriptLine.Voice, String)] {
        [LiveTranscriptLine.Voice.you, .others, .mac].compactMap { voice in
            guard let text = engine.pending[voice],
                  !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (voice, text)
        }
    }

    private var status: String {
        switch engine.status {
        case .off: return "STOPPED"
        case .preparing(let note): return note
        case .listening: return "ON-DEVICE"
        case .unavailable: return "UNAVAILABLE"
        }
    }

    private var emptyLine: String {
        switch engine.status {
        case .unavailable:
            // The provider's own words here were a model-hub stack trace.
            return "The on-device speech model couldn't start, so there's no live transcript. The full one is still made when you stop."
        case .preparing(let note) where note.hasPrefix("DOWNLOADING"):
            // First run pulls the speech model down. Say so, or the panel
            // looks broken for as long as the download takes.
            return "Fetching the speech model — \(note.lowercased()). It only happens once."
        case .preparing: return "Loading the on-device model…"
        default: return "Listening… the first line lands a few seconds in."
        }
    }
}
