import Foundation

/// Deep analysis result returned by the cloud AI provider after photo capture.
public struct SCCloudResult: Codable, Sendable {
    public let score: Int
    public let issues: [SCIssue]
    public let shotType: String
    public let recommendations: [SCRecommendation]
    public let rawJSON: String

    public init(score: Int, issues: [SCIssue], shotType: String, recommendations: [SCRecommendation], rawJSON: String) {
        self.score = score
        self.issues = issues
        self.shotType = shotType
        self.recommendations = recommendations
        self.rawJSON = rawJSON
    }
}
