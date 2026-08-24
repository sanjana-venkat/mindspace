import AppKit
import AVFoundation
import NotefyCore
import SwiftUI

@MainActor
final class CaptureReviewController {
    private var panel: NSPanel?

    func present(
        step: ExplorationStep,
        appState: AppState,
        destinationTitle: String,
        destinations: [NoteDestination],
        onSelectDestination: @escaping (NoteDestination) -> Void,
        onCreateNote: @escaping () -> Void,
        onTranscribeVoice: @escaping (URL) async -> Result<String, Error>,
        onKeep: @escaping (String, URL?) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        panel?.close()

        let isTextLift = step.screenshotPath == nil && step.selectedText != nil
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = screenFrame.size
        let origin = screenFrame.origin

        let panel = CaptureKeyPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let close: () -> Void = { [weak self, weak panel] in
            panel?.animator().alphaValue = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                panel?.close()
                if self?.panel === panel { self?.panel = nil }
            }
        }
        panel.contentView = NSHostingView(rootView: CaptureReviewView(
            step: step,
            isTextLift: isTextLift,
            destinationTitle: destinationTitle,
            destinations: destinations,
            onSelectDestination: onSelectDestination,
            onCreateNote: onCreateNote,
            onTranscribeVoice: onTranscribeVoice,
            onKeep: { note, voiceURL in
                onKeep(note, voiceURL)
                close()
            },
            onDiscard: {
                onDiscard()
                close()
            }
        ).environmentObject(appState))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        panel.animator().alphaValue = 1
        self.panel = panel
    }
}

final class CaptureKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class CaptureVoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var power: Float = -60
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var outputURL: URL?

    func clearOutput() {
        outputURL = nil
    }

    func toggle() {
        isRecording ? stop() : requestAndStart()
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    private func requestAndStart() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else {
                errorMessage = "Microphone access is needed for a voice note."
                return
            }
            start()
        }
    }

    private func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("noted-capture-voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: 60) else {
                throw NSError(domain: "Noted.CaptureVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "The microphone did not start."])
            }
            self.recorder = recorder
            outputURL = url
            elapsed = 0
            power = -60
            isRecording = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    self.elapsed = recorder.currentTime
                    self.power = recorder.averagePower(forChannel: 0)
                    if !recorder.isRecording || self.elapsed >= 60 { self.stop() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CaptureReviewView: View {
    let step: ExplorationStep
    let isTextLift: Bool
    let destinationTitle: String
    let destinations: [NoteDestination]
    let onSelectDestination: (NoteDestination) -> Void
    let onCreateNote: () -> Void
    let onTranscribeVoice: (URL) async -> Result<String, Error>
    let onKeep: (String, URL?) -> Void
    let onDiscard: () -> Void

    @StateObject private var voice = CaptureVoiceRecorder()
    @State private var note = ""
    @State private var isFinishing = false
    @State private var isTranscribing = false

    var body: some View {
        Group {
            if isTextLift {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.45)
                    textLift
                }
                .ignoresSafeArea()
            } else {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.45)
                    screenshotHold
                        .padding(28)
                }
                .ignoresSafeArea()
            }
        }
        .onExitCommand { discard() }
        .onKeyPress(.escape) {
            discard()
            return .handled
        }
    }

    private var screenshotHold: some View {
        VStack(spacing: -7) {
            VStack(alignment: .leading, spacing: 8) {
                destinationPicker
                if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 600, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                Text(metadata)
                    .font(NotefyFont.caption)
                    .tracking(1)
                    .foregroundStyle(NotefyTheme.inkFaint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(NotefyTheme.cardPaper)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
            .rotationEffect(.degrees(-0.6))

            sticky
                .padding(.horizontal, 34)
                .rotationEffect(.degrees(1.2))
        }
        .frame(width: 640)
    }

    private var textLift: some View {
        VStack(alignment: .leading, spacing: 13) {
            destinationPicker
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(NotefyTheme.pebbleOlive).frame(width: 3)
                Text(displayExcerpt)
                    .font(NotefyFont.body)
                    .lineSpacing(7)
                    .foregroundStyle(NotefyTheme.ink)
                    .padding(.horizontal, 3)
                    .background(NotefyTheme.pebbleTan.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(sourceLine)
                .font(NotefyFont.caption)
                .tracking(1)
                .foregroundStyle(NotefyTheme.inkFaint)

            noteField
                .padding(.vertical, 5)
                .background(RuledNoteLines())

            captureActions
        }
        .padding(20)
        .frame(width: 560)
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
        .transition(.scale(scale: 0.98).combined(with: .opacity))
    }

    private var sticky: some View {
        VStack(alignment: .leading, spacing: 5) {
            noteField
            if let error = voice.errorMessage {
                Text(error).font(NotefyFont.caption).foregroundStyle(NotefyTheme.marginRose)
            }
            captureActions
        }
        .padding(12)
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
    }

    private var destinationPicker: some View {
        CaptureDestinationPicker(
            initialTitle: destinationTitle,
            destinations: destinations,
            onSelect: onSelectDestination,
            onCreate: onCreateNote
        )
    }

    @ViewBuilder
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("add a thought…", text: Binding(
                get: { note },
                set: { note = String($0.prefix(1_600)) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(NotefyFont.hand)
            .foregroundStyle(NotefyTheme.ink)
            .lineLimit(1...12)
            .fixedSize(horizontal: false, vertical: true)
            .onSubmit { keep() }

            if isTranscribing {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Adding what you said below your typed thought…")
                        .font(NotefyFont.caption)
                        .foregroundStyle(NotefyTheme.inkSoft)
                    Spacer()
                }
                .frame(minHeight: 34)
            } else if voice.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(NotefyTheme.marginRose).frame(width: 8, height: 8)
                    Text("RECORDING · THIS WILL BE ADDED BELOW")
                        .font(NotefyFont.caption)
                        .tracking(0.7)
                        .foregroundStyle(NotefyTheme.inkSoft)
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { index in
                            Capsule()
                                .fill(NotefyTheme.ink)
                                .frame(width: 2.5, height: waveformHeight(index) * 0.55)
                        }
                    }
                    Spacer()
                    Text(time(voice.elapsed))
                        .font(NotefyFont.caption)
                        .foregroundStyle(voice.elapsed >= 50 ? NotefyTheme.marginRose : NotefyTheme.inkSoft)
                }
                .frame(minHeight: 34)
            }
        }
    }

    private var captureActions: some View {
        HStack(spacing: 9) {
            if note.count >= 1_300 {
                Text("\(note.count) / 1600")
                    .font(NotefyFont.caption)
                    .foregroundStyle(note.count >= 1_550 ? NotefyTheme.marginRose : NotefyTheme.inkFaint)
            }
            Spacer()
            Button(action: toggleVoiceAnnotation) {
                ZStack {
                    Circle().fill(voice.isRecording ? NotefyTheme.marginRose : Color.clear)
                    Circle().stroke(NotefyTheme.ink, lineWidth: 1.5)
                    OverlayIcon(kind: .microphone).frame(width: 17, height: 17)
                        .colorInvertIfRecording(voice.isRecording)
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(isTranscribing)
            Button(action: discard) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("DISCARD · ESC")
                }
                .font(NotefyFont.caption)
                .tracking(0.8)
                .foregroundStyle(NotefyTheme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color.clear, in: Capsule())
                .overlay(Capsule().stroke(NotefyTheme.ink.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Button(action: keep) {
                Text("KEEP ↧").font(NotefyFont.label).tracking(1.1)
                    .padding(.horizontal, 17).padding(.vertical, 10)
                    .background(NotefyTheme.ink, in: Capsule())
                    .foregroundStyle(NotefyTheme.sand)
            }
            .buttonStyle(.plain)
            .disabled(voice.isRecording || isTranscribing)
            .opacity(voice.isRecording || isTranscribing ? 0.42 : 1)
        }
    }

    private var displayExcerpt: String {
        let text = step.selectedText ?? ""
        guard text.count > 600 else { return text }
        return "\(text.prefix(600))… +\(text.count - 600) more"
    }

    private var sourceLine: String {
        "\(sourceName) · \(step.windowTitle) · \(step.timestamp.formatted(date: .omitted, time: .shortened))".uppercased()
    }

    private var metadata: String {
        "SCREEN CAPTURE · \(step.timestamp.formatted(date: .omitted, time: .shortened)) · \(sourceName)".uppercased()
    }

    private var sourceName: String {
        if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host }
        if ["Notefy", "Noted", "notefy-app"].contains(step.appName) { return "Screen region" }
        return step.appName
    }

    private func waveformHeight(_ index: Int) -> CGFloat {
        let normalized = max(0.12, min(1, CGFloat((voice.power + 60) / 60)))
        let rhythm = CGFloat([0.45, 0.8, 0.55, 1, 0.68][index % 5])
        return 7 + 31 * normalized * rhythm
    }

    private func time(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func keep() {
        guard !isFinishing, !voice.isRecording, !isTranscribing else { return }
        isFinishing = true
        voice.stop()
        onKeep(note.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    private func toggleVoiceAnnotation() {
        if !voice.isRecording {
            voice.toggle()
            return
        }

        voice.stop()
        guard let url = voice.outputURL else { return }
        isTranscribing = true
        Task {
            let result = await onTranscribeVoice(url)
            try? FileManager.default.removeItem(at: url)
            voice.clearOutput()
            switch result {
            case .success(let transcript):
                let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    let existing = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    note = existing.isEmpty ? clean : existing + "\n" + clean
                }
            case .failure(let error):
                voice.errorMessage = "Could not add speech: \(error.localizedDescription)"
            }
            isTranscribing = false
        }
    }

    private func discard() {
        guard !isFinishing else { return }
        isFinishing = true
        voice.stop()
        if let url = voice.outputURL { try? FileManager.default.removeItem(at: url) }
        onDiscard()
    }
}

private struct CaptureDestinationPicker: View {
    @State private var title: String
    @State private var showPicker = false
    let onSelect: (NoteDestination) -> Void
    let onCreate: () -> Void

    init(
        initialTitle: String,
        destinations: [NoteDestination],
        onSelect: @escaping (NoteDestination) -> Void,
        onCreate: @escaping () -> Void
    ) {
        _title = State(initialValue: initialTitle)
        self.onSelect = onSelect
        self.onCreate = onCreate
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                Text("SAVING TO · \(title.uppercased())")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(NotefyFont.caption).tracking(0.7)
            .foregroundStyle(NotefyTheme.inkSoft)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(NotefyTheme.sandDeep, in: Capsule())
            .overlay(Capsule().stroke(NotefyTheme.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            NoteSearchPicker(
                title: "Save this capture to",
                onSelect: { destination in
                    title = destination.title
                    onSelect(destination)
                },
                onCreateNew: {
                    onCreate()
                    title = "Untitled note"
                }
            )
        }
    }
}

private struct RuledNoteLines: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: CGFloat(27), through: size.height, by: 27) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(NotefyTheme.inkSoft.opacity(0.16)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    @ViewBuilder
    func colorInvertIfRecording(_ active: Bool) -> some View {
        if active { self.colorInvert() } else { self }
    }
}
