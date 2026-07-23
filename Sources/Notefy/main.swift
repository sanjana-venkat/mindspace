import Foundation
import AppKit
import Dispatch

// Setup active paths
let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
let notefySessionDir = desktopURL.appendingPathComponent("Notefy_Sessions")

print("==================================================")
print("             NOTEFY macOS PORTABLE DECK            ")
print("==================================================")
print("Session output directory: \(notefySessionDir.path)")

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
        print("   Screenshot saved: \(URL(fileURLWithPath: screenshot).lastPathComponent)")
    }
}

// Function to print console menu
func printMenu() {
    print("\n---------------- MENU CONTROLS ----------------")
    if !tracker.isTracking {
        print("[E] Start new Exploration Tracker session")
    } else {
        print("[E] Finish Exploration Tracker & compile summary")
        if tracker.isTracking {
            print("[P] Pause / Resume tracking")
        }
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
                    } else {
                        recorder.stopRecording()
                        print("\n🎙️ Saved voice thought.")
                    }
                } else {
                    print("\n⚠️ Voice thoughts can only be recorded during active exploration.")
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
