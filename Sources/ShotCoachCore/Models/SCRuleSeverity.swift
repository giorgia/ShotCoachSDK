import Foundation

/// Severity level for a frame rule result.
public enum SCRuleSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}
