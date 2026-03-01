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
            // Secondary sort by ruleID ensures a stable, deterministic order across frames.
            // Without it, same-severity rules can swap positions every 1.5 s (dict order).
            .sorted {
                let r0 = severityRank($0.value.severity)
                let r1 = severityRank($1.value.severity)
                return r0 != r1 ? r0 > r1 : $0.key < $1.key
            }
            .map { FailingResult(ruleID: $0.key, ruleResult: $0.value) }
    }

    private func severityRank(_ s: SCRuleSeverity) -> Int {
        switch s {
        case .info:     return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }
}
