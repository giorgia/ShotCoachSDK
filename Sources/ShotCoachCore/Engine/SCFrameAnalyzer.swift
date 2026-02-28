import Foundation

/// Runs all SCFrameRule instances concurrently against incoming camera frames.
/// Analysis is throttled to at most one pass per 1500 ms via actor-isolated state.
public actor SCFrameAnalyzer {

    // MARK: - Public interface

    public let rules: [any SCFrameRule]

    public init(rules: [any SCFrameRule] = []) {
        self.rules = rules
    }

    /// Convenience initialiser that pulls `onDeviceRules` from a category config.
    public init(category: any SCCategoryConfig) {
        self.rules = category.onDeviceRules
    }

    /// Sets the delegate that receives frame and cloud analysis events.
    /// The delegate is held weakly via `_delegateObject`; retain it in the caller.
    public func setDelegate(_ delegate: (any SCAnalysisDelegate)?) {
        self.delegate = delegate
    }

    /// Returns the most recent `SCFrameResult`, or a default "initializing" result
    /// if no analysis has been run yet.
    public func lastFrameResult() -> SCFrameResult {
        return lastResult
    }

    /// Analyses `frame` against all rules concurrently and returns the aggregated result.
    /// If fewer than 1500 ms have elapsed since the last analysis, the previous result
    /// is returned immediately without re-running the rules.
    @discardableResult
    public func analyze(_ frame: SCFrame) async -> SCFrameResult {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= throttleInterval else {
            return lastResult
        }
        lastAnalysisDate = now

        let start = ContinuousClock.now

        // Run every rule concurrently; collect keyed results.
        var ruleResults: [String: SCRuleResult] = [:]
        await withTaskGroup(of: (String, SCRuleResult).self) { group in
            for rule in rules {
                group.addTask {
                    (rule.ruleID, await rule.evaluate(frame))
                }
            }
            for await (id, result) in group {
                assert(ruleResults[id] == nil,
                       "Duplicate ruleID '\(id)' — only the last result will be kept")
                ruleResults[id] = result
            }
        }

        let elapsed      = ContinuousClock.now - start
        let (sec, atto)  = elapsed.components
        let processingMs = Double(sec) * 1000 + Double(atto) / 1_000_000_000_000_000

        let allPassed = ruleResults.values.allSatisfy(\.passed)
        let guidance  = allPassed ? "Ready to shoot" : topFailureMessage(in: ruleResults)

        let frameResult = SCFrameResult(
            rules: ruleResults,
            overallGuidance: guidance,
            isReadyToCapture: allPassed,
            processingMs: processingMs
        )

        lastResult = frameResult
        notifyDelegate(with: frameResult)
        return frameResult
    }

    // MARK: - Testing

#if DEBUG
    /// Resets the throttle timestamp so the next `analyze` call is guaranteed to run.
    /// For use in unit tests only — stripped from release builds.
    func resetThrottleForTesting() {
        lastAnalysisDate = .distantPast
    }
#endif

    // MARK: - Private

    // `weak` on a protocol existential is unsound; store the delegate as a weak AnyObject
    // and re-type on access. SCAnalysisDelegate: AnyObject guarantees this cast succeeds.
    private weak var _delegateObject: AnyObject?
    private var delegate: (any SCAnalysisDelegate)? {
        get { _delegateObject as? any SCAnalysisDelegate }
        set { _delegateObject = newValue }
    }

    private var lastAnalysisDate: Date = .distantPast
    private let throttleInterval: TimeInterval = 1.5
    private var lastResult: SCFrameResult = SCFrameResult(
        rules: [:],
        overallGuidance: "Initializing",
        isReadyToCapture: false,
        processingMs: 0
    )

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

    /// Schedules the delegate callback on the MainActor (fire-and-forget).
    private func notifyDelegate(with result: SCFrameResult) {
        let capturedDelegate = delegate
        Task { @MainActor in
            capturedDelegate?.analyzer(self, didUpdate: result)
        }
    }
}
