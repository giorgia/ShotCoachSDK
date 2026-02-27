import Foundation

/// Aggregated result of running all SCFrameRule instances against one frame.
public struct SCFrameResult: Codable, Sendable {
    public let rules: [String: SCRuleResult]
    public let overallGuidance: String
    public let isReadyToCapture: Bool
    public let processingMs: Double

    public init(
        rules: [String: SCRuleResult],
        overallGuidance: String,
        isReadyToCapture: Bool,
        processingMs: Double
    ) {
        self.rules = rules
        self.overallGuidance = overallGuidance
        self.isReadyToCapture = isReadyToCapture
        self.processingMs = processingMs
    }
}
