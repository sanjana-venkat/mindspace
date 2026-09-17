import AVFoundation
import FluidAudio
import Foundation

/// Streaming speech recognition for the live transcript.
///
/// Whisper is a batch model: it wants a window of audio, thinks for a second or
/// two, and hands back the lot. That is fine for the finished transcript and
/// hopeless for watching a meeting be heard — lines arrived in clumps and fell
/// further behind the longer you talked.
///
/// Parakeet EOU is cache-aware and streaming: it takes 320ms chunks, keeps its
/// encoder state between them, and emits words as they are decoded. Each
/// instance owns one conversation — one for your microphone, one for what the
/// Mac is playing — because the decoder state belongs to a single voice.
actor ParakeetTranscriber {
    /// How the model got on, for the interface to report.
    enum Preparation: Equatable {
        case downloading(Double)
        case compiling
        case ready
    }

    private let manager: StreamingEouAsrManager
    private var loaded = false

    /// Everything decoded so far this session; the callbacks hand back the
    /// whole thing each time, so the new part is the tail past this mark.
    private var committed = ""

    init(chunk: StreamingChunkSize = .ms320) {
        manager = StreamingEouAsrManager(chunkSize: chunk)
    }

    /// Downloads the model on first use — about 215MB, once — then loads it
    /// into Core ML. Safe to call again; it returns straight away when loaded.
    func prepare(progress: @escaping @Sendable (Preparation) -> Void) async throws {
        guard !loaded else {
            progress(.ready)
            return
        }
        try await manager.loadModels(to: nil, configuration: nil) { snapshot in
            switch snapshot.phase {
            case .listing, .downloading:
                progress(.downloading(snapshot.fractionCompleted))
            case .compiling:
                progress(.compiling)
            }
        }
        loaded = true
        progress(.ready)
    }

    /// `onWords` fires as the current sentence is being decoded — the ghost
    /// text. `onSentence` fires when the model decides an utterance has ended,
    /// which is the point at which a line is worth keeping.
    func observe(
        onWords: @escaping @Sendable (String) -> Void,
        onSentence: @escaping @Sendable (String) -> Void
    ) async {
        await manager.setPartialCallback { [weak self] whole in
            Task { [weak self] in
                guard let self, let tail = await self.tail(of: whole), !tail.isEmpty else { return }
                onWords(tail)
            }
        }
        await manager.setEouCallback { [weak self] whole in
            Task { [weak self] in
                guard let self, let sentence = await self.commit(whole), !sentence.isEmpty else { return }
                onSentence(sentence)
            }
        }
    }

    /// 16 kHz mono float PCM, which is what both recorders already produce.
    func feed(_ samples: [Float]) async throws {
        guard loaded, !samples.isEmpty, let buffer = Self.buffer(from: samples) else { return }
        _ = try await manager.process(audioBuffer: buffer)
    }

    /// Flushes whatever is still buffered and returns the last sentence.
    func finish() async -> String {
        guard loaded else { return "" }
        let whole = (try? await manager.finish()) ?? ""
        let tail = trailing(of: whole)
        committed = ""
        return tail
    }

    /// A finished recording, transcribed in one pass with the same weights the
    /// live pass uses. The file is resampled to 16 kHz mono and pushed through
    /// in one-second slices — the model is streaming, so "offline" here just
    /// means nobody is waiting between chunks.
    func transcribe(fileURL: URL) async throws -> String {
        try await prepare { _ in }
        await manager.reset()
        committed = ""

        let samples = try AudioConverter().resampleAudioFile(fileURL)
        guard !samples.isEmpty else { return "" }

        let slice = 16_000
        var index = 0
        while index < samples.count {
            let end = min(index + slice, samples.count)
            if let buffer = Self.buffer(from: Array(samples[index..<end])) {
                _ = try await manager.process(audioBuffer: buffer)
            }
            index = end
        }

        let text = try await manager.finish()
        committed = ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shutdown() async {
        await manager.cleanup()
        loaded = false
        committed = ""
    }

    // MARK: the growing transcript

    /// What has been decoded since the last committed sentence.
    private func tail(of whole: String) -> String? {
        trailing(of: whole).trimmingCharacters(in: .whitespaces)
    }

    /// Marks everything up to here as said, and returns the new part.
    private func commit(_ whole: String) -> String? {
        let sentence = trailing(of: whole).trimmingCharacters(in: .whitespaces)
        committed = whole
        return sentence
    }

    private func trailing(of whole: String) -> String {
        guard whole.hasPrefix(committed) else { return whole }
        return String(whole.dropFirst(committed.count))
    }

    /// The recorders hand over bare sample arrays; Core ML wants a buffer.
    private static func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16_000,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        return buffer
    }
}
