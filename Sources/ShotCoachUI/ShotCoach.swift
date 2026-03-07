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

    /// Current zoom factor reflected from the camera device. Updated by `setZoom(_:)`.
    @Published public private(set) var zoomFactor: CGFloat = 1.0

    /// Current flash mode applied at capture time. Cycled by `cycleFlash()`.
    @Published public private(set) var flashMode: SCFlashMode = .auto

    /// The active camera lens. Toggled by `cycleLens()` / `switchLens(_:)`.
    /// Always `.main` on devices without an ultra-wide camera.
    @Published public private(set) var lensMode: SCLensMode = .main

    // MARK: - Public read-only

    /// The category driving this session.
    public let category: any SCCategoryConfig

    /// True when the device has a physical ultra-wide camera (iPhone 11+).
    /// Observe this before showing a lens-toggle control.
    public var isUltraWideAvailable: Bool { cameraSession.isUltraWideAvailable }

    /// The underlying `AVCaptureSession` — consumed by `AVCapturePreviewView`.
    /// Intended for custom preview-layer integrations; consumers using `SCCameraGuidanceView`
    /// do not need to access this directly.
    /// **Do not add or remove inputs/outputs.** Mutating the session bypasses
    /// `SCCameraSession`'s internal pipeline and may cause capture failures or crashes.
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
        let provider = SCOpenAIProvider(apiKey: apiKey)
        self.cloudProvider = provider
        self.cameraSession = SCCameraSession(
            category: category,
            cloudProvider: provider
        )
        self.cameraSession.delegate = self
    }

    // MARK: - Session control

    /// Starts the camera capture session. Call when the guidance view appears.
    public func start() { cameraSession.start() }

    /// Stops the camera capture session. Call when the guidance view disappears.
    public func stop()  { cameraSession.stop() }

    /// Captures the current shot.
    ///
    /// `isCapturing` is `true` only for the duration of the physical shutter operation
    /// (typically <1 s). Cloud analysis runs concurrently in the background; the resulting
    /// `SCPhoto` (with `cloudResult`, which may be `nil` on cloud failure) is appended to
    /// `photos` and the session advances to the next shot when the delegate fires.
    ///
    /// Silently no-ops if a capture is already in-flight.
    public func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        Task { @MainActor in
            _ = try? await cameraSession.capturePhoto()
            isCapturing = false
        }
    }

    /// Sets the camera zoom factor. Clamped to `1.0...maxZoomFactor` by `SCCameraSession`.
    public func setZoom(_ factor: CGFloat) {
        cameraSession.setZoom(factor)
        zoomFactor = max(1.0, min(cameraSession.maxZoomFactor, factor))
    }

    /// Switches the active lens. No-op when `isUltraWideAvailable` is `false`.
    /// Resets zoom to 1× — optical zoom ranges differ between lenses.
    public func switchLens(_ mode: SCLensMode) {
        guard mode == .main || isUltraWideAvailable else { return }
        cameraSession.switchLens(mode)
        lensMode   = mode
        zoomFactor = 1.0
    }

    /// Toggles between `.main` and `.ultraWide`. No-op on devices without ultra-wide.
    public func cycleLens() {
        switchLens(lensMode == .main ? .ultraWide : .main)
    }

    /// Cycles flash mode: off → auto → on → off.
    public func cycleFlash() {
        let all = SCFlashMode.allCases
        guard let idx = all.firstIndex(of: flashMode) else { return }
        let next = all[(idx + 1) % all.count]
        flashMode               = next
        cameraSession.flashMode = next
    }

    /// Moves camera focus and exposure to a device-space point.
    /// Convert a tap from view space using `AVCaptureVideoPreviewLayer.captureDevicePointConverted`.
    public func setFocusPoint(_ devicePoint: CGPoint) {
        cameraSession.setFocusPoint(devicePoint)
    }

    /// Analyses a photo from the user's library as though it were captured by the shutter.
    /// Results arrive via the same `onResult` closure path as a captured photo.
    public func analyzePhoto(imageData: Data) async {
        let prompt = currentShot.map { category.cloudPrompt(for: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Analyse this photo for overall quality, composition, and lighting."
        let photo       = SCPhoto(imageData: imageData, frameResult: nil)
        let cloudResult = try? await cloudProvider.analyze(photo: photo, prompt: prompt)
        let enriched    = SCPhoto(imageData: imageData, frameResult: nil, cloudResult: cloudResult)
        photos.append(enriched)
        advanceShot()
    }

    // MARK: - Private

    private let cloudProvider: any SCCloudProvider
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
