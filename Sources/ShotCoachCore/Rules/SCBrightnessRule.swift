import Foundation
import CoreVideo

/// Evaluates frame luminance via direct pixel sampling (kCVPixelFormatType_32BGRA assumed).
/// Fails when the frame is too dark or overexposed.
public struct SCBrightnessRule: SCFrameRule {
    public let minLuminance: Float
    public let maxLuminance: Float

    public init(minLuminance: Float = 0.15, maxLuminance: Float = 0.90) {
        self.minLuminance = minLuminance
        self.maxLuminance = maxLuminance
    }

    public var ruleID: String { "sc.brightness" }
    public var severity: SCRuleSeverity { .critical }
    public var feedbackMessage: String { "Adjust lighting before shooting" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let luma = averageLuminance(of: frame.pixelBuffer)
        if luma < minLuminance {
            return SCRuleResult(passed: false,
                                message: "Frame is too dark — increase exposure or add lighting",
                                severity: severity)
        }
        if luma > maxLuminance {
            return SCRuleResult(passed: false,
                                message: "Frame is overexposed — reduce exposure",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "Brightness OK", severity: severity)
    }

    // MARK: - Private

    private func averageLuminance(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
        let w   = CVPixelBufferGetWidth(pixelBuffer)
        let h   = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Sample at most 64 points per axis for speed.
        let step = max(1, max(w, h) / 64)
        var total: Float = 0
        var n = 0
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                let off = y * bpr + x * 4
                // kCVPixelFormatType_32BGRA layout: B G R A
                let b = Float(ptr[off])     / 255
                let g = Float(ptr[off + 1]) / 255
                let r = Float(ptr[off + 2]) / 255
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                n += 1
            }
        }
        return n > 0 ? total / Float(n) : 0.5
    }
}
