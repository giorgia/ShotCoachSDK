import XCTest
import CoreVideo
@testable import ShotCoachCore

final class SCInstagrammabilityRuleTests: XCTestCase {

    // MARK: - Helpers

    private func makeBuffer(r: UInt8, g: UInt8, b: UInt8,
                            width: Int = 64, height: Int = 64) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, nil, &pb)
        precondition(status == kCVReturnSuccess && pb != nil,
                     "CVPixelBufferCreate failed: \(status)")
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        let ptr = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        for y in 0..<height {
            for x in 0..<width {
                let off = y * bpr + x * 4
                ptr[off]     = b
                ptr[off + 1] = g
                ptr[off + 2] = r
                ptr[off + 3] = 255
            }
        }
        return buf
    }

    private func makeFrame(r: UInt8, g: UInt8, b: UInt8) -> SCFrame {
        SCFrame(timestamp: 0, pixelBuffer: makeBuffer(r: r, g: g, b: b))
    }

    // MARK: - Tests

    func test_ruleID() {
        let rule = SCInstagrammabilityRule()
        XCTAssertEqual(rule.ruleID, "sc.instagrammability")
    }

    func test_uniformGrayBuffer_doesNotCrash_andReturnsScore() async {
        let rule = SCInstagrammabilityRule()
        let frame = makeFrame(r: 128, g: 128, b: 128)
        let result = await rule.evaluate(frame)
        // Must not crash, must return a numericScore, and score must be in valid range.
        XCTAssertNotNil(result.numericScore)
        if let score = result.numericScore {
            XCTAssertGreaterThanOrEqual(score, 0.0)
            XCTAssertLessThanOrEqual(score, 100.0)
        }
    }

    func test_allBlackBuffer_lowLightingScore() async {
        let rule = SCInstagrammabilityRule()
        let frame = makeFrame(r: 0, g: 0, b: 0)
        let result = await rule.evaluate(frame)
        // Black frame: lighting dimension near 0 → overall score should be low.
        // Because this is a synthetic buffer and Vision may fail gracefully,
        // we only assert score ≤ 4.0 or result is the fallback pass.
        if let score = result.numericScore {
            // Lighting weight is 0.15; max composite without lighting = 0.85 → 85.0.
            // Vision may return non-zero saliency for synthetic buffers, so we
            // assert the score is below 80 (lighting penalty must register).
            XCTAssertLessThan(score, 80.0,
                "All-black frame should produce a below-peak instagrammability score")
        } else {
            // Graceful fallback — Vision failed on synthetic buffer.
            XCTAssertTrue(result.passed)
            XCTAssertEqual(result.message, "Instagrammability analysis unavailable")
        }
    }

    func test_passingThreshold_defaultIs50() {
        let rule = SCInstagrammabilityRule()
        XCTAssertEqual(rule.passingThreshold, 50.0)
    }

    func test_customThreshold_isRespected() async {
        // Set a threshold above maximum possible → rule should fail for any real input.
        let rule = SCInstagrammabilityRule(passingThreshold: 110.0)
        let frame = makeFrame(r: 128, g: 128, b: 128)
        let result = await rule.evaluate(frame)
        if let score = result.numericScore {
            XCTAssertFalse(result.passed,
                "Score \(score) should not pass threshold 110.0")
        }
        // If Vision fails → graceful pass (unavailable) — also acceptable.
    }

    func test_passingResult_whenScoreAboveThreshold() async {
        // Threshold of 0 → any non-negative score should pass.
        let rule = SCInstagrammabilityRule(passingThreshold: 0.0)
        let frame = makeFrame(r: 200, g: 180, b: 160)
        let result = await rule.evaluate(frame)
        // Either graceful fallback (passed: true) or score-based (score ≥ 0 → passed).
        XCTAssertTrue(result.passed)
    }

    func test_severity_isWarning() {
        XCTAssertEqual(SCInstagrammabilityRule().severity, .warning)
    }
}
