import Foundation
import Vision
import CoreVideo

/// Detects excessive visual clutter using two complementary signals:
///
/// 1. **Edge density** — fraction of a coarse Laplacian grid whose absolute response exceeds
///    a threshold. Dense-object scenes (pile of dishes, cluttered counter, busy background)
///    produce many tightly packed boundaries; their edge density typically exceeds 28%.
///    This check runs first — it is fast (direct pixel sampling, no Vision call) so cluttered
///    frames are rejected without paying the saliency-request cost.
///
/// 2. **Objectness saliency** — distinct salient regions via
///    `VNGenerateObjectnessBasedSaliencyImageRequest`. More than `maxSalientRegions` regions,
///    or 2+ regions covering more than `maxCoverageRatio` of the frame, signals clutter.
///
/// `VNGenerateObjectnessBasedSaliencyImageRequest` typically returns 1–4 regions even in
/// busy rooms, so the default threshold is intentionally low (3). The edge-density check
/// fills the gap for pile-of-dishes scenes that saliency treats as a single region.
@available(*, deprecated, renamed: "SCInstagrammabilityRule",
           message: "SCClutterRule penalises intentional styling. Use SCInstagrammabilityRule instead.")
public struct SCClutterRule: SCFrameRule {
    /// Maximum acceptable number of distinct salient objects. Default 3.
    public let maxSalientRegions: Int
    /// Maximum acceptable total normalised area (0–1) covered by salient regions.
    /// Default 0.55 (55% of frame). Only evaluated when 2+ regions are present.
    public let maxCoverageRatio: Float
    /// Maximum acceptable fraction of coarse-grid sample points with a Laplacian response
    /// above the edge threshold. Default 0.28 (28%). Cluttered surfaces with many overlapping
    /// objects typically score 35–55%; clean surfaces score 10–20%.
    public let maxEdgeDensity: Float

    public init(maxSalientRegions: Int = 3,
                maxCoverageRatio: Float = 0.55,
                maxEdgeDensity: Float = 0.28) {
        self.maxSalientRegions = maxSalientRegions
        self.maxCoverageRatio  = maxCoverageRatio
        self.maxEdgeDensity    = maxEdgeDensity
    }

    public var ruleID: String { "sc.clutter" }
    public var severity: SCRuleSeverity { .warning }
    public var feedbackMessage: String { "Simplify the background" }

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        // ── Signal 1: Edge density (fast — no Vision call) ──────────────────────
        // Catches dense-object scenes (pile of dishes, cluttered counter) where
        // saliency groups everything into a single region. Runs first so high-density
        // frames are rejected without incurring the VNGenerateObjectness request cost.
        let density = edgeDensity(of: frame.pixelBuffer)
        if density > maxEdgeDensity {
            return SCRuleResult(passed: false,
                                message: "Too much detail in frame — clear the surface",
                                severity: severity)
        }

        // ── Signal 2: Objectness saliency ────────────────────────────────────────
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
            return SCRuleResult(passed: true, message: "Background clear", severity: severity)
        }

        let count     = objects.count
        let totalArea = objects.reduce(Float(0)) { sum, obj in
            sum + Float(obj.boundingBox.width * obj.boundingBox.height)
        }
        let tooMany    = count > maxSalientRegions
        let tooCrowded = count >= 2 && totalArea > maxCoverageRatio

        if tooMany || tooCrowded {
            return SCRuleResult(passed: false,
                                message: "Too many objects in frame — simplify the background",
                                severity: severity)
        }
        return SCRuleResult(passed: true, message: "Background clear", severity: severity)
    }

    // MARK: - Private

    /// Returns the fraction of a coarse-grid sample where the discrete Laplacian
    /// exceeds the edge threshold (30). Supports YUV biplanar (AVFoundation) via the
    /// Y plane, and BGRA via the green channel. A step of ~1/36 of the shorter dimension
    /// gives ~36×36 sample points on a 1080 p frame — well within the 80 ms rule budget.
    private func edgeDensity(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch fmt {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
            let w   = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let h   = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            return laplacianDensity(ptr: yBase.assumingMemoryBound(to: UInt8.self),
                                    w: w, h: h, bpr: bpr,
                                    pixelStride: 1, channelOffset: 0)
        default:
            // kCVPixelFormatType_32BGRA: B G R A — index 1 = green channel.
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
            let w   = CVPixelBufferGetWidth(pixelBuffer)
            let h   = CVPixelBufferGetHeight(pixelBuffer)
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            return laplacianDensity(ptr: base.assumingMemoryBound(to: UInt8.self),
                                    w: w, h: h, bpr: bpr,
                                    pixelStride: 4, channelOffset: 1)
        }
    }

    /// Computes the discrete 5-point Laplacian on a coarse grid and returns the fraction
    /// of sample points where |4·C − N − S − E − W| > 30.
    ///
    /// - Parameters:
    ///   - pixelStride:   Bytes between horizontally adjacent pixels (1 for Y-plane, 4 for BGRA).
    ///   - channelOffset: Byte offset to the target channel within each pixel.
    private func laplacianDensity(ptr: UnsafePointer<UInt8>,
                                  w: Int, h: Int, bpr: Int,
                                  pixelStride: Int, channelOffset: Int) -> Float {
        let step          = max(4, min(w, h) / 36)
        let edgeThreshold = 30
        var edgeCount     = 0
        var totalCount    = 0

        for y in Swift.stride(from: step, to: h - step, by: step) {
            for x in Swift.stride(from: step, to: w - step, by: step) {
                let c  = Int(ptr[ y         * bpr +  x         * pixelStride + channelOffset])
                let n  = Int(ptr[(y - step) * bpr +  x         * pixelStride + channelOffset])
                let s  = Int(ptr[(y + step) * bpr +  x         * pixelStride + channelOffset])
                let e  = Int(ptr[ y         * bpr + (x + step) * pixelStride + channelOffset])
                let ww = Int(ptr[ y         * bpr + (x - step) * pixelStride + channelOffset])
                if abs(4 * c - n - s - e - ww) > edgeThreshold { edgeCount += 1 }
                totalCount += 1
            }
        }
        return totalCount > 0 ? Float(edgeCount) / Float(totalCount) : 0
    }
}
