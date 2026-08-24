import Foundation
import AVFoundation

public class VoiceRecorder {
    private var audioRecorder: AVAudioRecorder?
    public private(set) var isRecording = false
    
    public init() {}
    
    public func startRecording(saveTo url: URL) -> Bool {
        guard !isRecording else { return false }
        
        // Define audio format: AAC, compact and clear for dictation
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0, // 16kHz is ideal for speech transcription
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard let recorder = audioRecorder else {
                print("⚠️ Failed to initialize audio recorder instance.")
                return false
            }
            
            if recorder.prepareToRecord() {
                recorder.record()
                isRecording = true
                print("🎙️ Voice thought recording started. Saving to: \(url.path)")
                return true
            } else {
                print("⚠️ Failed to prepare AVAudioRecorder.")
                return false
            }
        } catch {
            print("⚠️ Error starting audio recording: \(error.localizedDescription)")
            return false
        }
    }
    
    public func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        isRecording = false
        audioRecorder = nil
        print("🎙️ Voice thought recording finished.")
    }
}
