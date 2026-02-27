import Foundation

/// A required shot within a photography session (e.g. "Front Exterior", "Kitchen").
public struct SCShotType: Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
