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

        switch config.provider {
        case .local: analyzeViaOllama(base64Image: base64String, completion: completion)
        case .api: analyzeViaCloudAPI(base64Image: base64String, completion: completion)
        case .gemini:
            geminiClient.generateMentalNote(
                captures: [MentalNoteCapture(sourceLabel: "Screen capture", thought: nil, imageBase64: base64String)],
                systemPrompt: "Describe this screen capture in 2-3 sentences: what app or site it's from and the key information visible. Plain prose only.",
                completion: completion
            )
        }
    }

    /// Uses the configured model for text-only note generation given a fully-formed
    /// system prompt (see `AppState.systemPrompt(for:)`) — used when there are no real
    /// screenshots to synthesize from.
    public func generateNote(
        systemPrompt: String,
        context: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        switch config.provider {
        case .local:
            sendOllama(messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": String(context.prefix(100_000))]
            ], completion: completion)
        case .api:
            sendCloud(messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": String(context.prefix(100_000))]
            ], completion: completion)
        case .gemini:
            geminiClient.generateNote(systemPrompt: systemPrompt, context: context, completion: completion)
        }
    }

    private var geminiClient: GeminiClient {
        GeminiClient(apiKey: config.apiKey, model: config.modelName)
    }

    /// One capture fed into `generateMentalNote`: what the user was looking at (with its
    /// source) and, optionally, the screenshot itself plus any thought they left about it.
    public struct MentalNoteCapture {
        public let sourceLabel: String
        public let thought: String?
        public let imageBase64: String?

        public init(sourceLabel: String, thought: String?, imageBase64: String?) {
            self.sourceLabel = sourceLabel
            self.thought = thought
            self.imageBase64 = imageBase64
        }
    }

    /// Synthesizes a single note from real screenshots + the user's own thoughts, using a
    /// multimodal model in one combined request. `systemPrompt` carries the template's
    /// exact required structure (see `AppState.systemPrompt(for:)`). Works with any provider.
    public func generateMentalNote(
        captures: [MentalNoteCapture],
        systemPrompt: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !captures.isEmpty else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "No captures to synthesize"])))
            return
        }

        if config.provider == .gemini {
            geminiClient.generateMentalNote(captures: captures, systemPrompt: systemPrompt, completion: completion)
            return
        }

        var userText = ""
        var images: [String] = []
        for (index, capture) in captures.enumerated() {
            userText += "Capture \(index + 1) — Source: \(capture.sourceLabel)\n"
            if let thought = capture.thought, !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userText += "Thought: \(thought)\n"
            }
            if let image = capture.imageBase64 {
                images.append(image)
            } else {
                userText += "(No screenshot for this capture — text only.)\n"
            }
            userText += "\n"
        }
        userText += "Write the note tying these captures together, following the required structure exactly."

        if config.provider == .api {
            var content: [[String: Any]] = [["type": "text", "text": userText]]
            for image in images {
                content.append(["type": "image_url", "image_url": ["url": "data:image/png;base64,\(image)"]])
            }
            sendCloud(messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": content]
            ], completion: completion)
            return
        }

        var userMessage: [String: Any] = ["role": "user", "content": userText]
        if !images.isEmpty { userMessage["images"] = images }

        // Each image costs roughly 4-4.5k vision tokens once encoded; size the context
        // window to fit them all, capped so we don't request more than the model supports.
        let numCtx = min(32768, 3072 + images.count * 4608)
        // Vision + "thinking" generation is slow on-device; give it real room, scaled by
        // how many images there are, rather than the default short HTTP timeout.
        let timeout = min(600.0, 75.0 + Double(images.count) * 90.0)

        sendOllama(
            messages: [
                ["role": "system", "content": systemPrompt],
                userMessage
            ],
            options: ["num_ctx": numCtx],
            think: false,
            timeout: timeout,
            completion: completion
        )
    }
    
    // Call local Ollama vision endpoint
    private func analyzeViaOllama(base64Image: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendOllama(messages: [[
            "role": "user",
            "content": "Describe this screen capture. Extract visible text and the key information the user is reading.",
            "images": [base64Image]
        ]], completion: completion)
    }

    private func sendOllama(
        messages: [[String: Any]],
        options: [String: Any]? = nil,
        think: Bool? = nil,
        timeout: TimeInterval = 120,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: config.apiURL) else {
            completion(.failure(NSError(domain: "Notefy", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama API URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["model": config.modelName, "messages": messages, "stream": false]
        if let options { payload["options"] = options }
        if let think { payload["think"] = think }
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
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data from local Ollama model"])))
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                completion(.success(content))
            } else {
                completion(.failure(NSError(domain: "Notefy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse local model output"])))
            }
        }.resume()
    }
    
    // Call standard OpenAI-compatible cloud vision endpoint (OpenAI, OpenRouter, Custom VLM)
    private func analyzeViaCloudAPI(base64Image: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendCloud(messages: [[
            "role": "user",
            "content": [
                ["type": "text", "text": "Describe this screen and extract visible text and key information."],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64Image)"]]
            ]
        ]], completion: completion)
    }

    private func sendCloud(
        messages: [[String: Any]],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
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
        
        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": messages
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
