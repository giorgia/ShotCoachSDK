import Foundation

/// A single issue identified by the cloud analysis provider.
public struct SCIssue: Codable, Sendable {
    public let title: String
    public let detail: String
    public let impact: SCImpactLevel

    public init(title: String, detail: String, impact: SCImpactLevel) {
        self.title = title
        self.detail = detail
        self.impact = impact
    }
}
