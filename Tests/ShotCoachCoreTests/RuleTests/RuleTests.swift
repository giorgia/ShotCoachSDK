import XCTest
import CoreVideo
@testable import ShotCoachCore

final class RuleTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a solid-colour 64×64 kCVPixelFormatType_32BGRA pixel buffer.
    private func makeSolid(r: UInt8, g: UInt8, b: UInt8,
                           width: Int = 64, height: Int = 64) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        let ptr = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        for y in 0..<height {
            for x in 0..<width {
                let off = y * bpr + x * 4
                ptr[off]     = b    // B
                ptr[off + 1] = g    // G
                ptr[off + 2] = r    // R
                ptr[off + 3] = 255  // A
            }
        }
        return buf
    }

    /// Creates a 1px-checkerboard 64×64 BGRA pixel buffer (maximum sharpness).
    private func makeCheckerboard(width: Int = 64, height: Int = 64) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        let ptr = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                let off = y * bpr + x * 4
                ptr[off] = v; ptr[off + 1] = v; ptr[off + 2] = v; ptr[off + 3] = 255
            }
        }
        return buf
    }

    private func frame(_ pb: CVPixelBuffer) -> SCFrame {
        SCFrame(timestamp: 0, pixelBuffer: pb)
    }

    // MARK: - SCBrightnessRule

    func testBrightness_darkFails() async {
        let result = await SCBrightnessRule().evaluate(frame(makeSolid(r: 0, g: 0, b: 0)))
        XCTAssertFalse(result.passed)
    }

    func testBrightness_overexposedFails() async {
        let result = await SCBrightnessRule().evaluate(frame(makeSolid(r: 255, g: 255, b: 255)))
        XCTAssertFalse(result.passed)
    }

    func testBrightness_midGrayPasses() async {
        let result = await SCBrightnessRule().evaluate(frame(makeSolid(r: 128, g: 128, b: 128)))
        XCTAssertTrue(result.passed)
    }

    func testBrightness_ruleID() {
        XCTAssertEqual(SCBrightnessRule().ruleID, "sc.brightness")
    }

    func testBrightness_performance() async {
        let rule  = SCBrightnessRule()
        let f     = frame(makeSolid(r: 128, g: 128, b: 128))
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = await rule.evaluate(f) }
        let avg = (ContinuousClock.now - start) / 20
        XCTAssertLessThan(avg, .milliseconds(80), "SCBrightnessRule exceeded 80 ms average")
    }

    // MARK: - SCBlurRule

    func testBlur_solidColorFails() async {
        // Uniform frame has zero Laplacian variance → score 0 → fails any positive threshold.
        let result = await SCBlurRule(minSharpnessScore: 10).evaluate(frame(makeSolid(r: 128, g: 128, b: 128)))
        XCTAssertFalse(result.passed)
    }

    func testBlur_checkerboardPasses() async {
        let result = await SCBlurRule(minSharpnessScore: 10).evaluate(frame(makeCheckerboard()))
        XCTAssertTrue(result.passed)
    }

    func testBlur_ruleID() {
        XCTAssertEqual(SCBlurRule().ruleID, "sc.blur")
    }

    func testBlur_performance() async {
        let rule  = SCBlurRule()
        let f     = frame(makeCheckerboard())
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = await rule.evaluate(f) }
        let avg = (ContinuousClock.now - start) / 20
        XCTAssertLessThan(avg, .milliseconds(80), "SCBlurRule exceeded 80 ms average")
    }

    // MARK: - SCHorizonRule

    func testHorizon_uniformFramePasses() async {
        // Solid frame has no detectable horizon — rule should fail open.
        let result = await SCHorizonRule().evaluate(frame(makeSolid(r: 128, g: 128, b: 128)))
        XCTAssertTrue(result.passed)
    }

    func testHorizon_ruleID() {
        XCTAssertEqual(SCHorizonRule().ruleID, "sc.horizon")
    }

    func testHorizon_performance() async {
        let rule  = SCHorizonRule()
        let f     = frame(makeSolid(r: 128, g: 128, b: 128))
        _ = await rule.evaluate(f)  // warm up Vision
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = await rule.evaluate(f) }
        let avg = (ContinuousClock.now - start) / 20
        XCTAssertLessThan(avg, .milliseconds(80), "SCHorizonRule exceeded 80 ms average")
    }

    // MARK: - SCClutterRule

    func testClutter_uniformFramePasses() async {
        // Solid frame has no salient objects — should not be flagged as cluttered.
        let result = await SCClutterRule().evaluate(frame(makeSolid(r: 128, g: 128, b: 128)))
        XCTAssertTrue(result.passed)
    }

    func testClutter_ruleID() {
        XCTAssertEqual(SCClutterRule().ruleID, "sc.clutter")
    }

    func testClutter_performance() async {
        let rule  = SCClutterRule()
        let f     = frame(makeSolid(r: 128, g: 128, b: 128))
        _ = await rule.evaluate(f)  // warm up Vision
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = await rule.evaluate(f) }
        let avg = (ContinuousClock.now - start) / 20
        XCTAssertLessThan(avg, .milliseconds(80), "SCClutterRule exceeded 80 ms average")
    }

    // MARK: - SCDistanceRule

    func testDistance_uniformFramePasses() async {
        // No subject detectable → fail open.
        let result = await SCDistanceRule().evaluate(frame(makeSolid(r: 128, g: 128, b: 128)))
        XCTAssertTrue(result.passed)
    }

    func testDistance_ruleID() {
        XCTAssertEqual(SCDistanceRule().ruleID, "sc.distance")
    }

    func testDistance_performance() async {
        let rule  = SCDistanceRule()
        let f     = frame(makeSolid(r: 128, g: 128, b: 128))
        _ = await rule.evaluate(f)  // warm up Vision
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = await rule.evaluate(f) }
        let avg = (ContinuousClock.now - start) / 20
        XCTAssertLessThan(avg, .milliseconds(80), "SCDistanceRule exceeded 80 ms average")
    }

    // MARK: - SCReflectionRule

    func testReflection_noFacePasses() async {
        let result = await SCReflectionRule().evaluate(frame(makeSolid(r: 128, g: 128, b: 128)))
        XCTAssertTrue(result.passed)
    }

    func testReflection_ruleID() {
        XCTAssertEqual(SCReflectionRule().ruleID, "sc.reflection")
    }

    func testReflection_performance() async {
        let rule  = SCReflectionRule()
        let f     = frame(makeSolid(r: 128, g: 128, b: 128))
        _ = await rule.evaluate(f)  // warm up Vision
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = await rule.evaluate(f) }
        let avg = (ContinuousClock.now - start) / 20
        XCTAssertLessThan(avg, .milliseconds(80), "SCReflectionRule exceeded 80 ms average")
    }
}
