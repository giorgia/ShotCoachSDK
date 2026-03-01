import Combine
import AVFoundation
import ShotCoachCore

/// Observable facade that ties `SCCameraSession`, `SCFrameAnalyzer`, and
/// `SCOpenAIProvider` together for SwiftUI consumption.
///
/// ```swift
/// let sdk = ShotCoach(category: .homeListing, apiKey: "sk-...")
/// SCCameraGuidanceView(sdk: sdk)
///     .onResult { photo in print(photo.cloudResult?.score ?? 0) }
/// ```
@MainActor
public final class ShotCoach: ObservableObject {

    // MARK: - Published state

    /// Most-recent on-device frame analysis (updated ~every 1.5 s).
    @Published public private(set) var frameResult: SCFrameResult

    /// All photos captured this session, in capture order.
    /// Each photo's `cloudResult` is populated asynchronously after capture.
    @Published public private(set) var photos: [SCPhoto] = []

    /// The next required shot, or `nil` when all shots have been captured.
    @Published public private(set) var currentShot: SCShotType?

    /// True while a photo capture is in-flight; prevents double-tapping the shutter.
    @Published public private(set) var isCapturing = false

    // MARK: - Public read-only

    /// The category driving this session.
    public let category: any SCCategoryConfig

    /// The underlying `AVCaptureSession` — consumed by `AVCapturePreviewView`.
    public var captureSession: AVCaptureSession { cameraSession.nativeSession }

    // MARK: - Init

    /// Creates a fully configured coaching session.
    /// - Parameters:
    ///   - category: Defines required shots, on-device rules, and cloud prompts.
    ///   - apiKey:   OpenAI API key used for post-capture analysis. Store and load
    ///               it via `SCKeychainService` between launches; never hard-code it.
    public init(category: any SCCategoryConfig, apiKey: String) {
        self.category    = category
        self.currentShot = category.requiredShots.first
        self.frameResult = SCFrameResult(
            rules: [:],
            overallGuidance: "Initializing…",
            isReadyToCapture: false,
            processingMs: 0
        )
        self.cameraSession = SCCameraSession(
            category: category,
            cloudProvider: SCOpenAIProvider(apiKey: apiKey)
        )
        self.cameraSession.delegate = self
    }

    // MARK: - Session control

    /// Starts the camera capture session. Call when the guidance view appears.
    public func start() { cameraSession.start() }

    /// Stops the camera capture session. Call when the guidance view disappears.
    public func stop()  { cameraSession.stop() }

    /// Captures the current shot. The photo is appended to `photos` and the session
    /// advances to the next required shot once cloud analysis completes.
    /// Silently no-ops if a capture is already in-flight.
    public func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            _ = try? await cameraSession.capturePhoto()
            isCapturing = false
        }
    }

    // MARK: - Private

    private let cameraSession: SCCameraSession

    private func advanceShot() {
        guard let current = currentShot,
              let idx = category.requiredShots.firstIndex(of: current),
              idx + 1 < category.requiredShots.count else {
            currentShot = nil
            return
        }
        currentShot = category.requiredShots[idx + 1]
    }
}

// MARK: - SCAnalysisDelegate

extension ShotCoach: SCAnalysisDelegate {

    public func analyzer(_ analyzer: SCFrameAnalyzer, didUpdate result: SCFrameResult) {
        frameResult = result
    }

    public func analyzer(
        _ analyzer: SCFrameAnalyzer,
        didComplete photo: SCPhoto,
        cloudResult: SCCloudResult?
    ) {
        photos.append(photo)
        advanceShot()
    }
}
