import Foundation
import Vision

/// Detects unwanted reflections (e.g. photographer visible in a mirror or window) by
/// using face detection as a proxy. Any face found in a listing or product photo is
/// likely a reflected photographer rather than intentional subject matter.
/// Note: this rule will also trigger on framed portraits or artwork — configure
/// `allowedFaceCount` appropriately for contexts where faces are expected.
public struct SCReflectionRule: SCFrameRule {
    /// Number of faces permitted in the frame. Default 0 (no faces allowed).
    public let allowedFaceCount: Int

    public init(allowedFaceCount: Int = 0) {
        self.allowedFaceCount = allowedFaceCount
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
        if faceCount > allowedFaceCount || humanCount > allowedFaceCount {
            return SCRuleResult(passed: false,
                                message: "Reflection detected — check mirrors and windows",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "No reflections detected", severity: severity)
    }
}
