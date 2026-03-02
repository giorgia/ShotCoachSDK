import Foundation

/// Runs all SCFrameRule instances concurrently against incoming camera frames.
/// Analysis is throttled to at most one pass per 1500 ms via actor-isolated state.
///
/// `SCShotClassifierRule` is always run in the TaskGroup alongside the caller-supplied
/// rules, but its result is sidechained: the detected shot type is extracted and placed
/// in `SCFrameResult.detectedShotType` rather than appearing in `SCFrameResult.rules`.
public actor SCFrameAnalyzer {

    // MARK: - Public interface

    public let rules: [any SCFrameRule]

    public init(rules: [any SCFrameRule] = []) {
        self.rules = rules
        self.requiredShots = []
        self.classifier = SCShotClassifierRule(requiredShots: [])
    }

    /// Convenience initialiser that pulls `onDeviceRules` and `requiredShots`
    /// from a category config. `requiredShots` (with their `classificationHints`) is
    /// forwarded to `SCShotClassifierRule` so the classifier can use category-specific
    /// Vision vocabulary rather than the generic taxonomy map.
    public init(category: any SCCategoryConfig) {
        self.rules = category.onDeviceRules
        self.requiredShots = category.requiredShots
        self.classifier = SCShotClassifierRule(requiredShots: category.requiredShots)
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

        // Run every rule and the shot classifier concurrently.
        // The classifier result is sidechained — it does not enter `ruleResults`.
        var ruleResults: [String: SCRuleResult] = [:]
        var classifierShotID: String? = nil
        var classifierTopLabel: String? = nil
        // `classifier` is created once at init with the category's requiredShots so that
        // hint-based scoring uses the correct vocabulary for the active session.
        let snapClassifier = classifier

        await withTaskGroup(of: (String, SCRuleResult).self) { group in
            // Classifier runs in the same TaskGroup for concurrency but is keyed
            // by a sentinel ID so it can be separated from quality-rule results.
            group.addTask {
                (SCShotClassifierRule.classifierRuleID, await snapClassifier.evaluate(frame))
            }
            for rule in rules {
                group.addTask {
                    (rule.ruleID, await rule.evaluate(frame))
                }
            }
            for await (id, result) in group {
                if id == SCShotClassifierRule.classifierRuleID {
                    // Sidechain: extract shot ID and raw top label; don't add to ruleResults.
                    classifierShotID  = result.detectedShotTypeID
                    classifierTopLabel = result.message.isEmpty ? nil : result.message
                } else {
                    // precondition (not assert) so duplicate ruleIDs crash in both
                    // debug and release builds — silent overwrites corrupt analytics data.
                    precondition(ruleResults[id] == nil,
                                 "Duplicate ruleID '\(id)' — each SCFrameRule must have a unique ruleID")
                    ruleResults[id] = result
                }
            }
        }

        let elapsed      = ContinuousClock.now - start
        let (sec, atto)  = elapsed.components
        let processingMs = Double(sec) * 1000 + Double(atto) / 1_000_000_000_000_000

        let allPassed = ruleResults.values.allSatisfy(\.passed)
        let guidance  = allPassed ? "Ready to shoot" : topFailureMessage(in: ruleResults)

        // Resolve the classifier's shot ID against the category's required shots.
        // Returns nil when no match is found (e.g. wrong category for the scene).
        let detectedShotType = classifierShotID
            .flatMap { id in requiredShots.first { $0.id == id } }

        let frameResult = SCFrameResult(
            rules: ruleResults,
            overallGuidance: guidance,
            isReadyToCapture: allPassed,
            processingMs: processingMs,
            detectedShotType: detectedShotType,
            topSceneLabel: classifierTopLabel
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

    /// Required shots from the category supplied at init time.
    /// Used to resolve `SCShotClassifierRule`'s detected ID into a full `SCShotType`.
    /// Empty when initialised via `init(rules:)` — `detectedShotType` will be nil.
    private let requiredShots: [SCShotType]

    /// Shot classifier pre-built with the category's `requiredShots` and their
    /// `classificationHints` so hint-based scoring is applied on every frame.
    private let classifier: SCShotClassifierRule

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
