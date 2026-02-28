import Foundation

/// Errors that can be thrown by any SCCloudProvider implementation.
public enum SCCloudError: Error, Sendable {
    /// No cloud provider has been configured for this session.
    case notConfigured
    case networkFailure
    case invalidResponse
    case decodingError
    case rateLimited
}
