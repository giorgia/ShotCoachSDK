import Foundation

/// A customised wrapper around an `SCBuiltInCategory` produced by `.extending { }`.
/// Adds extra prompt context and/or required shots on top of the base category
/// without forking the full config.
///
/// `SCCategoryOverride` is a value type and `Codable`, so it can be persisted
/// alongside session state if needed.
public struct SCCategoryOverride: SCCategoryConfig, Codable, Sendable {

    private let base:        SCBuiltInCategory
    private var extraPrompt: String
    private var extraShots:  [SCShotType]

    // Internal — callers use SCBuiltInCategory.extending { } instead.
    init(base: SCBuiltInCategory) {
        self.base        = base
        self.extraPrompt = ""
        self.extraShots  = []
    }

    // MARK: - SCCategoryConfig

    public var categoryID:    String            { base.categoryID }
    public var displayName:   String            { base.displayName }
    public var requiredShots: [SCShotType]      { base.requiredShots + extraShots }
    public var onDeviceRules: [any SCFrameRule] { base.onDeviceRules }

    public func cloudPrompt(for shot: SCShotType) -> String {
        let basePrompt = base.cloudPrompt(for: shot)
        guard !extraPrompt.isEmpty else { return basePrompt }
        return basePrompt + "\n\nAdditional context: " + extraPrompt
    }

    // MARK: - Builder methods

    /// Appends `text` to the cloud prompt for every shot in this category.
    /// Calling this multiple times concatenates the additional context.
    public mutating func appendPrompt(_ text: String) {
        extraPrompt = extraPrompt.isEmpty ? text : extraPrompt + " " + text
    }

    /// Adds `shot` to the end of the required-shots list for this category.
    public mutating func addRequiredShot(_ shot: SCShotType) {
        extraShots.append(shot)
    }
}
