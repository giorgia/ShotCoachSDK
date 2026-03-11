import Foundation
import CoreGraphics
import ImageIO

// MARK: - Shared image compression

/// Compresses `data` to JPEG quality 0.7, capping the longest side at `maxPx` pixels.
/// Uses only CoreGraphics + ImageIO — no UIKit or AppKit.
func scCompressImage(_ data: Data, maxPx: Int) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw SCCloudError.invalidResponse
    }

    let scaled = try scResizeIfNeeded(cgImage, maxPx: maxPx)
    let output = NSMutableData()
    // "public.jpeg" is the stable JPEG UTI — no MobileCoreServices import needed.
    guard let dest = CGImageDestinationCreateWithData(
        output as CFMutableData, "public.jpeg" as CFString, 1, nil
    ) else {
        throw SCCloudError.invalidResponse
    }
    CGImageDestinationAddImage(
        dest, scaled,
        [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
    )
    guard CGImageDestinationFinalize(dest) else { throw SCCloudError.invalidResponse }
    return output as Data
}

func scResizeIfNeeded(_ image: CGImage, maxPx: Int) throws -> CGImage {
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

// MARK: - Shared networking

/// Executes `request` with exponential back-off retry (1 s, 2 s) on retryable errors.
/// `parse` is called on a successful 200 response.
func scPerformWithRetry(
    _ request: URLRequest,
    parse: (Data) throws -> SCCloudResult
) async throws -> SCCloudResult {
    var lastError: SCCloudError = .networkFailure("No attempts made")
    let maxAttempts = 3
    for attempt in 0..<maxAttempts {
        do {
            return try await scPerformRequest(request, parse: parse)
        } catch let e as SCCloudError where scIsRetryable(e) {
            lastError = e
            // Skip sleep after the final attempt.
            if attempt < maxAttempts - 1 {
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            }
        } catch {
            throw error
        }
    }
    throw lastError
}

private func scIsRetryable(_ error: SCCloudError) -> Bool {
    switch error {
    case .rateLimited, .networkFailure: return true
    default:                            return false
    }
}

private func scPerformRequest(
    _ request: URLRequest,
    parse: (Data) throws -> SCCloudResult
) async throws -> SCCloudResult {
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
    case 200:         return try parse(data)
    case 401, 403:    throw SCCloudError.invalidAPIKey
    case 413:         throw SCCloudError.imageTooLarge
    case 429:         throw SCCloudError.rateLimited
    case 500...599:   throw SCCloudError.networkFailure("Server error \(http.statusCode)")
    default:          throw SCCloudError.networkFailure("Unexpected HTTP \(http.statusCode)")
    }
}

// MARK: - Shared response parsing

/// The JSON structure both providers expect from the model.
struct SCParsedCloudResult: Decodable {
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

/// Strips optional markdown code fences and returns UTF-8 encoded JSON data.
func scExtractJSONData(from content: String) throws -> Data {
    let stripped = content
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = stripped.data(using: .utf8) else {
        throw SCCloudError.jsonParsingFailed("Could not encode content as UTF-8")
    }
    return data
}

/// Builds an `SCCloudResult` from the shared parsed structure.
func scBuildCloudResult(from parsed: SCParsedCloudResult, rawJSON: String) -> SCCloudResult {
    SCCloudResult(
        score: min(100, max(0, parsed.score)),
        issues: parsed.issues.map { SCIssue(title: $0.title, detail: $0.detail, impact: $0.impact) },
        shotType: parsed.shotType,
        recommendations: parsed.recommendations.map { SCRecommendation(text: $0.text, priority: $0.priority) },
        rawJSON: rawJSON
    )
}
