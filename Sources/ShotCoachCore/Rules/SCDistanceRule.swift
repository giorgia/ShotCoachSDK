import Foundation
import Vision

/// Checks that the subject fills an appropriate portion of the frame using attention-based saliency.
/// Fails when the main subject is too small (too far) or too large (too close).
public struct SCDistanceRule: SCFrameRule {
    /// Subject must cover at least this fraction of the frame area. Default 5 %.
    public let minCoverage: Float
    /// Subject must not cover more than this fraction of the frame area. Default 80 %.
    public let maxCoverage: Float

    public init(minCoverage: Float = 0.05, maxCoverage: Float = 0.80) {
        self.minCoverage = minCoverage
        self.maxCoverage = maxCoverage
    }

    public var ruleID: String { "sc.distance" }
    public var severity: SCRuleSeverity { .warning }
    public var feedbackMessage: String { "Adjust your distance from the subject" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return SCRuleResult(passed: true, message: "Distance analysis unavailable", severity: severity)
        }

        guard let observation = request.results?.first as? VNSaliencyImageObservation,
              let objects = observation.salientObjects, !objects.isEmpty else {
            // No subject detected — cannot determine distance; fail open.
            return SCRuleResult(passed: true, message: "Subject not detected", severity: severity)
        }

        // Use the largest salient bounding box as the main subject.
        let main = objects.max { a, b in
            a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
        }!
        let coverage = Float(main.boundingBox.width * main.boundingBox.height)

        if coverage < minCoverage {
            return SCRuleResult(passed: false,
                                message: "Subject is too small — move closer",
                                severity: severity)
        }
        if coverage > maxCoverage {
            return SCRuleResult(passed: false,
                                message: "Subject is too close — step back",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "Distance OK", severity: severity)
    }
}
