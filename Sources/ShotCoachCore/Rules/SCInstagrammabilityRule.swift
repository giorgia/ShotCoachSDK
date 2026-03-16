import Foundation
import Vision
import CoreVideo

/// Scores frames on a 0–100 instagrammability scale using a single
/// `VNGenerateAttentionBasedSaliencyImageRequest` and four weighted dimensions:
///
/// | Dimension            | Weight | Signal                                           |
/// |----------------------|--------|--------------------------------------------------|
/// | Focal clarity        | 0.40   | Salient-object count + confidence concentration  |
/// | Compositional balance| 0.25   | Weighted centroid distance to thirds-intersections |
/// | Visual variety       | 0.20   | Coefficient of variation across 3×3 heatmap cells |
/// | Lighting quality     | 0.15   | Direct luminance sampling (Rec.709)              |
///
/// Unlike `SCClutterRule`, this rule rewards intentional design — a gallery wall
/// with good lighting and a clear focal subject scores high, not low.
///
/// - Note: Dimension weights (focal 40%, balance 25%, variety 20%, lighting 15%) are
///   v1 heuristics calibrated for real-estate interiors. They may be refined in a future
///   release once real-world usage data is available.
public struct SCInstagrammabilityRule: SCFrameRule {

    public var ruleID: String { "sc.instagrammability" }
    public var severity: SCRuleSeverity { .warning }
    public var feedbackMessage: String { "Improve composition" }

    /// Score threshold in [0, 100] above which the rule is considered passing.
    public let passingThreshold: Double

    public init(passingThreshold: Double = 50.0) {
        self.passingThreshold = passingThreshold
    }

    // MARK: - SCFrameRule

    public func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        // Single Vision request used by focal-clarity, compositional-balance,
        // and visual-variety dimensions.
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return SCRuleResult(passed: true,
                                message: "Instagrammability analysis unavailable",
                                severity: severity)
        }

        let observation = request.results?.first as? VNSaliencyImageObservation

        // Dimension scores [0, 1].
        let focalScore   = focalClarityScore(observation: observation)
        let balanceScore = compositionalBalanceScore(observation: observation)
        let varietyScore = visualVarietyScore(observation: observation)
        let lightScore   = lightingScore(pixelBuffer: frame.pixelBuffer)

        // Weighted composite → [0, 1], then scaled to [0, 100].
        // Weights: focal clarity carries more weight (composition matters most for
        // real-estate instagrammability); lighting is reduced because indoor rooms
        // almost always fall in an acceptable luma range, making it a near-free score.
        let composite = focalScore   * 0.40
                      + balanceScore * 0.25
                      + varietyScore * 0.20
                      + lightScore   * 0.15
        let score = composite * 100.0

        let label = scoreLabel(score)
        let suggestion = weakestSuggestion(focal: focalScore,
                                           balance: balanceScore,
                                           variety: varietyScore,
                                           light: lightScore)
        let message = "\(label) · \(suggestion)"

        return SCRuleResult(
            passed: score >= passingThreshold,
            message: message,
            severity: severity,
            numericScore: score
        )
    }

    // MARK: - Dimension: Focal clarity

    /// Rewards a single high-confidence salient object; penalises many objects
    /// with dispersed confidence.
    ///
    /// - No salient objects → 0.
    /// - One object with confidence ≥ 0.8 → 1.0.
    /// - Score decreases as count rises and/or confidence disperses.
    private func focalClarityScore(observation: VNSaliencyImageObservation?) -> Double {
        guard let objects = observation?.salientObjects, !objects.isEmpty else { return 0 }
        let count = objects.count
        // Concentration: how much of the total confidence sits in the top object.
        let sorted = objects.sorted { $0.confidence > $1.confidence }
        let topConf = Double(sorted[0].confidence)
        let total   = objects.reduce(0.0) { $0 + Double($1.confidence) }
        let concentration = total > 0 ? topConf / total : 0

        // Single strong subject: high concentration + high top confidence.
        let clarityRaw = concentration * topConf
        // Penalise by object count (log scale so 2 objects isn't heavily penalised).
        let countPenalty = 1.0 / (1.0 + log(Double(count)))
        return min(1.0, clarityRaw * countPenalty / 0.55)   // normalise so ~0.55 raw = 1.0
    }

    // MARK: - Dimension: Compositional balance

    /// Distances the weighted centroid of salient bounding boxes from the four
    /// rule-of-thirds intersections (0.33/0.67 × 0.33/0.67).
    private static let thirdsPoints: [(Double, Double)] = [
        (1.0/3, 1.0/3), (2.0/3, 1.0/3),
        (1.0/3, 2.0/3), (2.0/3, 2.0/3),
    ]

    private func compositionalBalanceScore(observation: VNSaliencyImageObservation?) -> Double {
        guard let objects = observation?.salientObjects, !objects.isEmpty else {
            // No objects — treat as neutral composition (mid score).
            return 0.5
        }
        // Weighted centroid.
        var sumX = 0.0, sumY = 0.0, sumW = 0.0
        for obj in objects {
            let w = Double(obj.confidence)
            sumX += Double(obj.boundingBox.midX) * w
            sumY += Double(obj.boundingBox.midY) * w
            sumW += w
        }
        guard sumW > 0 else { return 0.5 }
        let cx = sumX / sumW
        let cy = sumY / sumW

        // Nearest thirds-intersection distance.
        let minDist = Self.thirdsPoints.map { pt in
            hypot(cx - pt.0, cy - pt.1)
        }.min() ?? 1.0

        // Distance 0 → 1.0; distance ≥ 0.35 → 0.
        let score = max(0.0, 1.0 - (minDist / 0.35))
        return score
    }

    // MARK: - Dimension: Visual variety (heatmap 3×3)

    /// Samples the saliency heatmap into a 3×3 grid and computes the coefficient of
    /// variation (stdDev / mean) across the 9 cell means.
    /// CV ≥ 0.5 → 1.0 (high variety); CV ≤ 0.05 → 0 (uniform, flat).
    private func visualVarietyScore(observation: VNSaliencyImageObservation?) -> Double {
        guard let obs = observation else { return 0.5 }
        let pixelBuffer = obs.pixelBuffer

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        // Saliency maps are typically 1-channel float or 8-bit greyscale.
        // We handle both; fall back to 0.5 on unknown formats.
        let w   = CVPixelBufferGetWidth(pixelBuffer)
        let h   = CVPixelBufferGetHeight(pixelBuffer)
        guard w > 0, h > 0 else { return 0.5 }

        var cellMeans = [Double](repeating: 0, count: 9)
        let cellW = w / 3
        let cellH = h / 3

        switch fmt {
        case kCVPixelFormatType_OneComponent8:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for row in 0..<3 {
                for col in 0..<3 {
                    var sum = 0.0, n = 0
                    for y in (row * cellH)..<((row + 1) * cellH) {
                        for x in (col * cellW)..<((col + 1) * cellW) {
                            sum += Double(ptr[y * bpr + x]) / 255.0
                            n += 1
                        }
                    }
                    cellMeans[row * 3 + col] = n > 0 ? sum / Double(n) : 0
                }
            }
        case kCVPixelFormatType_OneComponent32Float:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
            let ptr = base.assumingMemoryBound(to: Float.self)
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let floatsPerRow = bpr / MemoryLayout<Float>.size
            for row in 0..<3 {
                for col in 0..<3 {
                    var sum = 0.0, n = 0
                    for y in (row * cellH)..<((row + 1) * cellH) {
                        for x in (col * cellW)..<((col + 1) * cellW) {
                            sum += Double(ptr[y * floatsPerRow + x])
                            n += 1
                        }
                    }
                    cellMeans[row * 3 + col] = n > 0 ? sum / Double(n) : 0
                }
            }
        default:
            return 0.5  // Unknown saliency buffer format — neutral score.
        }

        let mean = cellMeans.reduce(0, +) / 9.0
        guard mean > 0 else { return 0 }
        let variance = cellMeans.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 9.0
        let cv = sqrt(variance) / mean
        // CV ≥ 0.5 → 1.0; CV ≤ 0.05 → 0.
        return max(0.0, min(1.0, (cv - 0.05) / (0.5 - 0.05)))
    }

    // MARK: - Dimension: Lighting quality

    /// Scores 1.0 when average luminance is in [0.35, 0.65]; linear falloff outside.
    /// Narrower than `SCBrightnessRule`'s pass band — rewards well-exposed scenes
    /// without giving a free pass to any non-dark, non-blown frame.
    private func lightingScore(pixelBuffer: CVPixelBuffer) -> Double {
        let luma = Double(averageLuminance(of: pixelBuffer))
        if luma >= 0.35, luma <= 0.65 { return 1.0 }
        if luma < 0.35 { return luma / 0.35 }
        // luma > 0.65
        return (1.0 - luma) / 0.35
    }

    private func averageLuminance(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch fmt {
        // kCVPixelFormatType_32BGRA falls into the default branch below.
        // The default branch assumes BGRA byte order (B=off+0, G=off+1, R=off+2)
        // which is correct for BGRA buffers delivered by AVFoundation and CVPixelBuffer.
        // If the buffer is RGBA or ARGB the luminance weights will be applied to the
        // wrong channels — add an explicit case before `default` if other formats arise.
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0.5 }
            let w    = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let h    = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bpr  = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let ptr  = yBase.assumingMemoryBound(to: UInt8.self)
            let isFullRange = (fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            let yMin: Float   = isFullRange ? 0   : 16
            let yRange: Float = isFullRange ? 255 : 219
            let stepX = max(1, w / 32)
            let stepY = max(1, h / 32)
            var total: Float = 0; var n = 0
            for y in stride(from: 0, to: h, by: stepY) {
                for x in stride(from: 0, to: w, by: stepX) {
                    total += max(0, min(1, (Float(ptr[y * bpr + x]) - yMin) / yRange))
                    n += 1
                }
            }
            return n > 0 ? total / Float(n) : 0.5
        default:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
            let w   = CVPixelBufferGetWidth(pixelBuffer)
            let h   = CVPixelBufferGetHeight(pixelBuffer)
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let stepX = max(1, w / 32)
            let stepY = max(1, h / 32)
            var total: Float = 0; var n = 0
            for y in stride(from: 0, to: h, by: stepY) {
                for x in stride(from: 0, to: w, by: stepX) {
                    let off = y * bpr + x * 4
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

    // MARK: - Helpers

    private func scoreLabel(_ score: Double) -> String {
        switch score {
        case 80.0...: return "Stunning"
        case 65.0...: return "Great"
        case 50.0...: return "Good"
        case 30.0...: return "Needs Work"
        default:      return "Poor"
        }
    }

    /// Returns the improvement suggestion for the weakest dimension.
    private func weakestSuggestion(focal: Double, balance: Double,
                                   variety: Double, light: Double) -> String {
        let dims: [(Double, String)] = [
            (focal,   "Create a clear focal subject"),
            (balance, "Move focal point to a thirds intersection"),
            (variety, "Add visual interest to the frame"),
            (light,   "Adjust lighting for the ideal exposure"),
        ]
        // Find the dimension with the lowest score.
        let weakest = dims.min { $0.0 < $1.0 } ?? dims[0]
        return weakest.1
    }
}
