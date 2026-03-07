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
    /// Numeric quality score on a 0–10 scale. Currently set by `SCInstagrammabilityRule`
    /// and `SCAestheticRule`; `nil` for all other rules.
    public let numericScore: Double?

    public init(
        passed: Bool,
        message: String,
        severity: SCRuleSeverity,
        detectedShotTypeID: String? = nil,
        numericScore: Double? = nil
    ) {
        self.passed = passed
        self.message = message
        self.severity = severity
        self.detectedShotTypeID = detectedShotTypeID
        self.numericScore = numericScore
    }
}
