import Foundation
import CoreGraphics
import ImageIO

/// SCCloudProvider backed by OpenAI GPT-4o.
/// The API key is held in memory only and is never logged, printed, or embedded in URLs.
public struct SCOpenAIProvider: SCCloudProvider {

    private let apiKey: String

    /// - Parameter apiKey: A valid OpenAI API key. Store it in `SCKeychainService`
    ///   between sessions; pass the loaded value here at runtime.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - SCCloudProvider

    public func analyze(photo: SCPhoto, prompt: String) async throws -> SCCloudResult {
        let compressed = try compressImage(photo.imageData)
        let base64 = compressed.base64EncodedString()
        let request = try buildRequest(base64Image: base64, prompt: prompt)
        return try await performWithRetry(request)
    }

    // MARK: - Private — networking

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

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
                        "url": "data:image/jpeg;base64,\(base64Image)"
                    ]]
                ]]
            ],
            "max_tokens": 1000,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        // apiKey is used here as a header value, not logged or appended to any URL.
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Performs `request`, retrying up to 3 times with exponential backoff on 429 / 5xx.
    private func performWithRetry(_ request: URLRequest) async throws -> SCCloudResult {
        var lastError: SCCloudError = .networkFailure("No attempts made")
        for attempt in 0..<3 {
            do {
                return try await performRequest(request)
            } catch let e as SCCloudError where isRetryable(e) {
                lastError = e
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
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
        case 429:
            throw SCCloudError.rateLimited
        case 500...:
            throw SCCloudError.networkFailure("Server error \(http.statusCode)")
        default:
            throw SCCloudError.invalidResponse
        }
    }

    // MARK: - Private — response parsing

    private struct OpenAIResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
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

        let apiResponse: OpenAIResponse
        do {
            apiResponse = try decoder.decode(OpenAIResponse.self, from: data)
        } catch {
            throw SCCloudError.invalidResponse
        }

        guard let content = apiResponse.choices.first?.message.content else {
            throw SCCloudError.invalidResponse
        }

        // Strip optional markdown code fences the model may wrap around JSON.
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
            score: parsed.score,
            issues: parsed.issues.map { SCIssue(title: $0.title, detail: $0.detail, impact: $0.impact) },
            shotType: parsed.shotType,
            recommendations: parsed.recommendations.map { SCRecommendation(text: $0.text, priority: $0.priority) },
            rawJSON: content
        )
    }

    // MARK: - Private — image compression

    /// Compresses `data` to JPEG quality 0.7, capping the longest side at 1200 px.
    /// Uses only CoreGraphics + ImageIO — no UIKit or AppKit imports.
    private func compressImage(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SCCloudError.invalidResponse
        }

        let scaled = try resizeIfNeeded(cgImage, maxPx: 1200)

        let output = NSMutableData()
        // "public.jpeg" is the stable JPEG UTI — no MobileCoreServices import needed.
        guard let dest = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else {
            throw SCCloudError.imageTooLarge
        }

        CGImageDestinationAddImage(
            dest, scaled,
            [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else {
            throw SCCloudError.imageTooLarge
        }
        return output as Data
    }

    private func resizeIfNeeded(_ image: CGImage, maxPx: Int) throws -> CGImage {
        let w = image.width, h = image.height
        guard max(w, h) > maxPx else { return image }

        let scale  = Double(maxPx) / Double(max(w, h))
        let newW   = max(1, Int(Double(w) * scale))
        let newH   = max(1, Int(Double(h) * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SCCloudError.invalidResponse
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let resized = ctx.makeImage() else {
            throw SCCloudError.invalidResponse
        }
        return resized
    }
}
