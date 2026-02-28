import Foundation
import Vision

/// Detects excessive visual clutter using objectness-based saliency.
/// Fails when the number of distinct salient regions exceeds the configured maximum.
public struct SCClutterRule: SCFrameRule {
    /// Maximum acceptable number of distinct salient objects. Default 5.
    public let maxSalientRegions: Int

    public init(maxSalientRegions: Int = 5) {
        self.maxSalientRegions = maxSalientRegions
    }

    public var ruleID: String { "sc.clutter" }
    public var severity: SCRuleSeverity { .warning }
    public var feedbackMessage: String { "Simplify the background" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return SCRuleResult(passed: true, message: "Clutter analysis unavailable", severity: severity)
        }

        guard let observation = request.results?.first as? VNSaliencyImageObservation,
              let objects = observation.salientObjects, !objects.isEmpty else {
            // No distinct objects detected — scene is not cluttered.
            return SCRuleResult(passed: true, message: "Background clear", severity: severity)
        }

        let count = objects.count
        if count > maxSalientRegions {
            return SCRuleResult(passed: false,
                                message: "Too many objects in frame (\(count)) — simplify the background",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "Background clear", severity: severity)
    }
}
