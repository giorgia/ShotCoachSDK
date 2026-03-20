import Foundation
import Vision

/// Detects unwanted reflections (e.g. photographer visible in a mirror or window).
/// Uses two Vision requests in parallel:
/// - `VNDetectFaceRectanglesRequest` — catches clear face reflections in flat mirrors/glass
/// - `VNDetectHumanRectanglesRequest` (upperBodyOnly) — catches torso-up silhouettes
///   reflected in curved or glossy product surfaces where the face may be distorted
///
/// Note: this rule will also trigger on framed portraits or artwork — configure
/// `allowedFaceCount` / `allowedHumanCount` appropriately for contexts where
/// people are expected in the frame.
public struct SCReflectionRule: SCFrameRule {
    /// Number of detected faces permitted before the rule fails. Default 0.
    public let allowedFaceCount: Int
    /// Number of detected upper-body silhouettes permitted before the rule fails. Default 0.
    /// Upper-body detection is broader than face detection and may produce more false positives
    /// in scenes with humanoid shapes (e.g. mannequins). Raise this if needed.
    public let allowedHumanCount: Int

    public init(allowedFaceCount: Int = 0, allowedHumanCount: Int = 0) {
        self.allowedFaceCount = allowedFaceCount
        self.allowedHumanCount = allowedHumanCount
    }

    public var ruleID: String { "sc.reflection" }
    public var severity: SCRuleSeverity { .warning }
    public var feedbackMessage: String { "Check for reflections in mirrors or windows" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let faceRequest  = VNDetectFaceRectanglesRequest()
        // upperBodyOnly = true detects torso-up silhouettes, catching photographer
        // reflections in curved/glossy product surfaces where the face may be distorted.
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = true
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([faceRequest, humanRequest])
        } catch {
            return SCRuleResult(passed: true, message: "Reflection analysis unavailable", severity: severity)
        }

        let faceCount  = faceRequest.results?.count  ?? 0
        let humanCount = humanRequest.results?.count ?? 0
        if faceCount > allowedFaceCount || humanCount > allowedHumanCount {
            return SCRuleResult(passed: false,
                                message: "Reflection detected — check mirrors and windows",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "No reflections detected", severity: severity)
    }
}
