import Foundation

/// Thin wrapper around Google's Generative Language API (Gemini). Used for both audio
/// transcription and multimodal (image + text) note synthesis with a single API key —
/// one Gemini model can handle everything Notefy needs from a cloud provider.
public class GeminiClient {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    private let apiKey: String
    private let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? "gemini-2.5-flash" : model
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
        guard !apiKey.isEmpty else {
            completion(.failure(NSError(domain: "Notefy", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is empty"])))
            return
        }
        guard let url = URL(string: "\(Self.baseURL)/\(model):generateContent?key=\(apiKey)") else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini model name"])))
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
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data from Gemini"])))
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "unknown error"
                completion(.failure(NSError(domain: "Notefy", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Gemini error: \(bodyText.prefix(300))"])))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Gemini response"])))
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
                completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Gemini blocked the request: \(reason)"])))
                return
            }
            completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Gemini returned no usable content"])))
        }.resume()
    }
}
