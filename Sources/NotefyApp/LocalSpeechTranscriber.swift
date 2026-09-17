import Foundation

enum ModelRuntimeState: Equatable {
    case notDownloaded
    case downloading(Double)
    case loadingModel
    case ready
    case transcribing
    case failed(String)

    var label: String {
        switch self {
        case .notDownloaded: return "Not downloaded"
        case .downloading(let progress): return "Downloading model… \(Int(progress * 100))%"
        case .loadingModel: return "Loading model…"
        case .ready: return "Ready"
        case .transcribing: return "Transcribing…"
        case .failed(let message): return "Error: \(message)"
        }
    }
}

/// On-device transcription of a finished recording.
///
/// This used to be WhisperKit, which meant carrying two speech models: Whisper
/// for the file and Parakeet for the live pass. They do the same job, so the
/// app now keeps one — the same Parakeet weights the live transcript already
/// downloaded are replayed over the whole recording when you stop. One
/// download, one model in memory, and the finished transcript can no longer
/// disagree with the words you watched appear.
///
/// The model is cached under Application Support by FluidAudio, so repeat
/// launches skip the download.
@MainActor
final class LocalSpeechTranscriber: ObservableObject {
    @Published private(set) var state: ModelRuntimeState = .notDownloaded

    /// Kept loaded between recordings: the first load is the expensive one.
    private var transcriber: ParakeetTranscriber?

    /// Downloads the model on first use and loads it into Core ML.
    func ensureReady() async {
        if transcriber != nil, state == .ready { return }
        let transcriber = self.transcriber ?? ParakeetTranscriber()
        self.transcriber = transcriber
        do {
            try await transcriber.prepare { [weak self] step in
                Task { @MainActor in
                    guard let self else { return }
                    switch step {
                    case .downloading(let fraction): self.state = .downloading(fraction)
                    case .compiling: self.state = .loadingModel
                    case .ready: self.state = .ready
                    }
                }
            }
            state = .ready
        } catch {
            self.transcriber = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// The whole recording, in one pass.
    func transcribe(audioURL: URL) async -> Result<String, Error> {
        await ensureReady()
        guard let transcriber else {
            let detail: String
            if case .failed(let message) = state { detail = message } else { detail = "Local model unavailable" }
            return .failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: detail]))
        }

        state = .transcribing
        defer { state = .ready }

        do {
            let text = try await transcriber.transcribe(fileURL: audioURL)
            return .success(text.isEmpty ? "(No speech detected)" : text)
        } catch {
            return .failure(error)
        }
    }
}
