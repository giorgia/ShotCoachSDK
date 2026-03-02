import Foundation

/// The output of a single SCFrameRule evaluation.
public struct SCRuleResult: Codable, Sendable {
    public let passed: Bool
    public let message: String
    public let severity: SCRuleSeverity
    /// Set by `SCShotClassifierRule` when it identifies the scene with sufficient
    /// confidence; `nil` for all other rules. The value is a `SCShotType.id` string
    /// that `SCFrameAnalyzer` resolves to a full `SCShotType` via the category's
    /// `requiredShots` list.
    public let detectedShotTypeID: String?

    public init(
        passed: Bool,
        message: String,
        severity: SCRuleSeverity,
        detectedShotTypeID: String? = nil
    ) {
        self.passed = passed
        self.message = message
        self.severity = severity
        self.detectedShotTypeID = detectedShotTypeID
    }
}
