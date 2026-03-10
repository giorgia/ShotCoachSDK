import Foundation

/// Errors that can be thrown by any SCCloudProvider implementation.
public enum SCCloudError: Error, Codable, Sendable {
    /// No cloud provider has been configured for this session.
    case notConfigured
    /// The API key was rejected by the cloud service (HTTP 401/403).
    case invalidAPIKey
    /// The cloud service is rate-limiting requests (HTTP 429).
    case rateLimited
    /// A network-level failure occurred; the associated value carries a description.
    case networkFailure(String)
    /// The HTTP response was unexpected (non-2xx outside handled codes).
    case invalidResponse
    /// The model returned content that could not be parsed as SCCloudResult JSON.
    case jsonParsingFailed(String)
    /// The image data exceeds the provider's size limit after compression.
    case imageTooLarge
}

extension SCCloudError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No cloud provider configured."
        case .invalidAPIKey:
            return "Invalid API key — check your OpenAI key in Settings."
        case .rateLimited:
            return "OpenAI rate limit reached. Wait a moment and try again."
        case .networkFailure(let detail):
            return "Network error: \(detail)"
        case .invalidResponse:
            return "Unexpected response from OpenAI."
        case .jsonParsingFailed(let detail):
            return "Could not parse AI response: \(detail)"
        case .imageTooLarge:
            return "Image is too large to send. Try a lower-resolution photo."
        }
    }
}
