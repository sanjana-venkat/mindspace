import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public struct MeetingRecordingArtifacts {
    public let microphoneURL: URL?
    public let systemAudioURL: URL?
    public let systemAudioWarning: String?
}

public struct DualSourceAudioLevels: Sendable, Equatable {
    public let microphoneDecibels: Float
    public let systemAudioDecibels: Float
}

/// Captures two independent local tracks: selected microphone ("You") and
/// ScreenCaptureKit computer audio ("Others"). No meeting bot or vendor API is
/// involved, and the streams remain separate through transcription.
public final class MeetingRecorder {
    public private(set) var isRecording = false
    public private(set) var isSystemAudioActive = false
    public var preferredInputDeviceUID: String?
    public var onMicrophonePCM: (([Float]) -> Void)?
    public var onSystemAudioPCM: (([Float]) -> Void)?
    public var onLevels: ((DualSourceAudioLevels) -> Void)?

    private let microphone = MicrophonePCMRecorder()
    private let systemAudio = SystemAudioRecorder()
    private var microphoneURL: URL?
    private var systemAudioWarning: String?
    private let levelLock = NSLock()
    private var microphoneDB: Float = -160
    private var systemDB: Float = -160

    public init() {
        microphone.onPCM = { [weak self] samples, decibels in
            guard let self else { return }
            self.onMicrophonePCM?(samples)
            self.updateLevels(microphone: decibels)
        }
        systemAudio.onPCM = { [weak self] samples, decibels in
            guard let self else { return }
            self.onSystemAudioPCM?(samples)
            self.updateLevels(system: decibels)
        }
    }

    public static func availableInputDevices() -> [AudioInputDevice] {
        AudioInputDevices.available()
    }

    public func start(saveMicrophoneTo url: URL) async throws -> String? {
        guard !isRecording else { return systemAudioWarning }
        guard await Self.requestMicrophoneAccess() else {
            throw NSError(domain: "Notefy.MeetingRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access was denied."])
        }

        try microphone.start(saveTo: url, preferredInputDeviceUID: preferredInputDeviceUID)
        microphoneURL = url

        do {
            try await systemAudio.start()
            systemAudioWarning = nil
            isSystemAudioActive = true
        } catch {
            // Preserve a useful microphone-only recording when screen/system
            // audio permission or ScreenCaptureKit startup is unavailable.
            systemAudioWarning = "Computer audio is unavailable: \(error.localizedDescription)"
            isSystemAudioActive = false
        }
        isRecording = true
        return systemAudioWarning
    }

    /// Captures only audio playing on the Mac. This is used by the rail's
    /// computer-audio action and does not open or record the microphone.
    public func startComputerAudioOnly() async throws {
        guard !isRecording else { return }
        try await systemAudio.start()
        microphoneURL = nil
        systemAudioWarning = nil
        isSystemAudioActive = true
        isRecording = true
        updateLevels(microphone: -160)
    }

    public func stop() async -> MeetingRecordingArtifacts? {
        guard isRecording else { return nil }
        let completedMicrophoneURL = microphoneURL.flatMap { microphone.stop() ?? $0 }
        let systemURL = await systemAudio.stop()
        let artifacts = MeetingRecordingArtifacts(
            microphoneURL: completedMicrophoneURL,
            systemAudioURL: systemURL,
            systemAudioWarning: systemAudioWarning
        )
        isRecording = false
        isSystemAudioActive = false
        self.microphoneURL = nil
        systemAudioWarning = nil
        updateLevels(microphone: -160, system: -160)
        return artifacts
    }

    private func updateLevels(microphone: Float? = nil, system: Float? = nil) {
        levelLock.lock()
        if let microphone { microphoneDB = microphone }
        if let system { systemDB = system }
        let snapshot = DualSourceAudioLevels(microphoneDecibels: microphoneDB, systemAudioDecibels: systemDB)
        levelLock.unlock()
        onLevels?(snapshot)
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

private enum WAVHeader {
    static func data(byteCount: Int, sampleRate: UInt32 = 16_000) -> Data {
        let dataSize = UInt32(clamping: byteCount)
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = channels * (bits / 8)
        var result = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        result.append(contentsOf: "RIFF".utf8); append(dataSize &+ 36)
        result.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16)); append(UInt16(1))
        append(channels); append(sampleRate); append(byteRate); append(blockAlign); append(bits)
        result.append(contentsOf: "data".utf8); append(dataSize)
        return result
    }
}

private func powerDecibels(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return -160 }
    let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
    let rms = sqrt(sum / Float(samples.count))
    return rms > 0.000_001 ? max(-160, min(0, 20 * log10(rms))) : -160
}

private final class MicrophonePCMRecorder {
    var onPCM: (([Float], Float) -> Void)?
    private let engine = AVAudioEngine()
    private var fileHandle: FileHandle?
    private var outputURL: URL?
    private var bytesWritten = 0
    private var tapInstalled = false
    private let sampleRate: Double = 16_000

    func start(saveTo url: URL, preferredInputDeviceUID: String?) throws {
        guard !engine.isRunning else { return }
        try AudioInputDevices.apply(uid: preferredInputDeviceUID, to: engine)
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw NSError(domain: "Notefy.Microphone", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected microphone has no active input stream."])
        }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "Notefy.Microphone", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the transcription audio format."])
        }
        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw NSError(domain: "Notefy.Microphone", code: 4, userInfo: [NSLocalizedDescriptionKey: "The selected microphone format could not be converted to 16 kHz mono PCM."])
        }

        FileManager.default.createFile(atPath: url.path, contents: WAVHeader.data(byteCount: 0))
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw NSError(domain: "Notefy.Microphone", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create the microphone recording."])
        }
        handle.seekToEndOfFile()
        fileHandle = handle
        outputURL = url
        bytesWritten = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * self.sampleRate / buffer.format.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                guard !supplied else { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard conversionError == nil else { return }
            guard let channel = converted.floatChannelData?[0] else { return }
            let count = Int(converted.frameLength)
            let floats = Array(UnsafeBufferPointer(start: channel, count: count))
            var pcm = [Int16](repeating: 0, count: count)
            for index in 0..<count { pcm[index] = Int16(max(-1, min(1, floats[index])) * 32_767) }
            let data = pcm.withUnsafeBufferPointer { Data(buffer: $0) }
            self.fileHandle?.write(data)
            self.bytesWritten += data.count
            self.onPCM?(floats, powerDecibels(floats))
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            handle.closeFile()
            fileHandle = nil
            outputURL = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() -> URL? {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        guard let handle = fileHandle, let url = outputURL else { return nil }
        handle.seek(toFileOffset: 0)
        handle.write(WAVHeader.data(byteCount: bytesWritten))
        handle.closeFile()
        fileHandle = nil
        outputURL = nil
        let hasAudio = bytesWritten > 0
        bytesWritten = 0
        if !hasAudio { try? FileManager.default.removeItem(at: url); return nil }
        return url
    }
}

private final class SystemAudioRecorder: NSObject, SCStreamOutput {
    var onPCM: (([Float], Float) -> Void)?
    private var stream: SCStream?
    private var fileHandle: FileHandle?
    private var outputURL: URL?
    private var bytesWritten = 0
    private var recording = false
    private let sampleQueue = DispatchQueue(label: "com.notefy.system-audio")

    func start() async throws {
        guard !recording else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Notefy.SystemAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display is available for computer-audio capture."])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notefy-meeting-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        FileManager.default.createFile(atPath: url.path, contents: WAVHeader.data(byteCount: 0))
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw NSError(domain: "Notefy.SystemAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the computer-audio recording."])
        }
        handle.seekToEndOfFile()

        let configuration = SCStreamConfiguration()
        configuration.width = 2; configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        self.stream = stream; fileHandle = handle; outputURL = url; bytesWritten = 0; recording = true
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            recording = false; self.stream = nil; handle.closeFile(); fileHandle = nil; outputURL = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() async -> URL? {
        guard recording || outputURL != nil else { return nil }
        recording = false
        if let stream { try? await stream.stopCapture() }
        stream = nil
        return sampleQueue.sync {
            guard let handle = fileHandle, let url = outputURL else { return nil }
            handle.seek(toFileOffset: 0); handle.write(WAVHeader.data(byteCount: bytesWritten)); handle.closeFile()
            fileHandle = nil; outputURL = nil
            let hasAudio = bytesWritten > 0; bytesWritten = 0
            if !hasAudio { try? FileManager.default.removeItem(at: url); return nil }
            return url
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, recording,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return }
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer else { return }

        let channels = max(1, Int(format.mChannelsPerFrame))
        let floats: [Float]
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let count = length / MemoryLayout<Float>.size
            let input = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: count)
            let frames = count / channels
            floats = (0..<frames).map { frame in
                var sum: Float = 0
                for channel in 0..<channels { sum += input[frame * channels + channel] }
                return max(-1, min(1, sum / Float(channels)))
            }
        } else if format.mBitsPerChannel == 16 {
            let count = length / MemoryLayout<Int16>.size
            let input = UnsafeRawPointer(pointer).bindMemory(to: Int16.self, capacity: count)
            let frames = count / channels
            floats = (0..<frames).map { frame in
                var sum = 0
                for channel in 0..<channels { sum += Int(input[frame * channels + channel]) }
                return Float(sum / channels) / 32_768
            }
        } else { return }

        let pcm = floats.map { Int16(max(-1, min(1, $0)) * 32_767) }
        let data = pcm.withUnsafeBufferPointer { Data(buffer: $0) }
        fileHandle?.write(data); bytesWritten += data.count
        onPCM?(floats, powerDecibels(floats))
    }
}
