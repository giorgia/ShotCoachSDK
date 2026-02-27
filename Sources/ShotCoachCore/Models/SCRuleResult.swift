import Foundation

/// The output of a single SCFrameRule evaluation.
public struct SCRuleResult: Codable, Sendable {
    public let passed: Bool
    public let message: String
    public let severity: SCRuleSeverity

    public init(passed: Bool, message: String, severity: SCRuleSeverity) {
        self.passed = passed
        self.message = message
        self.severity = severity
    }
}
