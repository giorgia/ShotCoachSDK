import Foundation

/// Errors that can be thrown by any SCCloudProvider implementation.
public enum SCCloudError: Error {
    case networkFailure
    case invalidResponse
    case decodingError
    case rateLimited
}
