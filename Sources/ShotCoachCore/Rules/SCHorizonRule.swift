import Foundation
import Vision

/// Detects tilted horizons using Vision's VNDetectHorizonRequest.
/// Fails when the measured tilt exceeds the configured maximum degrees.
public struct SCHorizonRule: SCFrameRule {
    /// Maximum acceptable horizon tilt in degrees. Default 5°.
    public let maxTiltDegrees: Double

    public init(maxTiltDegrees: Double = 5.0) {
        self.maxTiltDegrees = maxTiltDegrees
    }

    public var ruleID: String { "sc.horizon" }
    public var severity: SCRuleSeverity { .warning }
    public var feedbackMessage: String { "Level the camera" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Fail open: if analysis fails, don't block the user.
            return SCRuleResult(passed: true, message: "Horizon analysis unavailable", severity: severity)
        }

        guard let observation = request.results?.first else {
            // No horizon detected (e.g. uniform frame) — cannot determine tilt.
            return SCRuleResult(passed: true, message: "Horizon undetectable", severity: severity)
        }

        let tilt = abs(observation.angle) * 180 / .pi
        if tilt > maxTiltDegrees {
            return SCRuleResult(passed: false,
                                message: String(format: "Horizon is tilted %.1f° — straighten the camera", tilt),
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "Horizon level", severity: severity)
    }
}
