import Foundation

public enum ModelProvider: String, Codable, CaseIterable {
    case local = "local"
    case api = "api"          // OpenAI and anything speaking its format
    case gemini = "gemini"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .local: return "On-device"
        case .api: return "OpenAI"
        case .gemini: return "Gemini"
        case .anthropic: return "Claude"
        }
    }

    /// Where the key comes from, so the app can point people at it.
    public var keyURL: String {
        switch self {
        case .local: return ""
        case .api: return "platform.openai.com/api-keys"
        case .gemini: return "aistudio.google.com/apikey"
        case .anthropic: return "console.anthropic.com/settings/keys"
        }
    }

    public var defaultVisionURL: String {
        switch self {
        case .local: return "http://localhost:11434/api/chat"
        case .api: return "https://api.openai.com/v1/chat/completions"
        case .gemini: return ""
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        }
    }

    public var defaultVisionModel: String {
        switch self {
        case .local: return "qwen2.5vl:7b"
        case .api: return "gpt-4o"
        case .gemini: return "gemini-2.5-flash"
        case .anthropic: return "claude-sonnet-4-5"
        }
    }

    public var needsKey: Bool { self != .local }
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
    /// One key per provider, so switching between them doesn't lose the others.
    /// Keyed by `ModelProvider.rawValue`, with "audio." prefixes for the
    /// transcription side, which can use a different account entirely.
    public var savedKeys: [String: String]?

    public init(audio: AudioConfig = AudioConfig(), vision: VisionConfig = VisionConfig(), savedKeys: [String: String]? = nil) {
        self.audio = audio
        self.vision = vision
        self.savedKeys = savedKeys
    }

    public mutating func rememberKey(_ key: String, for provider: ModelProvider, audio: Bool = false) {
        var keys = savedKeys ?? [:]
        keys[(audio ? "audio." : "") + provider.rawValue] = key
        savedKeys = keys
    }

    public func key(for provider: ModelProvider, audio: Bool = false) -> String {
        savedKeys?[(audio ? "audio." : "") + provider.rawValue] ?? ""
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
