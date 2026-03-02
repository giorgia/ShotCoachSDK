import Foundation
import Vision
import CoreVideo

/// Classifies the scene type in each camera frame using `VNClassifyImageRequest`
/// (Apple's built-in Vision taxonomy — no CoreML model required).
///
/// This rule **never blocks capture** — it always returns `passed: true`.
/// Its purpose is metadata:
/// - `SCRuleResult.message`            — human-readable label for display (matched shot
///                                       display name when a shot is recognised, otherwise
///                                       the formatted top Vision result, e.g. "Indoor").
/// - `SCRuleResult.detectedShotTypeID` — matched `SCShotType.id` when a shot is recognised
///                                       above `confidenceThreshold`.
///
/// ### Classification strategy
///
/// When the initialiser receives `requiredShots` with `classificationHints`, the classifier
/// uses **cumulative scoring**: for every shot type it sums the Vision confidences of all
/// observations whose identifier contains any of the shot's hint strings. The shot with the
/// highest cumulative score wins (if ≥ `confidenceThreshold`). This is far more robust than
/// single-observation matching because Vision's taxonomy is generic and hierarchical — a
/// kitchen will score on "kitchen" + "appliance" + "counter" simultaneously even if no single
/// observation is individually high-confidence.
///
/// When `requiredShots` is empty (or all shots lack hints), the classifier falls back to the
/// built-in taxonomy map for backward compatibility.
///
/// `SCFrameAnalyzer` sidechains this result: it extracts both fields and places them in
/// `SCFrameResult.topSceneLabel` and `SCFrameResult.detectedShotType`. The result never
/// appears in `SCFrameResult.rules` and never triggers a `FeedbackPill`.
public struct SCShotClassifierRule: SCFrameRule {

    /// The stable rule identifier used by `SCFrameAnalyzer` to sidechain this result.
    public static let classifierRuleID = "sc.shot_classifier"

    public var ruleID: String { SCShotClassifierRule.classifierRuleID }
    public var severity: SCRuleSeverity { .info }
    public var feedbackMessage: String { "" }

    /// Minimum cumulative confidence score required to report a `detectedShotTypeID`.
    /// With hint-based scoring this is the sum of matching observation confidences.
    /// The display label (`message`) uses a fixed lower threshold (0.10) independently.
    public let confidenceThreshold: Float

    /// Required shots supplied by the category. When non-empty and hints are present,
    /// hint-based scoring is used instead of the built-in taxonomy map.
    private let requiredShots: [SCShotType]

    public init(requiredShots: [SCShotType] = [], confidenceThreshold: Float = 0.20) {
        self.requiredShots        = requiredShots
        self.confidenceThreshold  = confidenceThreshold
    }

    // MARK: - SCFrameRule

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let (shotID, displayLabel) = classifyScene(pixelBuffer: frame.pixelBuffer)
        return SCRuleResult(
            passed: true,
            message: displayLabel ?? "",
            severity: severity,
            detectedShotTypeID: shotID
        )
    }

    // MARK: - Private — classification

    /// Minimum confidence for an individual observation to appear in the display label
    /// (independent of `confidenceThreshold`).
    private let labelMinConfidence: Float = 0.10

    /// Returns `(shotID, displayLabel)`:
    /// - `shotID`      — matched shot's `id`, or nil when score < `confidenceThreshold`.
    /// - `displayLabel`— matched shot's `displayName`, or formatted top Vision identifier.
    private func classifyScene(pixelBuffer: CVPixelBuffer) -> (String?, String?) {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return (nil, nil)
        }
        guard let results = request.results, !results.isEmpty else { return (nil, nil) }

        // Fallback display label: highest single-observation result above the low threshold.
        let topLabel = results
            .sorted { $0.confidence > $1.confidence }
            .first  { $0.confidence >= labelMinConfidence }
            .map    { formatIdentifier($0.identifier) }

        // ── Hint-based scoring ───────────────────────────────────────────────────
        // Used when any required shot has classification hints.
        let shotsWithHints = requiredShots.filter { !$0.classificationHints.isEmpty }
        if !shotsWithHints.isEmpty {
            var bestShot:  SCShotType? = nil
            var bestScore: Float = 0

            for shot in shotsWithHints {
                // Sum the confidence of every Vision observation that matches any hint.
                // Each observation is counted at most once per shot — a `Set` of already-
                // matched identifiers prevents double-counting when multiple hints match
                // the same hierarchical Vision label (e.g. "kitchen" and "appliance" both
                // matching "kitchen appliance" with confidence 0.4 would otherwise add 0.8).
                var counted = Set<String>()
                var score: Float = 0
                for hint in shot.classificationHints {
                    guard let obs = results.first(where: {
                        $0.identifier.lowercased().contains(hint.lowercased())
                    }) else { continue }
                    guard counted.insert(obs.identifier).inserted else { continue }
                    score += obs.confidence
                }
                if score > bestScore {
                    bestScore = score
                    bestShot  = shot
                }
            }

            if bestScore >= confidenceThreshold, let matched = bestShot {
                // Show the shot's display name so the user sees "Kitchen" not "Appliance".
                return (matched.id, matched.displayName)
            }
            // Below threshold — still surface top Vision label for awareness.
            return (nil, topLabel)
        }

        // ── Taxonomy-map fallback (no hints supplied) ────────────────────────────
        for (identifiers, shotID) in Self.taxonomyMap {
            for substring in identifiers {
                if let obs = results.first(where: {
                    $0.identifier.lowercased().contains(substring)
                }), obs.confidence >= confidenceThreshold {
                    return (shotID, topLabel)
                }
            }
        }
        return (nil, topLabel)
    }

    // MARK: - Taxonomy-map fallback

    /// Used only when `requiredShots` have no hints (e.g. fully custom categories or tests).
    private static let taxonomyMap: [(identifiers: [String], shotID: String)] = [
        (["living room", "living_room", "living-room", "lounge"],   "living_room"),
        (["kitchen"],                                                 "kitchen"),
        (["bedroom", "sleeping room"],                               "master_bedroom"),
        (["bathroom", "restroom"],                                   "bathroom"),
        (["house", "building facade", "exterior", "facade"],        "front_exterior"),
        (["dashboard", "cockpit", "car interior", "steering"],      "dashboard"),
        (["car", "automobile", "vehicle"],                           "front_three_quarter"),
        (["food", "plate", "dish", "dining"],                       "hero"),
    ]

    // MARK: - Formatting

    /// "car_interior" → "Car Interior", "living room" → "Living Room"
    private func formatIdentifier(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
