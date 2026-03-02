import Foundation
import Vision
import CoreVideo

/// Classifies the scene type in each camera frame using `VNClassifyImageRequest`
/// (Apple's built-in Vision taxonomy — no CoreML model required).
///
/// This rule **never blocks capture** — it always returns `passed: true`.
/// Its purpose is metadata: setting `SCRuleResult.detectedShotTypeID` so that
/// `SCFrameAnalyzer` can populate `SCFrameResult.detectedShotType`, which
/// `SCShotChecklistView` uses to highlight the detected scene in the checklist.
///
/// The classifier runs concurrently with quality rules inside `SCFrameAnalyzer`'s
/// `TaskGroup` but its result is sidelined — it does not appear in
/// `SCFrameResult.rules` and never triggers a `FeedbackPill`.
public struct SCShotClassifierRule: SCFrameRule {

    /// The stable rule identifier used by `SCFrameAnalyzer` to sidechain this
    /// rule's result. Callers must not add another rule with this ID.
    public static let classifierRuleID = "sc.shot_classifier"

    public var ruleID: String { SCShotClassifierRule.classifierRuleID }
    public var severity: SCRuleSeverity { .info }
    public var feedbackMessage: String { "" }

    /// Minimum `VNClassificationObservation.confidence` required to report a
    /// detected shot type. Observations below this threshold are ignored.
    public let confidenceThreshold: Float

    public init(confidenceThreshold: Float = 0.6) {
        self.confidenceThreshold = confidenceThreshold
    }

    // MARK: - SCFrameRule

    /// Always returns `passed: true`. Sets `detectedShotTypeID` when a scene
    /// is identified above `confidenceThreshold`; otherwise `nil`.
    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let shotID = classifyScene(pixelBuffer: frame.pixelBuffer)
        return SCRuleResult(
            passed: true,
            message: shotID.map { "Scene classified: \($0)" } ?? "",
            severity: severity,
            detectedShotTypeID: shotID
        )
    }

    // MARK: - Private

    /// Maps Vision taxonomy identifier substrings (priority-ordered) to `SCShotType.id` values.
    ///
    /// Multiple identifier substrings can map to the same shot ID; the first match
    /// in the taxonomy map that exceeds `confidenceThreshold` is returned.
    ///
    /// Shot IDs match the `SCShotType.id` values defined in `SCBuiltInCategory`:
    ///   - "living_room", "kitchen", "master_bedroom", "bathroom", "front_exterior"
    ///     cover `SCBuiltInCategory.homeListing`
    ///   - "front_three_quarter", "dashboard" cover `SCBuiltInCategory.carListing`
    ///   - "hero" covers `SCBuiltInCategory.foodPhoto`
    private static let taxonomyMap: [(identifiers: [String], shotID: String)] = [
        (["living_room", "living-room", "living_space"],    "living_room"),
        (["kitchen"],                                        "kitchen"),
        (["bedroom"],                                        "master_bedroom"),
        (["bathroom"],                                       "bathroom"),
        (["house", "building_facade", "exterior"],           "front_exterior"),
        (["car_interior", "vehicle_interior", "dashboard"],  "dashboard"),
        (["car", "automobile", "vehicle"],                   "front_three_quarter"),
        (["food", "plate", "dish", "dining"],                "hero"),
    ]

    private func classifyScene(pixelBuffer: CVPixelBuffer) -> String? {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Vision unavailable or buffer too small — fail open.
            return nil
        }
        guard let results = request.results, !results.isEmpty else { return nil }

        // Walk the taxonomy map in priority order; return the first shot ID whose
        // identifier substring appears in any observation above the threshold.
        for (identifiers, shotID) in Self.taxonomyMap {
            for identifier in identifiers {
                if let obs = results.first(where: {
                    $0.identifier.lowercased().contains(identifier)
                }), obs.confidence >= confidenceThreshold {
                    return shotID
                }
            }
        }
        return nil
    }
}
