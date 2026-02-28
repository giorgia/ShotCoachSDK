import Foundation

/// Runs all SCFrameRule instances concurrently against incoming camera frames.
/// Analysis is throttled to at most one pass per 1500 ms via actor-isolated state.
public actor SCFrameAnalyzer {

    // MARK: - Public interface

    public let rules: [any SCFrameRule]

    public init(rules: [any SCFrameRule] = []) {
        self.rules = rules
    }

    /// Sets the delegate that receives frame and cloud analysis events.
    /// The delegate is held weakly; retain it in the caller.
    public func setDelegate(_ delegate: (any SCAnalysisDelegate)?) {
        self.delegate = delegate
    }

    /// Analyses `frame` against all rules concurrently.
    /// Calls are silently dropped if fewer than 1500 ms have elapsed since the last analysis.
    public func analyze(_ frame: SCFrame) async {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= throttleInterval else { return }
        lastAnalysisDate = now

        let start = Date()

        // Run every rule concurrently; collect keyed results.
        var ruleResults: [String: SCRuleResult] = [:]
        await withTaskGroup(of: (String, SCRuleResult).self) { group in
            for rule in rules {
                group.addTask {
                    (rule.ruleID, await rule.evaluate(frame))
                }
            }
            for await (id, result) in group {
                ruleResults[id] = result
            }
        }

        let processingMs = Date().timeIntervalSince(start) * 1000
        let allPassed    = ruleResults.values.allSatisfy(\.passed)
        let guidance     = allPassed ? "Ready to shoot" : topFailureMessage(in: ruleResults)

        let frameResult = SCFrameResult(
            rules: ruleResults,
            overallGuidance: guidance,
            isReadyToCapture: allPassed,
            processingMs: processingMs
        )

        notifyDelegate(with: frameResult)
    }

    // MARK: - Testing

    /// Resets the throttle timestamp so the next `analyze` call is guaranteed to run.
    /// For use in unit tests only.
    func resetThrottleForTesting() {
        lastAnalysisDate = .distantPast
    }

    // MARK: - Private

    private weak var delegate: (any SCAnalysisDelegate)?
    private var lastAnalysisDate: Date = .distantPast
    private let throttleInterval: TimeInterval = 1.5

    /// Returns the human-readable message from the highest-severity failing rule.
    private func topFailureMessage(in results: [String: SCRuleResult]) -> String {
        results.values
            .filter { !$0.passed }
            .max { severityRank($0.severity) < severityRank($1.severity) }
            .map(\.message) ?? "Adjust your shot"
    }

    private func severityRank(_ s: SCRuleSeverity) -> Int {
        switch s {
        case .info:     return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }

    /// Dispatches the delegate callback on the MainActor.
    private func notifyDelegate(with result: SCFrameResult) {
        let capturedDelegate = delegate
        let capturedSelf     = self
        Task { @MainActor in
            capturedDelegate?.analyzer(capturedSelf, didUpdate: result)
        }
    }
}
