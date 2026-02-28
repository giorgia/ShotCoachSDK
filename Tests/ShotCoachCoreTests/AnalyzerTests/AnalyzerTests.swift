import XCTest
import CoreVideo
@testable import ShotCoachCore

final class AnalyzerTests: XCTestCase {

    // MARK: - Test doubles

    /// Rule that always passes, instantly.
    private struct PassRule: SCFrameRule {
        let ruleID: String
        func evaluate(_ frame: SCFrame) async -> SCRuleResult {
            SCRuleResult(passed: true, message: "OK", severity: .info)
        }
    }

    /// Rule that always fails with the given severity.
    private struct FailRule: SCFrameRule {
        let ruleID: String
        let sev: SCRuleSeverity
        func evaluate(_ frame: SCFrame) async -> SCRuleResult {
            SCRuleResult(passed: false, message: "Failed: \(ruleID)", severity: sev)
        }
    }

    @MainActor
    private class SpyDelegate: SCAnalysisDelegate {
        var updates: [SCFrameResult] = []
        func analyzer(_ analyzer: SCFrameAnalyzer, didUpdate result: SCFrameResult) {
            updates.append(result)
        }
        func analyzer(_ analyzer: SCFrameAnalyzer, didComplete photo: SCPhoto, cloudResult: SCCloudResult?) {}
    }

    // MARK: - Helpers

    private func makeFrame() -> SCFrame {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 8, 8,
                                         kCVPixelFormatType_32BGRA, nil, &pb)
        precondition(status == kCVReturnSuccess && pb != nil, "CVPixelBufferCreate failed: \(status)")
        return SCFrame(timestamp: 0, pixelBuffer: pb!)
    }

    /// Flushes pending MainActor tasks scheduled by the analyzer's notifyDelegate.
    private func flushMainActor() async {
        await Task { @MainActor in }.value
    }

    // MARK: - Result aggregation

    func testAnalyzer_allPassMeansReady() async {
        let analyzer = SCFrameAnalyzer(rules: [PassRule(ruleID: "a"), PassRule(ruleID: "b")])
        let spy = await MainActor.run { SpyDelegate() }
        await analyzer.setDelegate(spy)

        await analyzer.analyze(makeFrame())
        await flushMainActor()

        let updates = await MainActor.run { spy.updates }
        XCTAssertEqual(updates.count, 1)
        XCTAssertTrue(updates[0].isReadyToCapture)
        XCTAssertEqual(updates[0].overallGuidance, "Ready to shoot")
    }

    func testAnalyzer_singleFailMeansNotReady() async {
        let analyzer = SCFrameAnalyzer(rules: [
            PassRule(ruleID: "pass"),
            FailRule(ruleID: "fail", sev: .warning)
        ])
        let spy = await MainActor.run { SpyDelegate() }
        await analyzer.setDelegate(spy)

        await analyzer.analyze(makeFrame())
        await flushMainActor()

        let updates = await MainActor.run { spy.updates }
        XCTAssertFalse(updates[0].isReadyToCapture)
        XCTAssertNotNil(updates[0].rules["fail"])
        XCTAssertEqual(updates[0].rules["fail"]?.passed, false)
    }

    func testAnalyzer_guidanceReflectsHighestSeverityFailure() async {
        let analyzer = SCFrameAnalyzer(rules: [
            FailRule(ruleID: "minor", sev: .warning),
            FailRule(ruleID: "major", sev: .critical)
        ])
        let spy = await MainActor.run { SpyDelegate() }
        await analyzer.setDelegate(spy)

        await analyzer.analyze(makeFrame())
        await flushMainActor()

        let updates = await MainActor.run { spy.updates }
        XCTAssertEqual(updates[0].overallGuidance, "Failed: major")
    }

    func testAnalyzer_allRuleIDsPresent() async {
        let analyzer = SCFrameAnalyzer(rules: [
            PassRule(ruleID: "r1"),
            FailRule(ruleID: "r2", sev: .info)
        ])
        let spy = await MainActor.run { SpyDelegate() }
        await analyzer.setDelegate(spy)

        await analyzer.analyze(makeFrame())
        await flushMainActor()

        let rules = await MainActor.run { spy.updates[0].rules }
        XCTAssertNotNil(rules["r1"])
        XCTAssertNotNil(rules["r2"])
    }

    // MARK: - Throttling

    func testAnalyzer_throttlesRapidCalls() async {
        let analyzer = SCFrameAnalyzer(rules: [])
        let spy = await MainActor.run { SpyDelegate() }
        await analyzer.setDelegate(spy)

        let frame = makeFrame()
        await analyzer.analyze(frame) // accepted
        await analyzer.analyze(frame) // throttled
        await analyzer.analyze(frame) // throttled
        await flushMainActor()

        let count = await MainActor.run { spy.updates.count }
        XCTAssertEqual(count, 1)
    }

    func testAnalyzer_acceptsCallAfterInterval() async throws {
        let analyzer = SCFrameAnalyzer(rules: [])
        let spy = await MainActor.run { SpyDelegate() }
        await analyzer.setDelegate(spy)

        let frame = makeFrame()
        await analyzer.analyze(frame)  // accepted
        await flushMainActor()

        // Bypass throttle by advancing past the 1500 ms window.
        await analyzer.resetThrottleForTesting()

        await analyzer.analyze(frame)  // accepted again
        await flushMainActor()

        let count = await MainActor.run { spy.updates.count }
        XCTAssertEqual(count, 2)
    }

    // MARK: - No delegate

    func testAnalyzer_noDelegateSilentlySucceeds() async {
        let analyzer = SCFrameAnalyzer(rules: [PassRule(ruleID: "x")])
        // No delegate set — must not crash.
        await analyzer.analyze(makeFrame())
    }
}
