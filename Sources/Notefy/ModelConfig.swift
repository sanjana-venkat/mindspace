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
