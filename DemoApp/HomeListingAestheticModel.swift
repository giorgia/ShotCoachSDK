import CoreML
import CoreImage
import CoreVideo
import UIKit
@_spi(ShotCoachInternal) import ShotCoachCore

/// Concrete `SCAestheticModelProvider` for the Home Listing vertical.
///
/// Two CoreML models are chained at inference time:
///   1. **MobileClip S0** (`mobileclip_s0_image`) — encodes a 256×256 pixel buffer
///      into a 512-D CLIP embedding (output feature: `var_5`).
///   2. **HomeHead S0** (`home_head_s0`) — maps the embedding to a sigmoid
///      probability in [0, 1] (output feature: `var_5`), scaled to [0, 10].
///
/// Both `.mlpackage` files live in the SDK's `MLModels/` directory and must be added
/// to the app target's bundle (drag into Xcode → target membership = ShotCoachDemo).
final class HomeListingAestheticModel: SCAestheticModelProvider {

    // MARK: - Stored

    private let clipModel: MLModel
    private let headModel: MLModel
    private let clipInputName: String
    private let clipOutputName: String
    private let headInputName: String
    private let headOutputName: String
    /// Reused across frames — CIContext creation is expensive.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Init

    /// Loads both models from the main bundle.
    /// - Throws: `LoadError.bundleResourceNotFound` if either `.mlmodelc` is missing,
    ///   or a CoreML error if the model file is corrupt or incompatible.
    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        guard
            let clipURL = Bundle.main.url(forResource: "mobileclip_s0_image", withExtension: "mlmodelc")
                       ?? Bundle.main.url(forResource: "mobileclip_s0_image", withExtension: "mlmodelc", subdirectory: "MLModels"),
            let headURL = Bundle.main.url(forResource: "home_head_s0", withExtension: "mlmodelc")
                       ?? Bundle.main.url(forResource: "home_head_s0", withExtension: "mlmodelc", subdirectory: "MLModels")
        else { throw LoadError.bundleResourceNotFound }

        clipModel = try MLModel(contentsOf: clipURL, configuration: config)
        headModel = try MLModel(contentsOf: headURL, configuration: config)

        // Read feature names from the compiled models at init time.
        // Both MobileClip S0 and HomeHead S0 are single-input/single-output models,
        // so `.keys.first` is deterministic. The fallback literals match the known
        // feature names and guard against an unexpected empty description dictionary.
        clipInputName  = clipModel.modelDescription.inputDescriptionsByName.keys.first  ?? "image"
        clipOutputName = clipModel.modelDescription.outputDescriptionsByName.keys.first ?? "embedding"
        headInputName  = headModel.modelDescription.inputDescriptionsByName.keys.first  ?? "embedding"
        headOutputName = headModel.modelDescription.outputDescriptionsByName.keys.first ?? "var_5"

    }

    // MARK: - SCAestheticModelProvider

    func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double {
        return try await runModels(on: resizeCIImage(CIImage(cvPixelBuffer: pixelBuffer)))
    }

    /// Scores a JPEG/HEIC/PNG image. Uses CIImage so orientation is respected.
    func score(imageData: Data) async throws -> Double {
        guard let uiImage = UIImage(data: imageData),
              let ciImage = CIImage(image: uiImage) else { throw LoadError.resizeFailed }
        return try await runModels(on: resizeCIImage(ciImage))
    }

    // MARK: - Private

    /// Scales any CIImage to 256×256 into an IOSurface-backed BGRA buffer.
    /// IOSurface backing is required for GPU-accelerated CIContext rendering
    /// and for CoreML Neural Engine inference.
    private func resizeCIImage(_ ciImage: CIImage) throws -> CVPixelBuffer {
        let src = ciImage.extent
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 256 / src.width,
                                                               y:     256 / src.height))
        // Translate so the image origin sits at (0, 0) in the buffer.
        let atOrigin = scaled.transformed(by: CGAffineTransform(
            translationX: -scaled.extent.origin.x,
            y:            -scaled.extent.origin.y
        ))
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]]
        var dst: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 256, 256,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &dst)
        guard let dst else { throw LoadError.resizeFailed }
        ciContext.render(atOrigin, to: dst,
                         bounds: CGRect(x: 0, y: 0, width: 256, height: 256),
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        return dst
    }

    private func runModels(on pixelBuffer: CVPixelBuffer) async throws -> Double {
        let clipFeatures = try MLDictionaryFeatureProvider(
            dictionary: [clipInputName: MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let clipOut = try await clipModel.prediction(from: clipFeatures)
        guard let embedding = clipOut.featureValue(for: clipOutputName)?.multiArrayValue else {
            throw LoadError.unexpectedModelOutput
        }

        let headFeatures = try MLDictionaryFeatureProvider(
            dictionary: [headInputName: MLFeatureValue(multiArray: embedding)]
        )
        let headOut = try await headModel.prediction(from: headFeatures)
        guard let fv = headOut.featureValue(for: headOutputName) else {
            throw LoadError.unexpectedModelOutput
        }

        let raw = fv.multiArrayValue.map { $0[0].doubleValue } ?? fv.doubleValue
        // Gamma calibration (γ < 1) lifts lower model outputs toward a more intuitive
        // 0–10 scale. HomeHead S0 probabilities cluster in [0.2, 0.6] for typical
        // home listing photos, so without calibration scores feel "too low".
        // γ = 0.6: raw=0.3→49, raw=0.5→66, raw=0.7→81
        let calibrated = pow(max(0.0, min(1.0, raw)), 0.6)
        return calibrated * 100.0
    }


    // MARK: - Errors

    enum LoadError: Error {
        case bundleResourceNotFound
        case unexpectedModelOutput
        case resizeFailed
    }
}

// `MLModel` is not formally `Sendable`, but `HomeListingAestheticModel` is
// immutable after `init` — all properties are `let` and `CIContext` is
// thread-safe per Apple documentation. Safe to cross actor boundaries.
extension HomeListingAestheticModel: @unchecked Sendable {}

