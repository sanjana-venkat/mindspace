import Foundation

/// What each provider can actually run, asked of the provider itself.
///
/// A list baked into the app is out of date the day after it ships — the
/// settings offered gpt-4o long after it stopped being the thing anyone would
/// choose. These ask, and fall back to a short static list only when there is
/// nothing to ask with.
public enum ProviderCatalog {
    /// The models pulled onto this Mac. Ollama will run anything you have
    /// pulled and nothing you haven't, so this is the honest list — and the
    /// reason the local provider needs no curated menu of its own.
    public static func ollamaModels(endpoint: String) async -> [String] {
        // The configured endpoint points at /api/chat; the catalogue is /api/tags.
        guard let chat = URL(string: endpoint.isEmpty ? "http://localhost:11434/api/chat" : endpoint),
              let host = chat.host else { return [] }
        var tags = URLComponents()
        tags.scheme = chat.scheme ?? "http"
        tags.host = host
        tags.port = chat.port
        tags.path = "/api/tags"
        guard let url = tags.url else { return [] }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// What an OpenAI key can call, minus everything that cannot read a
    /// screenshot or write a note: images, video, audio, embeddings, moderation.
    public static func openAIModels(apiKey: String) async -> [String] {
        guard !apiKey.isEmpty, let url = URL(string: "https://api.openai.com/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models
            .compactMap { $0["id"] as? String }
            .filter { isWorthOffering($0) }
            .sorted()
            .reversed()
    }

    /// What an Anthropic key can call.
    public static func anthropicModels(apiKey: String) async -> [String] {
        guard !apiKey.isEmpty, let url = URL(string: "https://api.anthropic.com/v1/models?limit=100") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models
            .compactMap { $0["id"] as? String }
            .filter { isWorthOffering($0) }
            .sorted()
            .reversed()
    }

    /// Model names that have no business in a note-writing app.
    static let excluded = [
        "image", "vision-preview", "dall-e", "sora", "video", "veo", "banana",
        "lyria", "music", "audio", "tts", "whisper", "transcribe", "realtime",
        "embedding", "embed", "moderation", "rerank", "omni-moderation", "aqa",
        "guard", "search-preview", "computer-use",
    ]

    public static func isWorthOffering(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return !excluded.contains { lowered.contains($0) }
    }
}
