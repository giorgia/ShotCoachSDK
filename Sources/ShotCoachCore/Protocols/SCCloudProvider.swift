import Foundation

/// Sends a captured image to a cloud AI service for deep post-capture analysis.
public protocol SCCloudProvider: Sendable {
    /// Analyses a captured photo using the supplied prompt and returns a structured result.
    /// - Throws: `SCCloudError` on network, decoding, or rate-limit failures.
    func analyze(photo: SCPhoto, prompt: String) async throws -> SCCloudResult
}

public extension SCCloudProvider {
    func analyze(photo: SCPhoto, prompt: String) async throws -> SCCloudResult {
        throw SCCloudError.networkFailure
    }
}
