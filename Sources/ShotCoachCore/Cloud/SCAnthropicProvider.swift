import Foundation
import CoreGraphics
import ImageIO

/// SCCloudProvider backed by Anthropic Claude (claude-sonnet-4-6).
/// The API key is held in memory only and is never logged, printed, or embedded in URLs.
public struct SCAnthropicProvider: SCCloudProvider, Sendable {

    private let apiKey: String

    /// - Parameter apiKey: A valid Anthropic API key (starts with `sk-ant-`).
    ///   Persist it between sessions using `SCKeychainService`; pass the loaded value here.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - SCCloudProvider

    public func analyze(photo: SCPhoto, prompt: String) async throws -> SCCloudResult {
        guard !apiKey.isEmpty else { throw SCCloudError.invalidAPIKey }
        let compressed = try compressImage(photo.imageData)
        let base64 = compressed.base64EncodedString()
        let request = try buildRequest(base64Image: base64, prompt: prompt)
        return try await performWithRetry(request)
    }

    // MARK: - Private — networking

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model    = "claude-sonnet-4-6"
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
        // Anthropic vision: image block + text block in the user message.
        let body: [String: Any] = [
            "model":      Self.model,
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
        request.setValue(apiKey,           forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",     forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func performWithRetry(_ request: URLRequest) async throws -> SCCloudResult {
        var lastError: SCCloudError = .networkFailure("No attempts made")
        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            do {
                return try await performRequest(request)
            } catch let e as SCCloudError where isRetryable(e) {
                lastError = e
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                }
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func isRetryable(_ error: SCCloudError) -> Bool {
        switch error {
        case .rateLimited, .networkFailure: return true
        default:                            return false
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> SCCloudResult {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SCCloudError.networkFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SCCloudError.networkFailure("Non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            return try parseResponse(data)
        case 401, 403:
            throw SCCloudError.invalidAPIKey
        case 413:
            throw SCCloudError.imageTooLarge
        case 429:
            throw SCCloudError.rateLimited
        case 500...599:
            throw SCCloudError.networkFailure("Server error \(http.statusCode)")
        default:
            throw SCCloudError.networkFailure("Unexpected HTTP \(http.statusCode)")
        }
    }

    // MARK: - Private — response parsing

    private struct AnthropicResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
    }

    private struct ParsedResult: Decodable {
        struct Issue: Decodable {
            let title: String
            let detail: String
            let impact: SCImpactLevel
        }
        struct Recommendation: Decodable {
            let text: String
            let priority: Int
        }
        let score: Int
        let shotType: String
        let issues: [Issue]
        let recommendations: [Recommendation]
    }

    private func parseResponse(_ data: Data) throws -> SCCloudResult {
        let decoder = JSONDecoder()

        let apiResponse: AnthropicResponse
        do {
            apiResponse = try decoder.decode(AnthropicResponse.self, from: data)
        } catch {
            throw SCCloudError.jsonParsingFailed("Unexpected response format: \(error.localizedDescription)")
        }

        guard let content = apiResponse.content.first(where: { $0.type == "text" })?.text else {
            throw SCCloudError.invalidResponse
        }

        let stripped = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = stripped.data(using: .utf8) else {
            throw SCCloudError.jsonParsingFailed("Could not encode content as UTF-8")
        }

        let parsed: ParsedResult
        do {
            parsed = try decoder.decode(ParsedResult.self, from: jsonData)
        } catch {
            throw SCCloudError.jsonParsingFailed(error.localizedDescription)
        }

        return SCCloudResult(
            score: min(100, max(0, parsed.score)),
            issues: parsed.issues.map { SCIssue(title: $0.title, detail: $0.detail, impact: $0.impact) },
            shotType: parsed.shotType,
            recommendations: parsed.recommendations.map { SCRecommendation(text: $0.text, priority: $0.priority) },
            rawJSON: content
        )
    }

    // MARK: - Private — image compression (identical budget to SCOpenAIProvider)

    private func compressImage(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SCCloudError.invalidResponse
        }

        let scaled = try resizeIfNeeded(cgImage, maxPx: Self.maxImageDimension)
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else {
            throw SCCloudError.imageTooLarge
        }
        CGImageDestinationAddImage(
            dest, scaled,
            [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { throw SCCloudError.imageTooLarge }
        return output as Data
    }

    private func resizeIfNeeded(_ image: CGImage, maxPx: Int) throws -> CGImage {
        let w = image.width, h = image.height
        guard max(w, h) > maxPx else { return image }
        let scale = Double(maxPx) / Double(max(w, h))
        let newW  = max(1, Int(Double(w) * scale))
        let newH  = max(1, Int(Double(h) * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SCCloudError.invalidResponse }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let resized = ctx.makeImage() else { throw SCCloudError.invalidResponse }
        return resized
    }
}
