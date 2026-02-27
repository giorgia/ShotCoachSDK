import Foundation

/// Deep analysis result returned by the cloud AI provider after photo capture.
public struct SCCloudResult: Codable, Sendable {
    public let score: Double
    public let issues: [String]
    public let shotType: String
    public let recommendations: [String]

    public init(score: Double, issues: [String], shotType: String, recommendations: [String]) {
        self.score = score
        self.issues = issues
        self.shotType = shotType
        self.recommendations = recommendations
    }
}
