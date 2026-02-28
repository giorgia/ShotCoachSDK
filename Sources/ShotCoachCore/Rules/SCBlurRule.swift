import Foundation
import CoreVideo

/// Measures image sharpness using Laplacian variance (kCVPixelFormatType_32BGRA assumed).
/// Fails when the sharpness score drops below the configured minimum.
public struct SCBlurRule: SCFrameRule {
    /// Minimum acceptable sharpness on a 0–100 scale. Default 30.
    public let minSharpnessScore: Float

    public init(minSharpnessScore: Float = 30.0) {
        self.minSharpnessScore = minSharpnessScore
    }

    public var ruleID: String { "sc.blur" }
    public var severity: SCRuleSeverity { .critical }
    public var feedbackMessage: String { "Hold the camera steady" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        let score = sharpnessScore(of: frame.pixelBuffer)
        if score < 0 {
            // Fail open: buffer too small to compute Laplacian.
            return SCRuleResult(passed: true, message: "Frame too small to analyze sharpness", severity: severity)
        }
        if score < minSharpnessScore {
            return SCRuleResult(passed: false,
                                message: "Image is blurry — hold still or rest the camera on a surface",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "Sharpness OK", severity: severity)
    }

    // MARK: - Private

    /// Returns a sharpness score in [0, 100] using the variance of the Laplacian.
    /// Calibration: uniform images score 0; a full checkerboard scores 100.
    private func sharpnessScore(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Fail open: signal "not analyzable" with -1; evaluate(_:) handles this.
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return -1 }
        let w   = CVPixelBufferGetWidth(pixelBuffer)
        let h   = CVPixelBufferGetHeight(pixelBuffer)
        // Buffer must have interior pixels for the 4-connected Laplacian.
        guard w > 2, h > 2 else { return -1 }

        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        func luma(x: Int, y: Int) -> Float {
            let off = y * bpr + x * 4
            let b = Float(ptr[off])     / 255
            let g = Float(ptr[off + 1]) / 255
            let r = Float(ptr[off + 2]) / 255
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        // Per-axis step keeps samples ≤ 64 per axis regardless of aspect ratio.
        let stepX = max(1, w / 64)
        let stepY = max(1, h / 64)
        var sum:   Float = 0
        var sumSq: Float = 0
        var n = 0

        for y in stride(from: 1, to: h - 1, by: stepY) {
            for x in stride(from: 1, to: w - 1, by: stepX) {
                // 4-connected Laplacian: 4·C − T − B − L − R
                let lap = 4 * luma(x: x,   y: y)
                           - luma(x: x,   y: y - 1)
                           - luma(x: x,   y: y + 1)
                           - luma(x: x - 1, y: y)
                           - luma(x: x + 1, y: y)
                sum   += lap
                sumSq += lap * lap
                n += 1
            }
        }
        guard n > 0 else { return -1 }
        let mean     = sum / Float(n)
        let variance = sumSq / Float(n) - mean * mean
        // Scale factor calibrated so a 1px black/white checkerboard (variance ≈ 16,
        // Laplacian values alternating ±4) maps to score 100; uniform images map to 0.
        let laplacianScaleFactor: Float = 600
        return min(variance.squareRoot() * laplacianScaleFactor, 100)
    }
}
