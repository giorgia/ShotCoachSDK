import Foundation

/// Aggregated result of running all SCFrameRule instances against one frame.
public struct SCFrameResult: Codable, Sendable {
    public let rules: [String: SCRuleResult]
    public let overallGuidance: String
    public let isReadyToCapture: Bool
    public let processingMs: Double
    /// The scene type identified by `SCShotClassifierRule` in the current frame,
    /// or `nil` when the classifier confidence is below its threshold or no
    /// matching required shot exists in the active category.
    public let detectedShotType: SCShotType?

    public init(
        rules: [String: SCRuleResult],
        overallGuidance: String,
        isReadyToCapture: Bool,
        processingMs: Double,
        detectedShotType: SCShotType? = nil
    ) {
        self.rules = rules
        self.overallGuidance = overallGuidance
        self.isReadyToCapture = isReadyToCapture
        self.processingMs = processingMs
        self.detectedShotType = detectedShotType
    }
}
