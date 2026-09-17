import Foundation
import Combine

/// One line of the running transcript, stamped with when in the recording it
/// was said so a thought written now can point at it later.
struct LiveTranscriptLine: Identifiable, Equatable {
    enum Voice: Equatable, Hashable {
        case you, others, mac

        var label: String {
            switch self {
            case .you: return "YOU"
            case .others: return "OTHERS"
            case .mac: return "MAC"
            }
        }
    }

    let id = UUID()
    let at: TimeInterval
    let voice: Voice
    let text: String

    var clock: String { String(format: "%d:%02d", Int(at) / 60, Int(at) % 60) }
}

/// Transcribes while you are still recording.
///
/// This used to run Whisper over five-second windows, which is a batch model
/// doing a streaming job: every line cost a second or two of thinking, arrived
/// in a clump, and the gap grew for as long as the meeting ran. Parakeet EOU is
/// a cache-aware streaming model — it keeps its encoder state between 320ms
/// chunks and emits words as it decodes them, faster than they are spoken.
///
/// A meeting gets two of them, because a decoder's state belongs to one voice:
/// yours on the microphone, everyone else's on what the Mac is playing.
///
/// It is still a rough pass. The note's real transcript is made from the whole
/// recording when you stop, with whichever provider you chose.
@MainActor
final class LiveTranscriptEngine: ObservableObject {
    enum Mode { case microphone, systemAudio, meeting }

    enum Status: Equatable {
        case off
        /// Carries what the model is doing — downloading, loading — because
        /// "warming up" for ninety seconds with no further word reads as
        /// broken rather than busy.
        case preparing(String)
        case listening
        case unavailable(String)
    }

    /// Sentences the model has finished with.
    @Published private(set) var lines: [LiveTranscriptLine] = []
    /// The sentence being spoken right now, per voice — ghost text, replaced as
    /// more of it is decoded and promoted to a line when the utterance ends.
    @Published private(set) var pending: [LiveTranscriptLine.Voice: String] = [:]
    @Published private(set) var status: Status = .off

    private var primary: ParakeetTranscriber?
    private var secondary: ParakeetTranscriber?
    private var mode: Mode = .meeting
    private var startedAt = Date()
    private var running = false
    private let maxLines = 400

    func start(mode: Mode) {
        self.mode = mode
        lines = []
        pending = [:]
        startedAt = Date()
        running = true
        status = .preparing("STARTING")

        let primary = ParakeetTranscriber()
        let secondary = mode == .meeting ? ParakeetTranscriber() : nil
        self.primary = primary
        self.secondary = secondary

        let primaryVoice: LiveTranscriptLine.Voice = mode == .systemAudio ? .mac : .you

        Task { [weak self] in
            guard let self else { return }
            do {
                try await primary.prepare { step in
                    Task { @MainActor [weak self] in self?.report(step) }
                }
                await primary.observe(
                    onWords: { [weak self] words in
                        Task { @MainActor [weak self] in self?.pending[primaryVoice] = words }
                    },
                    onSentence: { [weak self] sentence in
                        Task { @MainActor [weak self] in self?.commit(sentence, as: primaryVoice) }
                    })

                if let secondary {
                    try await secondary.prepare { _ in }
                    await secondary.observe(
                        onWords: { [weak self] words in
                            Task { @MainActor [weak self] in self?.pending[.others] = words }
                        },
                        onSentence: { [weak self] sentence in
                            Task { @MainActor [weak self] in self?.commit(sentence, as: .others) }
                        })
                }

                guard self.running else { return }
                self.status = .listening
            } catch {
                guard self.running else { return }
                self.status = .unavailable(error.localizedDescription)
            }
        }
    }

    func stop() {
        running = false
        status = .off
        pending = [:]
        let leaving = [primary, secondary].compactMap { $0 }
        primary = nil
        secondary = nil
        Task {
            for transcriber in leaving { await transcriber.shutdown() }
        }
    }

    func appendMicrophone(_ samples: [Float]) {
        guard running, mode != .systemAudio, let primary else { return }
        Task { try? await primary.feed(samples) }
    }

    func appendSystemAudio(_ samples: [Float]) {
        guard running else { return }
        switch mode {
        case .meeting:
            guard let secondary else { return }
            Task { try? await secondary.feed(samples) }
        case .systemAudio:
            guard let primary else { return }
            Task { try? await primary.feed(samples) }
        case .microphone:
            return
        }
    }

    // MARK: what the model says

    private func report(_ step: ParakeetTranscriber.Preparation) {
        guard running, status != .listening else { return }
        switch step {
        case .downloading(let fraction):
            status = .preparing("DOWNLOADING \(Int(fraction * 100))%")
        case .compiling:
            status = .preparing("LOADING MODEL")
        case .ready:
            status = .listening
        }
    }

    private func commit(_ sentence: String, as voice: LiveTranscriptLine.Voice) {
        guard running else { return }
        pending[voice] = nil
        let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lines.append(LiveTranscriptLine(at: Date().timeIntervalSince(startedAt), voice: voice, text: clean))
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }
}
