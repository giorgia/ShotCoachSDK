import CoreML
import CoreImage
import CoreVideo
import UIKit
@_spi(ShotCoachInternal) import ShotCoachCore

/// Generic `SCAestheticModelProvider` backed by `aesthetic_head_v2`.
///
/// Two CoreML models are chained at inference time:
///   1. **MobileClip S0** (`mobileclip_s0_image`) — encodes a 256×256 pixel buffer
///      into a 512-D CLIP embedding.
///   2. **Aesthetic Head V2** (`aesthetic_head_v2`) — maps the embedding to a score
///      in [0, 100]. Normalization is baked into the CoreML model; no calibration
///      is applied here.
///
/// Both `.mlpackage` files live in `DemoApp/MLModels/` and must be added to the app
/// target's bundle (drag into Xcode → target membership = ShotCoachDemo).
final class GenericAestheticModel: SCAestheticModelProvider {

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
            let headURL = Bundle.main.url(forResource: "aesthetic_head_v2", withExtension: "mlmodelc")
                       ?? Bundle.main.url(forResource: "aesthetic_head_v2", withExtension: "mlmodelc", subdirectory: "MLModels")
        else { throw LoadError.bundleResourceNotFound }

        clipModel = try MLModel(contentsOf: clipURL, configuration: config)
        headModel = try MLModel(contentsOf: headURL, configuration: config)

        clipInputName  = clipModel.modelDescription.inputDescriptionsByName.keys.first  ?? "image"
        clipOutputName = clipModel.modelDescription.outputDescriptionsByName.keys.first ?? "final_emb_1"
        headInputName  = headModel.modelDescription.inputDescriptionsByName.keys.first  ?? "embedding"
        headOutputName = headModel.modelDescription.outputDescriptionsByName.keys.first ?? "score"
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
    private func resizeCIImage(_ ciImage: CIImage) throws -> CVPixelBuffer {
        let src = ciImage.extent
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 256 / src.width,
                                                               y:     256 / src.height))
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

        // aesthetic_head_v2 outputs a score already in [0, 100] — no calibration needed.
        return fv.multiArrayValue.map { $0[0].doubleValue } ?? fv.doubleValue
    }

    // MARK: - Errors

    enum LoadError: Error {
        case bundleResourceNotFound
        case unexpectedModelOutput
        case resizeFailed
    }
}

// `MLModel` is not formally `Sendable`, but `GenericAestheticModel` is
// immutable after `init` — all properties are `let` and `CIContext` is
// thread-safe per Apple documentation.
extension GenericAestheticModel: @unchecked Sendable {}
