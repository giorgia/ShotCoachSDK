import CoreVideo

/// Conforming types wrap a CoreML aesthetic model and produce a score in [0, 100].
/// The SDK ships no model — conformances live in the app target alongside the
/// `.mlpackage` resource.
public protocol SCAestheticModelProvider: Sendable {
    func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double
}
