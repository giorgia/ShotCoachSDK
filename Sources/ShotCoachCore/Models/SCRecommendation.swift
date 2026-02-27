import Foundation

/// An actionable suggestion returned alongside a cloud analysis result.
public struct SCRecommendation: Codable, Sendable {
    public let text: String
    public let priority: Int

    public init(text: String, priority: Int) {
        self.text = text
        self.priority = priority
    }
}
