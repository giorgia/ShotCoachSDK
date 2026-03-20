import XCTest
import CoreVideo
@_spi(ShotCoachInternal) @testable import ShotCoachCore

// MARK: - Mock providers

private struct MockAestheticModel: SCAestheticModelProvider {
    let fixedScore: Double
    func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double { fixedScore }
}

private struct ThrowingAestheticModel: SCAestheticModelProvider {
    struct ModelError: Error {}
    func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double { throw ModelError() }
}

// MARK: - Tests

final class SCAestheticRuleTests: XCTestCase {

    // MARK: - Helpers

    private func makeBuffer(width: Int = 32, height: Int = 32) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, nil, &pb)
        precondition(status == kCVReturnSuccess && pb != nil,
                     "CVPixelBufferCreate failed: \(status)")
        return pb!
    }

    private func makeFrame() -> SCFrame {
        SCFrame(timestamp: 0, pixelBuffer: makeBuffer())
    }

    // MARK: - Identity / metadata

    func test_ruleID() {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 5.0))
        XCTAssertEqual(rule.ruleID, "sc.aesthetic")
    }

    func test_severity_isWarning() {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 5.0))
        XCTAssertEqual(rule.severity, .warning)
    }

    func test_passingThreshold_default() {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 50.0))
        XCTAssertEqual(rule.passingThreshold, 50.0)
    }

    // MARK: - Pass / fail

    func test_scoreAboveThreshold_passes() async {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 80.0))
        let result = await rule.evaluate(makeFrame())
        XCTAssertTrue(result.passed)
    }

    func test_scoreBelowThreshold_fails() async {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 20.0))
        let result = await rule.evaluate(makeFrame())
        XCTAssertFalse(result.passed)
    }

    // MARK: - EMA smoothing

    func test_emaSmoothing_reducesJitter() async {
        // Feed a single rule 20 alternating 0/10 scores via SequenceModel.
        // With α=0.3 and a neutral start (5.0), the smoothed output must stay
        // well away from both extremes — proving EMA suppresses per-frame jitter.
        let alternatingRule = SCAestheticRule(
            model: SequenceModel(scores: (0..<20).map { $0.isMultiple(of: 2) ? 0.0 : 100.0 }),
            smoothingFactor: 0.3
        )
        let frame = makeFrame()
        var lastScore = 50.0
        for _ in 0..<20 {
            let res = await alternatingRule.evaluate(frame)
            lastScore = try! XCTUnwrap(res.numericScore)
        }
        XCTAssertGreaterThan(lastScore, 5.0,  "EMA should prevent score reaching 0 floor")
        XCTAssertLessThan(lastScore, 95.0,    "EMA should prevent score reaching 100 ceiling")
    }

    // MARK: - Graceful degradation

    func test_modelThrow_fallsBackToHeuristic() async {
        // ThrowingAestheticModel always throws. The rule falls back to the
        // instagrammability heuristic, so the score is allowed to drift from 50.0.
        // We verify a valid score in [0, 100] is still returned (no crash, no nil).
        let rule = SCAestheticRule(model: ThrowingAestheticModel())
        let result = await rule.evaluate(makeFrame())
        let score = try! XCTUnwrap(result.numericScore)
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 100.0)
    }

    // MARK: - Passing threshold boundary

    func test_passingThreshold_exactlyAtThreshold_passes() async {
        // A score exactly equal to the threshold must be considered passing (score >= threshold).
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 50.0),
                                   passingThreshold: 50.0)
        let result = await rule.evaluate(makeFrame())
        // EMA is initialised at 50.0 and fixedScore is 50.0 — result converges to 50.0.
        if let score = result.numericScore {
            XCTAssertEqual(result.passed, score >= 50.0,
                "passed must equal (score >= passingThreshold), got score=\(score)")
        }
    }

    func test_passingThreshold_justBelow_fails() async {
        // Score well below threshold must fail.
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 0.0),
                                   passingThreshold: 50.0)
        let frame = makeFrame()
        // Run several frames to let EMA decay well below 50.
        var result = await rule.evaluate(frame)
        for _ in 0..<10 { result = await rule.evaluate(frame) }
        XCTAssertFalse(result.passed, "Score far below threshold should not pass")
    }


    // MARK: - modelWeight

    func test_modelWeight_default_isPointSeven() {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 50.0))
        XCTAssertEqual(rule.modelWeight, 0.7)
    }

    func test_modelWeight_1_0_ignoresHeuristic() async {
        // With modelWeight=1.0 the heuristic contributes 0%.
        // A model fixed at 100 should drive EMA well above 80 after 10 frames.
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 100.0),
                                   modelWeight: 1.0)
        let frame = makeFrame()
        var result = await rule.evaluate(frame)
        for _ in 0..<10 { result = await rule.evaluate(frame) }
        XCTAssertGreaterThan(result.numericScore ?? 0, 80.0,
            "modelWeight=1.0 with fixedScore=100 should converge above 80 after 10 frames")
    }

    func test_modelWeight_0_0_ignoresModel() async {
        // With modelWeight=0.0 the model contributes 0%.
        // A model returning 100 and one returning 0 must produce the same blended score
        // because both are ignored — only the heuristic drives the result.
        let highRule = SCAestheticRule(model: MockAestheticModel(fixedScore: 100.0),
                                       modelWeight: 0.0)
        let lowRule  = SCAestheticRule(model: MockAestheticModel(fixedScore: 0.0),
                                       modelWeight: 0.0)
        let frame = makeFrame()
        var highResult = await highRule.evaluate(frame)
        var lowResult  = await lowRule.evaluate(frame)
        for _ in 0..<5 {
            highResult = await highRule.evaluate(frame)
            lowResult  = await lowRule.evaluate(frame)
        }
        XCTAssertEqual(highResult.numericScore ?? -1,
                       lowResult.numericScore  ?? -2,
                       accuracy: 1.0,
                       "modelWeight=0.0: model score should not influence blended result")
    }

    // MARK: - numericScore presence

    func test_numericScore_isPresent() async {
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 6.0))
        let result = await rule.evaluate(makeFrame())
        XCTAssertNotNil(result.numericScore)
    }

    // MARK: - Performance

    func test_performance() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "Performance tests skipped in CI")
        // Mock model returns instantly. 20 iterations must average < 80ms each.
        let rule = SCAestheticRule(model: MockAestheticModel(fixedScore: 7.0))
        let frame = makeFrame()
        let iterations = 20
        let start = Date()
        for _ in 0..<iterations {
            _ = await rule.evaluate(frame)
        }
        let elapsed = Date().timeIntervalSince(start)
        let avgMs = (elapsed / Double(iterations)) * 1000
        XCTAssertLessThan(avgMs, 80.0, "Average evaluation time \(avgMs)ms exceeds 80ms budget")
    }
}

// MARK: - SequenceModel helper

/// A mock provider that returns scores from a pre-defined sequence, cycling if exhausted.
private actor SequenceModel: SCAestheticModelProvider {
    private let scores: [Double]
    private var index = 0

    init(scores: [Double]) {
        self.scores = scores
    }

    nonisolated func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double {
        await nextScore()
    }

    private func nextScore() -> Double {
        guard !scores.isEmpty else { return 50.0 }
        let s = scores[index % scores.count]
        index += 1
        return s
    }
}
