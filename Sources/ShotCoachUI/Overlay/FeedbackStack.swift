import SwiftUI
import ShotCoachCore

/// Vertically stacks a `FeedbackPill` for each failing rule in an `SCFrameResult`,
/// sorted highest severity first.
public struct FeedbackStack: View {

    let result: SCFrameResult

    public init(result: SCFrameResult) {
        self.result = result
    }

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(failingResults, id: \.ruleID) { item in
                FeedbackPill(message: item.ruleResult.message, severity: item.ruleResult.severity)
            }
        }
    }

    // MARK: - Private

    private struct FailingResult {
        let ruleID:     String
        let ruleResult: SCRuleResult
    }

    private var failingResults: [FailingResult] {
        result.rules
            .filter { !$0.value.passed }
            .sorted { severityRank($0.value.severity) > severityRank($1.value.severity) }
            .map    { FailingResult(ruleID: $0.key, ruleResult: $0.value) }
    }

    private func severityRank(_ s: SCRuleSeverity) -> Int {
        switch s {
        case .info:     return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }
}
