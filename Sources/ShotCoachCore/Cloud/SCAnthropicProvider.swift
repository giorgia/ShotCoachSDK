import Foundation

/// SCCloudProvider backed by Anthropic Claude (claude-sonnet-4-6).
/// The API key is held in memory only and is never logged, printed, or embedded in URLs.
public struct SCAnthropicProvider: SCCloudProvider, Sendable {

    private let apiKey: String

    /// - Parameters:
    ///   - apiKey: A valid Anthropic API key (starts with `sk-ant-`).
    ///     Persist it between sessions using `SCKeychainService`; pass the loaded value here.
    ///   - model: The Claude model ID to use. Defaults to `claude-sonnet-4-6`.
    ///     Override to pin a specific version or test with a different tier.
    public init(apiKey: String, model: String = "claude-sonnet-4-6") {
        self.apiKey = apiKey
        self.model  = model
    }

    // MARK: - SCCloudProvider

    public func analyze(photo: SCPhoto, prompt: String) async throws -> SCCloudResult {
        guard !apiKey.isEmpty else { throw SCCloudError.invalidAPIKey }
        let compressed = try scCompressImage(photo.imageData, maxPx: Self.maxImageDimension)
        let request = try buildRequest(base64Image: compressed.base64EncodedString(), prompt: prompt)
        return try await scPerformWithRetry(request, parse: parseResponse)
    }

    // MARK: - Private — networking

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let defaultModel = "claude-sonnet-4-6"
    private static let maxImageDimension = 1200

    private let model: String

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
        // Anthropic vision: image block + text block in the user message.
        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "system":     Self.systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type":       "base64",
                                "media_type": "image/jpeg",
                                "data":       base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod  = "POST"
        // apiKey is used as a header value — never logged or embedded in URLs.
        request.setValue(apiKey,              forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json",  forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Private — response parsing

    private struct AnthropicResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
    }

    private func parseResponse(_ data: Data) throws -> SCCloudResult {
        let apiResponse: AnthropicResponse
        do {
            apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw SCCloudError.jsonParsingFailed("Response envelope did not match expected structure")
        }

        guard let content = apiResponse.content.first(where: { $0.type == "text" })?.text else {
            throw SCCloudError.invalidResponse
        }

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
