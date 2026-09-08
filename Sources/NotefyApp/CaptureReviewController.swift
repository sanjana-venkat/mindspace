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
                    Color.black.opacity(0.42)
                    textLift
                }
                .ignoresSafeArea()
            } else {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.42)
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
        VStack(alignment: .leading, spacing: 14) {
            destinationPicker

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(sourceName)
                        .font(Aurora.mono(9.5))
                        .foregroundStyle(Aurora.ink3)
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Aurora.surface2, in: Capsule())
                    Spacer(minLength: 0)
                    Text(metadata)
                        .font(Aurora.mono(9.5))
                        .foregroundStyle(Aurora.ink3)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Aurora.surface2.opacity(0.75))

                if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 360)
                }
            }
            .background(Aurora.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Aurora.line, lineWidth: 1))

            sticky
        }
        .padding(18)
        .frame(width: 660)
        .background(Aurora.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 50, y: 22)
    }

    private var textLift: some View {
        VStack(alignment: .leading, spacing: 13) {
            destinationPicker
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Aurora.accent).frame(width: 3)
                Text(displayExcerpt)
                    .font(Aurora.serif(16))
                    .lineSpacing(6)
                    .foregroundStyle(Aurora.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Aurora.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Aurora.line, lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)

            Text(sourceLine)
                .font(Aurora.mono(9.5))
                .tracking(1)
                .foregroundStyle(Aurora.ink3)

            sticky
        }
        .padding(18)
        .frame(width: 600)
        .background(Aurora.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Aurora.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 50, y: 22)
        .transition(.scale(scale: 0.98).combined(with: .opacity))
    }

    private var sticky: some View {
        VStack(alignment: .leading, spacing: 5) {
            noteField
            if let error = voice.errorMessage {
                Text(error).font(Aurora.ui(11.5, .medium)).foregroundStyle(Aurora.ink3)
            }
            captureActions
        }
        .padding(.top, 2)
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
            TextField("What were you thinking when you saved this?", text: Binding(
                get: { note },
                set: { note = String($0.prefix(1_600)) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(Aurora.serif(17))
            .foregroundStyle(Aurora.ink)
            .lineLimit(1...12)
            .fixedSize(horizontal: false, vertical: true)
            .onSubmit { keep() }

            if isTranscribing {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Adding what you said below your typed thought…")
                        .font(StoneFont.mark())
                        .foregroundStyle(Stoneink.textSecondary)
                    Spacer()
                }
                .frame(minHeight: 34)
            } else if voice.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(Stoneink.oxide600).frame(width: 8, height: 8)
                    Text("RECORDING · THIS WILL BE ADDED BELOW")
                        .font(StoneFont.mark())
                        .tracking(0.7)
                        .foregroundStyle(Stoneink.textSecondary)
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { index in
                            Capsule()
                                .fill(Stoneink.textPrimary)
                                .frame(width: 2.5, height: waveformHeight(index) * 0.55)
                        }
                    }
                    Spacer()
                    Text(time(voice.elapsed))
                        .font(StoneFont.mark())
                        .foregroundStyle(voice.elapsed >= 50 ? Stoneink.oxide600 : Stoneink.textSecondary)
                }
                .frame(minHeight: 34)
            }
        }
    }

    private var captureActions: some View {
        HStack(spacing: 9) {
            if note.count >= 1_300 {
                Text("\(note.count) / 1600")
                    .font(Aurora.mono(10))
                    .foregroundStyle(Aurora.ink3)
            }
            Spacer()
            Button(action: toggleVoiceAnnotation) {
                ZStack {
                    Circle().fill(voice.isRecording ? Aurora.accent : Aurora.surface2)
                    Circle().strokeBorder(Aurora.line, lineWidth: 1)
                    OverlayIcon(kind: .microphone, tint: voice.isRecording ? .white : NotefyTheme.ink)
                        .frame(width: 17, height: 17)
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(isTranscribing)
            Button(action: discard) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("DISCARD · ESC")
                }
                .font(Aurora.mono(10)).tracking(0.9)
                .foregroundStyle(Aurora.ink2)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Aurora.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Button(action: keep) {
                Text("KEEP ↧").font(Aurora.mono(10.5)).tracking(1.1)
                    .padding(.horizontal, 19).padding(.vertical, 11)
                    .background(Aurora.ink, in: Capsule())
                    .foregroundStyle(Aurora.ground)
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
            .font(Aurora.mono(10)).tracking(0.9)
            .foregroundStyle(Aurora.ink2)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Aurora.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
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

private extension View {
    @ViewBuilder
    func colorInvertIfRecording(_ active: Bool) -> some View {
        if active { self.colorInvert() } else { self }
    }
}
