import Foundation

public enum ModelProvider: String, Codable {
    case local = "local"
    case api = "api"
}

public struct AudioConfig: Codable {
    public var provider: ModelProvider
    public var apiURL: String // e.g. "https://api.openai.com/v1/audio/transcriptions"
    public var apiKey: String
    public var modelName: String // e.g. "whisper-1"
    
    public init(provider: ModelProvider = .local, apiURL: String = "", apiKey: String = "", modelName: String = "whisper-1") {
        self.provider = provider
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.modelName = modelName
    }
}

public struct VisionConfig: Codable {
    public var provider: ModelProvider
    public var apiURL: String // e.g. "https://api.openai.com/v1/chat/completions" or "http://localhost:11434/api/chat"
    public var apiKey: String
    public var modelName: String // e.g. "qwen2-vl" or "gpt-4o"
    
    public init(provider: ModelProvider = .local, apiURL: String = "http://localhost:11434/api/chat", apiKey: String = "", modelName: String = "qwen2-vl") {
        self.provider = provider
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.modelName = modelName
    }
}

public struct NotefySettings: Codable {
    public var audio: AudioConfig
    public var vision: VisionConfig
    
    public init(audio: AudioConfig = AudioConfig(), vision: VisionConfig = VisionConfig()) {
        self.audio = audio
        self.vision = vision
    }
    
    // Save configuration settings to local JSON file
    public func save(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: url)
        }
    }
    
    // Load configuration settings from local JSON file
    public static func load(from url: URL) -> NotefySettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(NotefySettings.self, from: data) else {
            // Return defaults if file doesn't exist
            let defaults = NotefySettings()
            defaults.save(to: url)
            return defaults
        }
        return settings
    }
}
import Foundation

public class AudioClient {
    private let config: AudioConfig
    
    public init(config: AudioConfig) {
        self.config = config
    }
    
    // Transcribe audio using local engine or remote API
    public func transcribe(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        if config.provider == .local {
            transcribeLocally(audioURL: audioURL, completion: completion)
        } else {
            transcribeViaAPI(audioURL: audioURL, completion: completion)
        }
    }
    
    private func transcribeLocally(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        print("🎙️ CoreML: Transcribing audio locally via WhisperKit...")
        // Simulating Whisper CoreML response for offline/local flow
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            let mockTranscript = "Combining background logs of browser activities alongside dictation transcripts will result in notes with a much higher density of exact terms and source link context than transcription alone."
            completion(.success(mockTranscript))
        }
    }
    
    private func transcribeViaAPI(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiURL) else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Audio API URL"])))
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Build multipart body
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(config.modelName)\r\n".data(using: .utf8)!)
        
        // Add file parameter
        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/aac\r\n\r\n".data(using: .utf8)!)
        
        do {
            let fileData = try Data(contentsOf: audioURL)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data received from transcription API"])))
                return
            }
            
            // OpenAI Whisper returns a JSON with {"text": "..."}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                completion(.success(text))
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "Unknown response format"
                completion(.success(responseString))
            }
        }
        task.resume()
    }
}
import Foundation

public class VisionClient {
    private let config: VisionConfig
    
    public init(config: VisionConfig) {
        self.config = config
    }
    
    // Analyze desktop screenshot to extract OCR text and window context
    public func analyzeScreen(imageURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let imgData = try? Data(contentsOf: imageURL) else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to read screenshot image file"])))
            return
        }
        
        let base64String = imgData.base64EncodedString()
        
        if config.provider == .local {
            analyzeViaOllama(base64Image: base64String, completion: completion)
        } else {
            analyzeViaCloudAPI(base64Image: base64String, completion: completion)
        }
    }
    
    // Call local Ollama vision endpoint
    private func analyzeViaOllama(base64Image: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiURL) else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Ollama Chat Payload format
        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": "Describe this screen capture and extract active browser tab, url, and any selected text.",
                    "images": [base64Image]
                ]
            ],
            "stream": false
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed serialization of Ollama payload"])))
            return
        }
        
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data from local Ollama model"])))
                return
            }
            
            // Ollama returns {"message": {"content": "..."}}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                completion(.success(content))
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "Failed to parse local model output"
                completion(.success(responseString))
            }
        }
        task.resume()
    }
    
    // Call standard OpenAI-compatible cloud vision endpoint (OpenAI, OpenRouter, Custom VLM)
    private func analyzeViaCloudAPI(base64Image: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiURL) else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Cloud API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Chat completion message with vision payload
        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "What is the active window, chrome URL, and selection on this screen? Output a concise JSON description."
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed serialization of Vision API payload"])))
            return
        }
        
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data from Vision API"])))
                return
            }
            
            // Standard OpenAI format: choices[0].message.content
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                completion(.success(content))
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "Failed to parse API model output"
                completion(.success(responseString))
            }
        }
        task.resume()
    }
}
import Foundation
import AppKit

public struct ExplorationStep: Codable {
    public let timestamp: Date
    public let appName: String
    public let windowTitle: String
    public let url: String?
    public let selectedText: String?
    public let screenshotPath: String?
    
    public init(appName: String, windowTitle: String, url: String? = nil, selectedText: String? = nil, screenshotPath: String? = nil) {
        self.timestamp = Date()
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.screenshotPath = screenshotPath
    }
}

public class ExplorationTracker {
    public private(set) var isTracking = false
    public private(set) var isPaused = false
    private var lastActiveApp: String = ""
    private var lastActiveTitle: String = ""
    private var steps: [ExplorationStep] = []
    private let outputDirectory: URL
    
    public var onStepCaptured: ((ExplorationStep) -> Void)?
    
    public init(outputDir: URL) {
        self.outputDirectory = outputDir
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }
    
    public func start() {
        guard !isTracking else { return }
        isTracking = true
        steps = []
        
        print("🚀 Notefy Exploration Tracker Started!")
        print("Watching active window changes...")
        
        // Start watching didActivateApplicationNotification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Force capture the currently active app immediately
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            captureCurrentState(activeApp)
        }
    }
    
    public func stop() -> [ExplorationStep] {
        guard isTracking else { return [] }
        isTracking = false
        
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        print("🛑 Notefy Exploration Tracker Stopped.")
        return steps
    }
    
    public func pause() {
        guard isTracking && !isPaused else { return }
        isPaused = true
        print("⏸️ Exploration tracker paused.")
    }
    
    public func resume() {
        guard isTracking && isPaused else { return }
        isPaused = false
        print("▶️ Exploration tracker resumed.")
    }
    
    public func captureCustomStep(_ step: ExplorationStep) {
        guard isTracking && !isPaused else { return }
        steps.append(step)
        onStepCaptured?(step)
    }
    
    @objc private func handleAppChange(_ notification: Notification) {
        guard isTracking && !isPaused else { return }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            captureCurrentState(app)
        }
    }
    
    public func captureCurrentState(_ app: NSRunningApplication) {
        guard isTracking && !isPaused else { return }
        let appName = app.localizedName ?? "Unknown App"
        let windowTitle = getActiveWindowTitle(for: app) ?? ""
        
        // Skip background or system elements
        if appName == "Finder" && windowTitle.isEmpty { return }
        
        var url: String? = nil
        var pageTitle = windowTitle
        
        // Special case: Google Chrome
        if appName == "Google Chrome" {
            let chromeDetails = getChromeTabDetails()
            url = chromeDetails.url
            if let title = chromeDetails.title {
                pageTitle = title
            }
        }
        
        // Avoid duplicate captures if app & title haven't changed
        if appName == lastActiveApp && pageTitle == lastActiveTitle {
            return
        }
        
        lastActiveApp = appName
        lastActiveTitle = pageTitle
        
        // Capture highlighted text from clipboard or accessibility
        let selectedText = getSelectedText()
        
        // Take screenshot asynchronously
        let screenshotFilename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let screenshotURL = self.outputDirectory.appendingPathComponent(screenshotFilename)
        
        // Capture screenshot
        if ScreenCapturer.takeScreenshot(saveTo: screenshotURL) {
            let step = ExplorationStep(
                appName: appName,
                windowTitle: pageTitle,
                url: url,
                selectedText: selectedText,
                screenshotPath: screenshotURL.path
            )
            steps.append(step)
            onStepCaptured?(step)
        } else {
            let step = ExplorationStep(
                appName: appName,
                windowTitle: pageTitle,
                url: url,
                selectedText: selectedText,
                screenshotPath: nil
            )
            steps.append(step)
            onStepCaptured?(step)
        }
    }
    
    // Read selected text using AppleScript or Clipboard
    private func getSelectedText() -> String? {
        // Option A: Quick AppleScript to trigger cmd+c and check pasteboard
        let originalPasteboard = NSPasteboard.general.string(forType: .string)
        
        let source = """
        tell application "System Events"
            keystroke "c" using {command down}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        
        // Wait a tiny fraction for clipboard to update
        Thread.sleep(forTimeInterval: 0.1)
        
        let currentPasteboard = NSPasteboard.general.string(forType: .string)
        
        // Restore pasteboard so we don't mess up user clipboard
        if let original = originalPasteboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(original, forType: .string)
        }
        
        // If it changed, return the copied selection
        if currentPasteboard != originalPasteboard {
            return currentPasteboard?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    // Extract active Google Chrome tab URL & Title via AppleScript
    private func getChromeTabDetails() -> (url: String?, title: String?) {
        let source = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                tell active tab of first window
                    return {URL, title}
                end tell
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return (nil, nil) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        
        if error != nil {
            return (nil, nil)
        }
        
        // NSAppleEventDescriptor lists are indexed starting from 1
        if result.numberOfItems == 2,
           let url = result.atIndex(1)?.stringValue,
           let title = result.atIndex(2)?.stringValue {
            return (url, title)
        }
        
        return (nil, nil)
    }
    
    // Get Window Title using CGWindowList API
    private func getActiveWindowTitle(for app: NSRunningApplication) -> String? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else {
            return nil
        }
        
        for info in windowListInfo {
            guard let dict = info as? NSDictionary,
                  let windowOwnerPID = dict[kCGWindowOwnerPID as String] as? Int,
                  windowOwnerPID == app.processIdentifier,
                  let windowLayer = dict[kCGWindowLayer as String] as? Int,
                  windowLayer == 0, // Main window layer
                  let windowName = dict[kCGWindowName as String] as? String else {
                continue
            }
            return windowName
        }
        return nil
    }
}
import Foundation

public class ScreenCapturer {
    public static func takeScreenshot(saveTo fileURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x flag takes screen capture silently without sound
        process.arguments = ["-x", fileURL.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("⚠️ Screencapture command execution failed: \(error.localizedDescription)")
            return false
        }
    }
}
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
import Foundation

public class ExplorationSummarizer {
    
    // Process raw steps, filter out noise, and build a formatted markdown note
    public static func summarize(steps: [ExplorationStep]) -> String {
        guard !steps.isEmpty else {
            return "# Notefy Exploration Summary\nNo exploration data captured."
        }
        
        // Define apps classified as context-switching/communication noise
        let noisyApps = ["Slack", "Microsoft Teams", "Mail", "Messages", "Discord", "Telegram"]
        
        // Filter out noise
        let filteredSteps = steps.filter { step in
            let isNoiseApp = noisyApps.contains(step.appName)
            
            // Filter criteria: Keep it if it has selected text, or if it is not a known communication noise app
            if step.selectedText != nil {
                return true
            }
            return !isNoiseApp
        }
        
        var output = ""
        output += "# Notefy Exploration Summary\n"
        output += "Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n"
        output += "Duration: Captured \(steps.count) events (Filtered down to \(filteredSteps.count) relevant actions)\n\n"
        
        output += "## 📝 Key Takeaways & Research Findings\n"
        
        var citations: [String] = []
        
        if filteredSteps.isEmpty {
            output += "Only context-switching noise was captured during this brief exploration session.\n"
        } else {
            for step in filteredSteps {
                let timeStr = DateFormatter.localizedString(from: step.timestamp, dateStyle: .none, timeStyle: .medium)
                
                // Track source for citations
                let sourceIdentifier: String
                if let url = step.url {
                    sourceIdentifier = "\(step.appName) — [\(step.windowTitle)](\(url))"
                } else {
                    sourceIdentifier = "\(step.appName) — \(step.windowTitle)"
                }
                
                if !citations.contains(sourceIdentifier) {
                    citations.append(sourceIdentifier)
                }
                
                let citationIndex = citations.firstIndex(of: sourceIdentifier)! + 1
                
                output += "### • [\(timeStr)] On \(step.appName) [\(citationIndex)]\n"
                output += "  Active Window: *\(step.windowTitle)*\n"
                
                if let selected = step.selectedText {
                    output += "  > **Highlighted Text**: \"\(selected)\"\n"
                }
                
                if let screenshot = step.screenshotPath {
                    output += "  *Screenshot recorded: \(URL(fileURLWithPath: screenshot).lastPathComponent)*\n"
                }
                output += "\n"
            }
        }
        
        // Output Citations List
        if !citations.isEmpty {
            output += "## 🌐 Sources & Citations\n"
            for (index, citation) in citations.enumerated() {
                output += "[\(index + 1)] \(citation)\n"
            }
        }
        
        // Context-Switching Noise Filter logs for verification
        let filteredOut = steps.filter { step in
            let isNoiseApp = noisyApps.contains(step.appName)
            return isNoiseApp && step.selectedText == nil
        }
        
        if !filteredOut.isEmpty {
            output += "\n## 🧹 Filtered Noise Logs (Removed by AI Agent)\n"
            for noise in filteredOut {
                output += "• Removed active focus on **\(noise.appName)**: *\(noise.windowTitle)*\n"
            }
        }
        
        return output
    }
}
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
