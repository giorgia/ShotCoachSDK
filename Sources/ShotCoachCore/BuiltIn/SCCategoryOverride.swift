import Foundation

/// A customised wrapper around an `SCBuiltInCategory` produced by `.extending { }`.
/// Adds extra prompt context, required shots, and/or on-device rules on top of the
/// base category without forking the full config.
///
/// `SCCategoryOverride` is `Codable` so it can be persisted alongside session state.
/// **Note:** custom rules added via `addRule(_:)` are **not** persisted — they are
/// runtime-only. Re-apply them via `.extending { $0.addRule(...) }` after decoding.
///
/// There is no public designated initialiser by design; use
/// `SCBuiltInCategory.extending { }` as the only construction path.
/// Decoding (`JSONDecoder.decode(SCCategoryOverride.self, from:)`) works across
/// module boundaries because `init(from:)` is synthesised as `public`.
public struct SCCategoryOverride: SCCategoryConfig, Codable, Sendable {

    private let base:        SCBuiltInCategory
    private var extraPrompt: String
    private var extraShots:  [SCShotType]
    // extraRules are runtime-only (SCFrameRule is not Codable). They are dropped
    // during encoding and restored to [] on decoding; callers must re-apply them.
    private var extraRules:  [any SCFrameRule]

    // Internal — callers use SCBuiltInCategory.extending { } instead.
    init(base: SCBuiltInCategory) {
        self.base        = base
        self.extraPrompt = ""
        self.extraShots  = []
        self.extraRules  = []
    }

    // MARK: - Codable (manual — extraRules are not Codable)

    private enum CodingKeys: String, CodingKey {
        case base, extraPrompt, extraShots
    }

    public init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        base        = try c.decode(SCBuiltInCategory.self, forKey: .base)
        extraPrompt = try c.decode(String.self,            forKey: .extraPrompt)
        extraShots  = try c.decode([SCShotType].self,      forKey: .extraShots)
        extraRules  = []   // Re-apply via .extending { $0.addRule(...) } after decode.
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base,        forKey: .base)
        try c.encode(extraPrompt, forKey: .extraPrompt)
        try c.encode(extraShots,  forKey: .extraShots)
    }

    // MARK: - SCCategoryConfig

    public var categoryID:    String            { base.categoryID }
    public var displayName:   String            { base.displayName }
    public var requiredShots: [SCShotType]      { base.requiredShots + extraShots }
    public var onDeviceRules: [any SCFrameRule] { base.onDeviceRules + extraRules }

    /// Returns the base category's cloud prompt for `shot`, with any extra context
    /// appended via `appendPrompt(_:)` separated by a blank line.
    /// This is the stable API surface — the underlying prompt text may change in patch
    /// releases but the method signature will not.
    public func cloudPrompt(for shot: SCShotType) -> String {
        let basePrompt = base.cloudPrompt(for: shot)
        guard !extraPrompt.isEmpty else { return basePrompt }
        return basePrompt + "\n\nAdditional context: " + extraPrompt
    }

    // MARK: - Builder methods

    /// Appends `text` to the cloud prompt for every shot in this category.
    /// Multiple calls concatenate with a single space separator.
    public mutating func appendPrompt(_ text: String) {
        extraPrompt = extraPrompt.isEmpty ? text : extraPrompt + " " + text
    }

    /// Adds `shot` to the end of the required-shots list for this category.
    public mutating func addRequiredShot(_ shot: SCShotType) {
        extraShots.append(shot)
    }

    /// Adds a custom on-device rule to run alongside the category's built-in rules.
    /// - Note: Custom rules are **not** persisted when the override is encoded.
    ///   Re-apply them via `.extending { $0.addRule(...) }` after decoding a persisted value.
    public mutating func addRule(_ rule: any SCFrameRule) {
        extraRules.append(rule)
    }
}
