import Foundation

/// SCCloudProvider backed by OpenAI GPT-4o.
/// The API key is held in memory only and is never logged, printed, or embedded in URLs.
public struct SCOpenAIProvider: SCCloudProvider, Sendable {

    private let apiKey: String

    /// - Parameter apiKey: A valid OpenAI API key. Persist it between sessions using
    ///   `SCKeychainService.save(key:value:)`; pass the value loaded from Keychain here
    ///   at runtime. The key is held in memory for this provider's lifetime only.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - SCCloudProvider

    public func analyze(photo: SCPhoto, prompt: String) async throws -> SCCloudResult {
        // Fast-fail before any CPU or network work — avoids a 1-3 s round-trip when
        // the key is deliberately empty (e.g. ShotCameraView defers cloud to batch).
        guard !apiKey.isEmpty else { throw SCCloudError.invalidAPIKey }
        let compressed = try scCompressImage(photo.imageData, maxPx: Self.maxImageDimension)
        let request = try buildRequest(base64Image: compressed.base64EncodedString(), prompt: prompt)
        return try await scPerformWithRetry(request, parse: parseResponse)
    }

    // MARK: - Private — networking

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let maxImageDimension = 1200

    private static let systemPrompt = """
        You are a professional photography coach AI. Analyze the provided image and \
        respond with valid JSON only — no markdown, no code fences. \
        The JSON must have exactly these top-level fields:
        • score: integer 0–100 (overall shot quality)
        • shotType: string (e.g. "wide", "close-up", "detail")
        • issues: array of {title: string, detail: string, impact: "low"|"medium"|"high"}
        • recommendations: array of {text: string, priority: integer 1–5}
        """

    private func buildRequest(base64Image: String, prompt: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": [
                        // apiKey is used only in the Authorization header below,
                        // never appended to this URL.
                        "url": "data:image/jpeg;base64,\(base64Image)"
                    ]]
                ]]
            ],
            "max_tokens": 1000,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        // apiKey is used as a Bearer token header value — never logged or in URLs.
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Private — response parsing

    private struct OpenAIResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    private func parseResponse(_ data: Data) throws -> SCCloudResult {
        let apiResponse: OpenAIResponse
        do {
            apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw SCCloudError.jsonParsingFailed("Unexpected response format: \(error.localizedDescription)")
        }

        guard let content = apiResponse.choices.first?.message.content else {
            throw SCCloudError.invalidResponse
        }

        // `response_format: json_object` should prevent code fences, but strip them
        // defensively in case a proxy or model variant wraps the JSON in markdown.
        let jsonData = try scExtractJSONData(from: content)
        let parsed: SCParsedCloudResult
        do {
            parsed = try JSONDecoder().decode(SCParsedCloudResult.self, from: jsonData)
        } catch {
            throw SCCloudError.jsonParsingFailed(error.localizedDescription)
        }

        return scBuildCloudResult(from: parsed, rawJSON: content)
    }
}
