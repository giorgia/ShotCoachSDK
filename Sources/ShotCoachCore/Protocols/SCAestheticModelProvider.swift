import CoreVideo

/// Conforming types wrap a CoreML aesthetic model and produce a score in [0, 100].
/// The SDK ships no model — conformances live in the app target alongside the
/// `.mlpackage` resource.
///
/// - Note: Marked `@_spi(ShotCoachInternal)` — semi-stable. The aesthetic model
///   API will evolve as additional verticals ship. Import with:
///   `@_spi(ShotCoachInternal) import ShotCoachCore`
@_spi(ShotCoachInternal)
public protocol SCAestheticModelProvider: Sendable {
    func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double
}
