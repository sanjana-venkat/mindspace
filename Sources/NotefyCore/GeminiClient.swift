import Foundation

/// What went wrong with Gemini, in a form the interface can act on rather than
/// paste into the note. Google's error bodies are JSON and often carry the fix
/// inside them — a retired model names its replacement — so the useful parts
/// are pulled out here instead of being shown raw.
public struct GeminiFailure: LocalizedError, Equatable {
    public enum Kind: Equatable {
        /// The model is gone, renamed, or not available to this key.
        case retiredModel
        /// There is no key at all — nothing has gone wrong, the app simply
        /// hasn't been given one.
        case missingKey
        /// The key is present but malformed or rejected.
        case key
        /// Too many requests, or the free tier is exhausted.
        case rateLimit
        /// Anything else, including the network being down.
        case other
    }

    public let kind: Kind
    /// One plain sentence, safe to show in the interface.
    public let summary: String
    /// The model Google told us to use instead, when it told us.
    public let suggestedModel: String?
    /// The original message, for the details disclosure.
    public let detail: String

    public var errorDescription: String? { summary }

    public init(kind: Kind, summary: String, suggestedModel: String? = nil, detail: String = "") {
        self.kind = kind
        self.summary = summary
        self.suggestedModel = suggestedModel
        self.detail = detail
    }
}

/// Thin wrapper around Google's Generative Language API (Gemini). Used for both audio
/// transcription and multimodal (image + text) note synthesis with a single API key —
/// one Gemini model can handle everything Notefy needs from a cloud provider.
public class GeminiClient {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    /// Where Gemini is now. Google retires model names on a schedule and
    /// returns a 404 naming the replacement, so this is a starting point
    /// rather than a fixed truth — `availableModels` asks the key itself.
    public static let fallbackModel = "gemini-3.8-flash"

    private let apiKey: String
    private let model: String
    /// Called with the model name that actually worked, when a request had to
    /// fall forward from a retired one. Lets the app save the fix.
    public var didAdoptModel: ((String) -> Void)?

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? GeminiClient.fallbackModel : model
    }

    public func transcribe(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let data = try? Data(contentsOf: audioURL) else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio file"])))
            return
        }
        let mimeType = audioMimeType(for: audioURL)
        let payload: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": "Transcribe this audio recording verbatim. Return only the transcript text — no commentary, no timestamps, no speaker labels unless multiple distinct speakers are clearly audible."],
                    ["inline_data": ["mime_type": mimeType, "data": data.base64EncodedString()]]
                ]
            ]]
        ]
        send(payload: payload, completion: completion)
    }

    /// Synthesizes a note from real screenshots + the user's own thoughts, using Gemini's
    /// multimodal chat in one combined request. Mirrors `VisionClient.generateMentalNote`.
    public func generateMentalNote(
        captures: [VisionClient.MentalNoteCapture],
        systemPrompt: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !captures.isEmpty else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "No captures to synthesize"])))
            return
        }

        var parts: [[String: Any]] = []
        for (index, capture) in captures.enumerated() {
            var text = "Capture \(index + 1) — Source: \(capture.sourceLabel)\n"
            if let sourceURL = capture.sourceURL { text += "Source URL: \(sourceURL)\n" }
            if let thought = capture.thought, !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text += "Thought: \(thought)\n"
            }
            parts.append(["text": text])
            if let image = capture.imageBase64 {
                parts.append(["inline_data": ["mime_type": "image/png", "data": image]])
            }
        }
        parts.append(["text": "Write the note tying these captures together, following the required structure exactly."])

        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": parts]]
        ]
        send(payload: payload, completion: completion)
    }

    /// Text-only note generation (no real screenshots available) — same structured-prompt
    /// contract as `generateMentalNote`, just without image parts.
    public func generateNote(
        systemPrompt: String,
        context: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": String(context.prefix(100_000))]]]]
        ]
        send(payload: payload, completion: completion)
    }

    private func audioMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mp3"
        case "m4a", "mp4": return "audio/mp4"
        default: return "audio/aac"
        }
    }

    private func send(payload: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        send(payload: payload, model: model, allowFallForward: true, completion: completion)
    }

    /// One attempt. If Gemini answers "that model is retired, use this one" the
    /// request is made again with the name it gave us, and the app is told so
    /// it can save the change — a note should not fail over a renamed model.
    private func send(
        payload: [String: Any],
        model: String,
        allowFallForward: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !apiKey.isEmpty else {
            completion(.failure(GeminiFailure(kind: .missingKey, summary: "No API key detected.")))
            return
        }
        guard let url = URL(string: "\(Self.baseURL)/\(model):generateContent?key=\(apiKey)") else {
            completion(.failure(GeminiFailure(
                kind: .retiredModel,
                summary: "“\(model)” isn't a usable model name.")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(GeminiFailure(
                    kind: .other,
                    summary: "Couldn't reach Gemini: \(error.localizedDescription)",
                    detail: error.localizedDescription)))
                return
            }
            guard let data = data else {
                completion(.failure(GeminiFailure(kind: .other, summary: "Gemini sent an empty reply.")))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let failure = Self.failure(from: data, status: http.statusCode, model: model)
                // The fix is in the error: try once more with the model Google
                // named, rather than handing the person a JSON blob.
                if allowFallForward, let next = failure.suggestedModel, next != model, let self {
                    self.send(payload: payload, model: next, allowFallForward: false) { result in
                        if case .success = result { self.didAdoptModel?(next) }
                        completion(result)
                    }
                    return
                }
                completion(.failure(failure))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(GeminiFailure(kind: .other, summary: "Gemini's reply wasn't readable.")))
                return
            }
            if let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first,
               let content = first["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty {
                    completion(.success(text))
                    return
                }
            }
            if let feedback = json["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
                completion(.failure(GeminiFailure(
                    kind: .other,
                    summary: "Gemini declined this note (\(reason.lowercased())).",
                    detail: reason)))
                return
            }
            completion(.failure(GeminiFailure(kind: .other, summary: "Gemini returned nothing usable.")))
        }.resume()
    }

    /// Turns Google's error JSON into something worth reading.
    static func failure(from data: Data, status: Int, model: String) -> GeminiFailure {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = (error?["message"] as? String) ?? raw

        switch status {
        case 400 where message.localizedCaseInsensitiveContains("api key"), 401, 403:
            return GeminiFailure(
                kind: .key,
                summary: "Gemini rejected that API key.",
                detail: message)
        case 404:
            return GeminiFailure(
                kind: .retiredModel,
                summary: "Google has retired “\(model)”.",
                suggestedModel: recommendedModel(in: message, excluding: model),
                detail: message)
        case 429:
            return GeminiFailure(
                kind: .rateLimit,
                summary: "This Gemini key is out of quota for now.",
                detail: message)
        default:
            return GeminiFailure(
                kind: .other,
                summary: "Gemini couldn't do it (error \(status)).",
                detail: message)
        }
    }

    /// Retirement notices name their replacement — "use models/gemini-3.6-flash".
    static func recommendedModel(in message: String, excluding current: String) -> String? {
        let pattern = "models/([A-Za-z0-9][A-Za-z0-9._-]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..., in: message)
        let names = regex.matches(in: message, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: message) else { return nil }
            return String(message[r])
        }
        return names.first { $0 != current }
    }

    /// What this key can actually call today. The picker is filled from here so
    /// a retirement is a refresh rather than an app update.
    public static func availableModels(apiKey: String, completion: @escaping (Result<[String], Error>) -> Void) {
        guard !apiKey.isEmpty, let url = URL(string: "\(baseURL)?key=\(apiKey)&pageSize=200") else {
            completion(.failure(GeminiFailure(kind: .key, summary: "Add a Gemini API key first.")))
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(GeminiFailure(kind: .other, summary: error.localizedDescription)))
                return
            }
            guard let data = data else {
                completion(.failure(GeminiFailure(kind: .other, summary: "Gemini sent an empty reply.")))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(failure(from: data, status: http.statusCode, model: "")))
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let models = (json?["models"] as? [[String: Any]]) ?? []
            let usable = models.compactMap { entry -> String? in
                guard let name = entry["name"] as? String else { return nil }
                let methods = (entry["supportedGenerationMethods"] as? [String]) ?? []
                guard methods.isEmpty || methods.contains("generateContent") else { return nil }
                let short = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                // Image, video, music, audio and embedding models can't write
                // a note — Lyria, the banana image models, Veo and the rest.
                guard ProviderCatalog.isWorthOffering(short) else { return nil }
                return short
            }
            completion(.success(usable.sorted().reversed()))
        }.resume()
    }
}
