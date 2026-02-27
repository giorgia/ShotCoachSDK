import Foundation

/// Summary of a completed photography session.
public struct SCSessionSummary: Codable, Sendable {
    public let photos: [SCPhoto]
    public let averageScore: Double
    public let completedShots: [SCShotType]

    public init(photos: [SCPhoto], averageScore: Double, completedShots: [SCShotType]) {
        self.photos = photos
        self.averageScore = averageScore
        self.completedShots = completedShots
    }
}
