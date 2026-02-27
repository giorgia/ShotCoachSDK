import SwiftUI

/// Visual theme for ShotCoachUI components. Pass via `.theme()` modifier or SwiftUI Environment.
public struct SCTheme {
    public var accent: Color
    public var overlayStyle: OverlayStyle
    public var feedbackPosition: FeedbackPosition

    public enum OverlayStyle {
        case frostedGlass
        case minimal
        case bold
    }

    public enum FeedbackPosition {
        case top
        case bottom
    }

    public init(
        accent: Color = .blue,
        overlayStyle: OverlayStyle = .frostedGlass,
        feedbackPosition: FeedbackPosition = .bottom
    ) {
        self.accent = accent
        self.overlayStyle = overlayStyle
        self.feedbackPosition = feedbackPosition
    }
}
