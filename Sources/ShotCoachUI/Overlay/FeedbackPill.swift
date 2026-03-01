import SwiftUI
import ShotCoachCore

/// Displays a single guidance message with a severity-coded background.
/// Severity maps to colour: `.info` → gray, `.warning` → orange, `.critical` → red.
public struct FeedbackPill: View {

    let message:  String
    let severity: SCRuleSeverity

    public init(message: String, severity: SCRuleSeverity) {
        self.message  = message
        self.severity = severity
    }

    public var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor, in: Capsule())
    }

    private var backgroundColor: Color {
        switch severity {
        case .info:     return Color.gray.opacity(0.85)
        case .warning:  return Color.orange
        case .critical: return Color.red
        }
    }
}
