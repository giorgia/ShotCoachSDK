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

    /// Injected CoreML-backed scorer.
    private let model: any SCAestheticModelProvider

    /// Score threshold in [0, 10] above which the rule is considered passing.
    public nonisolated let passingThreshold: Double

    /// EMA smoothing factor α ∈ (0, 1].
    /// Lower = smoother (more lag); higher = more responsive (more jitter).
    public nonisolated let smoothingFactor: Double

    // MARK: - Mutable actor-isolated state

    /// Current exponentially smoothed score. Starts at 5.0 (neutral midpoint).
    private var smoothedScore: Double = 5.0

    // MARK: - Init

    public init(
        model: any SCAestheticModelProvider,
        passingThreshold: Double = 5.0,
        smoothingFactor: Double = 0.3
    ) {
        precondition(smoothingFactor > 0 && smoothingFactor <= 1,
                     "smoothingFactor must be in (0, 1]; got \(smoothingFactor)")
        self.model = model
        self.passingThreshold = passingThreshold
        self.smoothingFactor = smoothingFactor
    }

    // MARK: - SCFrameRule

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        // Heuristic baseline — runs regardless of model availability.
        let heuristicScore = await SCInstagrammabilityRule().evaluate(frame).numericScore ?? 5.0

        // Blend: 70 % CoreML + 30 % heuristic.
        // On model throw, fall back to 100 % heuristic so the score stays meaningful.
        let blended: Double
        do {
            let raw = try await model.score(frame.pixelBuffer)
            let clamped = max(0.0, min(10.0, raw))
            blended = 0.7 * clamped + 0.3 * heuristicScore
        } catch {
            blended = heuristicScore
        }

        // EMA: smoothed = α * blended + (1 − α) * smoothed
        smoothedScore = smoothingFactor * blended + (1.0 - smoothingFactor) * smoothedScore

        let score = smoothedScore
        let label = scoreLabel(score)

        return SCRuleResult(
            passed: score >= passingThreshold,
            message: label,
            severity: severity,
            numericScore: score
        )
    }

    // MARK: - Helpers

    private func scoreLabel(_ score: Double) -> String {
        switch score {
        case 8.0...: return "Stunning"
        case 6.5...: return "Great"
        case 5.0...: return "Good"
        case 3.0...: return "Needs Work"
        default:     return "Poor"
        }
    }
}
