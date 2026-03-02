import Foundation

/// A required shot within a photography session (e.g. "Front Exterior", "Kitchen").
public struct SCShotType: Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    /// Vision taxonomy substrings used by `SCShotClassifierRule` to recognise this shot type.
    ///
    /// Each string is checked against `VNClassificationObservation.identifier` using
    /// `.contains()`. The classifier sums the confidences of all matching observations;
    /// the shot with the highest cumulative score wins (score ≥ `confidenceThreshold`).
    ///
    /// Provide as many domain-specific synonyms as possible — breadth beats precision here
    /// because Vision's taxonomy is generic and hierarchical.
    public let classificationHints: [String]

    public init(id: String, displayName: String, classificationHints: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.classificationHints = classificationHints
    }

    // MARK: - Codable (backward-compatible: classificationHints defaults to [] when absent)

    enum CodingKeys: String, CodingKey {
        case id, displayName, classificationHints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        classificationHints = (try? c.decode([String].self, forKey: .classificationHints)) ?? []
    }
}
