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
