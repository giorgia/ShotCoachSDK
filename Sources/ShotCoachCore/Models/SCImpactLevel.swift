import Foundation

/// Indicates how severely an issue affects the final shot quality.
public enum SCImpactLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}
