import Foundation

/// Where API keys live.
///
/// This used to be the Keychain, which is the right answer for a signed app
/// and the wrong one here: an ad-hoc signature changes with every build, the
/// Keychain sees a different application each time, and macOS asks for your
/// login password before it will hand the item over. That prompt arrived at
/// launch, before anything was on screen, for a key the app itself had written
/// minutes earlier.
///
/// So: a file the app owns, in its own Application Support directory, readable
/// and writable by this user account and nobody else (0600, in a 0700
/// directory). It is plain text. Anything running as you could read it — which
/// is also true of your shell history and your `.env` files, and is the trade
/// being made for not being asked for a password on every launch.
///
/// Worth revisiting the day this app has a Developer ID signature: with a
/// stable identity the Keychain stops asking, and it is strictly better.
private enum ModelSecretStore {
    private static let fileName = "model-keys.json"

    private static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Notefy", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent(fileName) }

    static func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let keys = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return keys
    }

    @discardableResult
    static func writeAll(_ keys: [String: String]) -> Bool {
        let manager = FileManager.default
        let kept = keys.filter { !$0.value.isEmpty }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            guard let data = try? JSONEncoder().encode(kept) else { return false }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            // Written before anyone else can look: this user, nobody else.
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }
}

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
        case .api: return "gpt-6-astra"
        case .gemini: return GeminiClient.fallbackModel
        case .anthropic: return "claude-sonnet-4-5"
        }
    }

    public var needsKey: Bool { self != .local }

    /// What the picker offers. Typing a model name by hand was a guessing
    /// game — and an easy way to end up with a hosted name under the
    /// on-device provider.
    public var visionModels: [String] {
        switch self {
        case .local:
            // Nothing is offered until Ollama has been asked: what you have
            // pulled is what you can run, and a suggestion you haven't pulled
            // is just a name that will fail.
            return []
        case .api:
            // A starting point before a key is entered; once there is one, the
            // list comes from /v1/models on the account itself.
            return ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-luna", "gpt-5.6-terra"]
        case .gemini:
            return ["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash",
                    "gemini-3.5-flash-lite", "gemini-3.1-pro"]
        case .anthropic:
            return ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
        }
    }

    /// Only the on-device provider needs an endpoint in the interface; the
    /// hosted ones have one address and prefilling it invited confusion —
    /// an Ollama localhost URL sitting under OpenAI, for instance.
    public var showsEndpointField: Bool { self == .local }

    public var keyLabel: String {
        switch self {
        case .local: return ""
        case .api: return "OpenAI API key"
        case .gemini: return "Gemini API key"
        case .anthropic: return "Claude API key"
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .local: return ""
        case .api: return "sk-…"
        case .gemini: return "AIza…"
        case .anthropic: return "sk-ant-…"
        }
    }

    public var keyHint: String {
        switch self {
        case .local: return ""
        case .api: return "Reads your captures and writes the organized note. Key from \(keyURL)."
        case .gemini: return "One key covers transcription and the organized note. Key from \(keyURL)."
        case .anthropic: return "Claude writes the organized note; voice stays on-device. Key from \(keyURL)."
        }
    }
}

public struct AudioConfig: Codable, Equatable {
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

public struct VisionConfig: Codable, Equatable {
    public var provider: ModelProvider
    public var apiURL: String // e.g. "https://api.openai.com/v1/chat/completions" or "http://localhost:11434/api/chat"
    public var apiKey: String
    public var modelName: String // e.g. "qwen2-vl" or "gpt-4o"
    
    public init(provider: ModelProvider = .local, apiURL: String = "http://localhost:11434/api/chat", apiKey: String = "", modelName: String = "qwen2.5vl:7b") {
        self.provider = provider
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.modelName = modelName
    }
}

public struct NotefySettings: Codable, Equatable {
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
        var keys = savedKeys ?? [:]
        keys["audio." + audio.provider.rawValue] = audio.apiKey
        keys[vision.provider.rawValue] = vision.apiKey

        let storedSecurely = ModelSecretStore.writeAll(keys)

        var settingsToWrite = self
        if storedSecurely {
            settingsToWrite.audio.apiKey = ""
            settingsToWrite.vision.apiKey = ""
            settingsToWrite.savedKeys = nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settingsToWrite) {
            try? data.write(to: url)
        }
    }
    
    /// Reads the settings file. The keys live beside it and are folded in by
    /// `attachStoredKeys()`, which is cheap now that no Keychain is involved.
    public static func load(from url: URL) -> NotefySettings {
        guard let data = try? Data(contentsOf: url),
              var settings = try? JSONDecoder().decode(NotefySettings.self, from: data) else {
            // Return defaults if file doesn't exist
            let defaults = NotefySettings()
            defaults.save(to: url)
            return defaults
        }
        var keys = settings.savedKeys ?? [:]
        if !settings.audio.apiKey.isEmpty { keys["audio." + settings.audio.provider.rawValue] = settings.audio.apiKey }
        if !settings.vision.apiKey.isEmpty { keys[settings.vision.provider.rawValue] = settings.vision.apiKey }
        settings.savedKeys = keys
        settings.audio.apiKey = keys["audio." + settings.audio.provider.rawValue] ?? ""
        settings.vision.apiKey = keys[settings.vision.provider.rawValue] ?? ""
        return settings
    }

    /// Every key the app is holding, read in one pass.
    public static func storedKeys() -> [String: String] {
        ModelSecretStore.readAll()
    }

    /// Folds those keys in. A key already in memory wins — it is either what
    /// the user just typed or what was migrated out of the plaintext file.
    /// Returns true when anything actually changed.
    @discardableResult
    public mutating func attachStoredKeys(_ stored: [String: String]) -> Bool {
        var keys = savedKeys ?? [:]
        var changed = false
        for (account, value) in stored where !value.isEmpty {
            if (keys[account] ?? "").isEmpty {
                keys[account] = value
                changed = true
            }
        }
        guard changed else { return false }
        savedKeys = keys
        audio.apiKey = keys["audio." + audio.provider.rawValue] ?? audio.apiKey
        vision.apiKey = keys[vision.provider.rawValue] ?? vision.apiKey
        return true
    }
}
