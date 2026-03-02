import Foundation
import CoreVideo

/// Evaluates frame luminance via direct pixel sampling.
/// Supports kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange and FullRange (AVFoundation camera
/// output) by sampling the Y-plane directly. Falls back to BGRA channel sampling for other formats.
/// Fails when the frame is too dark or overexposed.
public struct SCBrightnessRule: SCFrameRule {
    /// Minimum acceptable luminance in [0, 1] (Rec.709). Default 0.15.
    public let minLuminance: Float
    /// Maximum acceptable luminance in [0, 1] (Rec.709). Default 0.90.
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

        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)

        switch fmt {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            // AVFoundation camera frames arrive in YUV biplanar format.
            // CVPixelBufferGetBaseAddress returns nil for planar buffers —
            // read plane 0 (Y / luma) instead.
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0.5 }
            let w    = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let h    = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bpr  = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let ptr  = yBase.assumingMemoryBound(to: UInt8.self)
            // Video range: Y ∈ [16, 235].  Full range: Y ∈ [0, 255].
            let isFullRange = (fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            let yMin: Float = isFullRange ? 0   : 16
            let yRange: Float = isFullRange ? 255 : 219   // 235 - 16
            let stepX = max(1, w / 64)
            let stepY = max(1, h / 64)
            var total: Float = 0
            var n = 0
            for y in stride(from: 0, to: h, by: stepY) {
                for x in stride(from: 0, to: w, by: stepX) {
                    let luma = (Float(ptr[y * bpr + x]) - yMin) / yRange
                    total += max(0, min(1, luma))
                    n += 1
                }
            }
            return n > 0 ? total / Float(n) : 0.5

        default:
            // BGRA / RGBA: non-planar, CVPixelBufferGetBaseAddress is valid.
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
            let w   = CVPixelBufferGetWidth(pixelBuffer)
            let h   = CVPixelBufferGetHeight(pixelBuffer)
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            // Per-axis step keeps samples ≤ 64 per axis regardless of aspect ratio.
            let stepX = max(1, w / 64)
            let stepY = max(1, h / 64)
            var total: Float = 0
            var n = 0
            for y in stride(from: 0, to: h, by: stepY) {
                for x in stride(from: 0, to: w, by: stepX) {
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
}
