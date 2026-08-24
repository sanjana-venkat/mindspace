import Foundation
import WhisperKit

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

/// Downloads a Whisper CoreML model (via WhisperKit/Hugging Face) on first use and
/// runs transcription fully on-device afterward. Model is cached under
/// Application Support so repeat launches skip the download.
@MainActor
final class LocalWhisperTranscriber: ObservableObject {
    @Published private(set) var state: ModelRuntimeState = .notDownloaded

    private var pipe: WhisperKit?
    private var loadedVariant: String?
    private let downloadBase: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        downloadBase = support.appendingPathComponent("Notefy/WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
    }

    /// Ensures the given model variant (e.g. "tiny", "base", "small") is downloaded and loaded.
    func ensureReady(variant: String) async {
        let variant = resolvedLocalVariant(variant)
        if let loadedVariant, loadedVariant == variant, pipe != nil {
            state = .ready
            return
        }

        do {
            state = .downloading(0)
            let modelFolder = try await WhisperKit.download(
                variant: variant,
                downloadBase: downloadBase,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.state = .downloading(progress.fractionCompleted)
                    }
                }
            )

            state = .loadingModel
            let config = WhisperKitConfig(model: variant, modelFolder: modelFolder.path, load: true)
            pipe = try await WhisperKit(config)
            loadedVariant = variant
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func transcribe(audioURL: URL, variant: String) async -> Result<String, Error> {
        let variant = resolvedLocalVariant(variant)
        await ensureReady(variant: variant)
        guard let pipe else {
            let detail: String
            if case .failed(let message) = state { detail = message } else { detail = "Local model unavailable" }
            return .failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: detail]))
        }

        state = .transcribing
        defer { state = .ready }

        do {
            let results = try await pipe.transcribe(audioPath: audioURL.path)
            let text = results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return .success(text.isEmpty ? "(No speech detected)" : text)
        } catch {
            return .failure(error)
        }
    }

    private func resolvedLocalVariant(_ value: String) -> String {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == "whisper-1" || normalized.contains("/") || normalized.contains("http") {
            return "base"
        }
        return normalized
    }
}
