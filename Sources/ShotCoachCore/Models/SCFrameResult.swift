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
    /// Human-readable label of the highest-confidence Vision result in the current frame
    /// (e.g. "Kitchen", "Bedroom", "Car"). Populated whenever any observation reaches
    /// 0.10+ confidence, regardless of taxonomy matching or `confidenceThreshold`.
    /// Useful for displaying what the camera sees even when no shot-type match is found.
    public let topSceneLabel: String?

    public init(
        rules: [String: SCRuleResult],
        overallGuidance: String,
        isReadyToCapture: Bool,
        processingMs: Double,
        detectedShotType: SCShotType? = nil,
        topSceneLabel: String? = nil
    ) {
        self.rules = rules
        self.overallGuidance = overallGuidance
        self.isReadyToCapture = isReadyToCapture
        self.processingMs = processingMs
        self.detectedShotType = detectedShotType
        self.topSceneLabel = topSceneLabel
    }
}
