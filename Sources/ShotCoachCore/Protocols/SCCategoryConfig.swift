import Foundation

/// Defines a photography category: required shots, on-device rules, and cloud prompt.
/// Adopt this protocol to create a fully custom category.
public protocol SCCategoryConfig: Sendable {
    /// Stable identifier used for analytics and serialisation. Default: "custom".
    var categoryID: String { get }
    /// Human-readable name shown in the UI. Default: "Custom".
    var displayName: String { get }
    /// Ordered list of shots the session must capture. Default: empty.
    var requiredShots: [SCShotType] { get }
    /// On-device rules evaluated every 1.5 s against the live viewfinder. Default: empty.
    var onDeviceRules: [any SCFrameRule] { get }
    /// Returns the GPT-4o prompt for a given shot type.
    func cloudPrompt(for shot: SCShotType) -> String
}

public extension SCCategoryConfig {
    var categoryID: String { "custom" }
    var displayName: String { "Custom" }
    var requiredShots: [SCShotType] { [] }
    var onDeviceRules: [any SCFrameRule] { [] }
    func cloudPrompt(for shot: SCShotType) -> String { "" }
}
