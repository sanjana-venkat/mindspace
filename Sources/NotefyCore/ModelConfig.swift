import Foundation

public enum ModelProvider: String, Codable, CaseIterable {
    case local = "local"
    case api = "api"
    case gemini = "gemini"

    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .api: return "Cloud API"
        case .gemini: return "Gemini"
        }
    }
}

public struct AudioConfig: Codable {
    public var provider: ModelProvider
    public var apiURL: String // e.g. "https://api.openai.com/v1/audio/transcriptions"
    public var apiKey: String
    public var modelName: String // e.g. "whisper-1"
    public var inputDeviceUID: String?
    
    public init(provider: ModelProvider = .local, apiURL: String = "", apiKey: String = "", modelName: String = "base", inputDeviceUID: String? = nil) {
        self.provider = provider
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.inputDeviceUID = inputDeviceUID
    }
}

public struct VisionConfig: Codable {
    public var provider: ModelProvider
    public var apiURL: String // e.g. "https://api.openai.com/v1/chat/completions" or "http://localhost:11434/api/chat"
    public var apiKey: String
    public var modelName: String // e.g. "qwen2-vl" or "gpt-4o"
    
    public init(provider: ModelProvider = .local, apiURL: String = "http://localhost:11434/api/chat", apiKey: String = "", modelName: String = "qwen3.5:9b") {
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
