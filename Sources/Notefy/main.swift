import Foundation
import AppKit
import Dispatch

// Setup active paths
let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
let notefySessionDir = desktopURL.appendingPathComponent("Notefy_Sessions")
let settingsURL = notefySessionDir.appendingPathComponent("settings.json")

// Ensure directory exists immediately
try? FileManager.default.createDirectory(at: notefySessionDir, withIntermediateDirectories: true)

// Load settings
var settings = NotefySettings.load(from: settingsURL)

print("==================================================")
print("             NOTEFY macOS PORTABLE DECK            ")
print("==================================================")
print("Session output directory: \(notefySessionDir.path)")
print("Settings configuration:   \(settingsURL.path)")

// Initialize clients based on settings
var audioClient = AudioClient(config: settings.audio)
var visionClient = VisionClient(config: settings.vision)

// Initialize modules
let tracker = ExplorationTracker(outputDir: notefySessionDir)
let recorder = VoiceRecorder()

var recordingSessionCount = 0

// Setup callbacks for Tracker
tracker.onStepCaptured = { step in
    print("\n🔍 [Captured Event] on: \(step.appName)")
    print("   Title: \(step.windowTitle)")
    if let url = step.url {
        print("   URL: \(url)")
    }
    if let selection = step.selectedText {
        print("   Highlight: \"\(selection)\"")
    }
    if let screenshot = step.screenshotPath {
        let screenshotURL = URL(fileURLWithPath: screenshot)
        print("   Screenshot saved: \(screenshotURL.lastPathComponent)")
        
        // Asynchronously analyze screenshot with VLM (either locally or API based on settings)
        print("   👁️ AI Vision: Analyzing screen layout...")
        visionClient.analyzeScreen(imageURL: screenshotURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    let previewText = analysis.replacingOccurrences(of: "\n", with: " ").prefix(85)
                    print("\n🧠 [VLM Analysis for \(step.appName)]: \"\(previewText)...\"")
                case .failure(_):
                    // If server/API not active, log default notice
                    print("\n🧠 [VLM Notice] Offline mock. To run live VLM, configure settings.json and run Ollama/API.")
                }
                // Reprint menu prompt to avoid visual stdin block
                print("\nSelect option: ", terminator: "")
                fflush(stdout)
            }
        }
    }
}

// Function to print console menu
func printMenu() {
    print("\n---------------- MENU CONTROLS ----------------")
    if !tracker.isTracking {
        print("[E] Start new Exploration Tracker session")
        print("[S] View Active Model Settings")
    } else {
        print("[E] Finish Exploration Tracker & compile summary")
        print("[P] Pause / Resume tracking")
    }
    
    if tracker.isTracking {
        if !recorder.isRecording {
            print("[R] Record inline Audio Voice Thought")
        } else {
            print("[R] Stop recording Audio Voice Thought")
        }
    }
    print("[Q] Quit Notefy")
    print("-----------------------------------------------")
    print("Select option: ", terminator: "")
    fflush(stdout)
}

// Global thread control
let consoleQueue = DispatchQueue(label: "notefy.console.reader")

consoleQueue.async {
    printMenu()
    
    while let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        switch input {
        case "e":
            DispatchQueue.main.async {
                if !tracker.isTracking {
                    tracker.start()
                    print("\n🟢 Tracking is active! Switch tabs/windows to capture logs.")
                } else {
                    let steps = tracker.stop()
                    print("\n📊 Compiling session findings...")
                    let summaryMarkdown = ExplorationSummarizer.summarize(steps: steps)
                    
                    // Save final markdown note to desktop
                    let outputFilename = "Exploration_Summary_\(Int(Date().timeIntervalSince1970)).md"
                    let outputURL = notefySessionDir.appendingPathComponent(outputFilename)
                    
                    do {
                        try summaryMarkdown.write(to: outputURL, atomically: true, encoding: .utf8)
                        print("\n✨ Done! Exploration notes compiled successfully.")
                        print("💾 Document saved: \(outputURL.path)")
                    } catch {
                        print("⚠️ Error saving summary markdown: \(error.localizedDescription)")
                    }
                }
                printMenu()
            }
            
        case "p":
            DispatchQueue.main.async {
                if tracker.isTracking {
                    if tracker.isPaused {
                        tracker.resume()
                        print("\n▶️ Tracking Resumed.")
                    } else {
                        tracker.pause()
                        print("\n⏸️ Tracking Paused.")
                    }
                } else {
                    print("\n⚠️ No active exploration session to pause.")
                }
                printMenu()
            }
            
        case "r":
            DispatchQueue.main.async {
                if tracker.isTracking {
                    if !recorder.isRecording {
                        recordingSessionCount += 1
                        let audioURL = notefySessionDir.appendingPathComponent("voice_note_\(recordingSessionCount).aac")
                        if recorder.startRecording(saveTo: audioURL) {
                            print("\n🎙️ Dictation active. Speak clearly...")
                        }
                        printMenu()
                    } else {
                        recorder.stopRecording()
                        print("\n🎙️ Audio captured. Transcribing voice thought...")
                        
                        let audioURL = notefySessionDir.appendingPathComponent("voice_note_\(recordingSessionCount).aac")
                        
                        // Asynchronously transcribe voice thought using configured provider (local/API)
                        audioClient.transcribe(audioURL: audioURL) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let text):
                                    print("\n📝 [Audio Transcribed]: \"\(text)\"")
                                    // Inject transcription step into timeline
                                    let voiceStep = ExplorationStep(
                                        appName: "Notefy Voice",
                                        windowTitle: "Audio Journal Thought",
                                        selectedText: text
                                    )
                                    tracker.captureCustomStep(voiceStep)
                                case .failure(let error):
                                    print("\n⚠️ Transcription failed: \(error.localizedDescription)")
                                }
                                printMenu()
                            }
                        }
                    }
                } else {
                    print("\n⚠️ Voice thoughts can only be recorded during active exploration.")
                    printMenu()
                }
            }
            
        case "s":
            DispatchQueue.main.async {
                if !tracker.isTracking {
                    print("\n=== CURRENT MODEL CONFIGURATIONS ===")
                    print("🔊 AUDIO MODEL PROVIDER: \(settings.audio.provider.rawValue.uppercased())")
                    print("   API URL:   \(settings.audio.apiURL.isEmpty ? "Local CoreML / WhisperKit" : settings.audio.apiURL)")
                    print("   Model:     \(settings.audio.modelName)")
                    print("   API Key:   \(settings.audio.apiKey.isEmpty ? "None" : "••••••••")")
                    print("\n👁️ VISION MODEL PROVIDER: \(settings.vision.provider.rawValue.uppercased())")
                    print("   API URL:   \(settings.vision.apiURL)")
                    print("   Model:     \(settings.vision.modelName)")
                    print("   API Key:   \(settings.vision.apiKey.isEmpty ? "None" : "••••••••")")
                    print("====================================")
                    print("💡 Edit settings.json inside Notefy_Sessions to change models or set custom endpoints.")
                } else {
                    print("\n⚠️ Settings menu cannot be accessed during an active exploration session.")
                }
                printMenu()
            }
            
        case "q":
            print("\n👋 Exiting Notefy. Clean up resources...")
            DispatchQueue.main.async {
                _ = tracker.stop()
                recorder.stopRecording()
                exit(0)
            }
            
        default:
            print("\n❌ Invalid option. Try again.")
            printMenu()
        }
    }
}

// Start Main thread Dispatch Loop (required for AppKit workspace observers)
dispatchMain()
