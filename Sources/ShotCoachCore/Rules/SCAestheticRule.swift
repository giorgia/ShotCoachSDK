import Foundation
import CoreVideo

/// Live-frame aesthetic scoring rule backed by a user-supplied CoreML model.
///
/// The rule is an `actor` (not `struct`) to safely hold mutable EMA state across
/// concurrent `evaluate` calls. `ruleID`, `severity`, and `feedbackMessage` are
/// `nonisolated` — they are constants and require no actor hop.
///
/// **Usage**
/// ```swift
/// let rule = SCAestheticRule(model: MyAestheticModel())
/// ```
/// where `MyAestheticModel` conforms to `SCAestheticModelProvider` and lives in
/// your app target alongside the `.mlpackage` resource.
///
/// **EMA smoothing**
/// Exponential moving average with configurable `smoothingFactor` (α) suppresses
/// per-frame jitter without an external filter. Lower α = smoother / more lag;
/// higher α = more responsive / more jitter.
public actor SCAestheticRule: SCFrameRule {

    // MARK: - SCFrameRule (nonisolated constants)

    public nonisolated var ruleID: String { "sc.aesthetic" }
    public nonisolated var severity: SCRuleSeverity { .warning }
    public nonisolated var feedbackMessage: String { "Improve aesthetic quality" }

    // MARK: - Configuration

    /// Injected CoreML-backed scorer. `nonisolated let` so it is accessible from
    /// the nonisolated `evaluate` path without an actor hop.
    private nonisolated let model: any SCAestheticModelProvider

    /// Heuristic baseline used when `model` throws. Stored as a `let` so the
    /// Vision request infrastructure is created once, not on every frame.
    private nonisolated let heuristicRule = SCInstagrammabilityRule()

    /// Score threshold in [0, 100] above which the rule is considered passing.
    public nonisolated let passingThreshold: Double

    /// EMA smoothing factor α ∈ (0, 1].
    /// Lower = smoother (more lag); higher = more responsive (more jitter).
    public nonisolated let smoothingFactor: Double

    // MARK: - Mutable actor-isolated state

    /// Current exponentially smoothed score. Starts at 50.0 (neutral midpoint of 0–100).
    private var smoothedScore: Double = 50.0

    // MARK: - Init

    public init(
        model: any SCAestheticModelProvider,
        passingThreshold: Double = 50.0,
        smoothingFactor: Double = 0.3
    ) {
        precondition(smoothingFactor > 0 && smoothingFactor <= 1,
                     "smoothingFactor must be in (0, 1]; got \(smoothingFactor)")
        self.model = model
        self.passingThreshold = passingThreshold
        self.smoothingFactor = smoothingFactor
    }

    // MARK: - SCFrameRule

    /// Evaluates the frame, blending CoreML and Vision heuristic, then applies EMA.
    ///
    /// Heavy async work (model inference + saliency) runs `nonisolated` — outside actor
    /// isolation — so concurrent callers don't serialise behind each other during inference.
    /// The EMA state update is a single synchronous actor-isolated call (`applyEMA`) with
    /// no suspension inside it, making the read-modify-write atomic.
    public nonisolated func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        // All async work off-actor so concurrent callers run inference in parallel.
        let heuristicScore = await heuristicRule.evaluate(frame).numericScore ?? 50.0

        // Blend: 70 % CoreML + 30 % heuristic.
        // On model throw, fall back to 100 % heuristic so the score stays meaningful.
        let blended: Double
        do {
            let raw = try await model.score(frame.pixelBuffer)
            let clamped = max(0.0, min(100.0, raw))
            blended = 0.7 * clamped + 0.3 * heuristicScore
        } catch {
            blended = heuristicScore
        }

        // Single synchronous actor hop — no suspension inside, so the EMA update is atomic.
        return await applyEMA(blended: blended)
    }

    // MARK: - Helpers

    /// Applies EMA to `smoothedScore` and returns the result.
    /// This method is synchronous (no `await`) so the read-modify-write is atomic
    /// within the actor's serial executor — no two callers can interleave here.
    private func applyEMA(blended: Double) -> SCRuleResult {
        smoothedScore = smoothingFactor * blended + (1.0 - smoothingFactor) * smoothedScore
        let score = smoothedScore
        return SCRuleResult(
            passed: score >= passingThreshold,
            message: scoreLabel(score),
            severity: severity,
            numericScore: score
        )
    }

    private nonisolated func scoreLabel(_ score: Double) -> String {
        switch score {
        case 80.0...: return "Stunning"
        case 65.0...: return "Great"
        case 50.0...: return "Good"
        case 30.0...: return "Needs Work"
        default:      return "Poor"
        }
    }
}
