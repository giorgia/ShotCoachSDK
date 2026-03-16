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

    /// Apparent zoom spanning both lenses.
    /// - `0.5` = ultra-wide at its native 1× (half the field of view of the main lens).
    /// - `1.0` = main lens at 1×.
    /// - `>1.0` = main lens with digital/optical zoom.
    public var virtualZoomFactor: CGFloat {
        lensMode == .ultraWide ? 0.5 : zoomFactor
    }

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

    /// Sets zoom across both lenses using a unified virtual scale:
    /// - Any value `< 1.0` → ultra-wide lens at its native 1× (all map to the same FOV)
    /// - `1.0` → main lens at 1×
    /// - `> 1.0` → main lens with optical/digital zoom
    ///
    /// Automatically switches lenses when crossing the 1× boundary.
    /// No-op when ultra-wide is unavailable and factor < 1.
    public func setVirtualZoom(_ factor: CGFloat) {
        if factor < 1.0 {
            guard isUltraWideAvailable else { return }
            if lensMode != .ultraWide { switchLens(.ultraWide) }
            // Ultra-wide always stays at 1× hardware zoom; the 0.5× label is its native FOV.
        } else {
            if lensMode != .main { switchLens(.main) }
            // Always call setZoom even while isSwitchingLens — captureQueue is serial, so
            // the setZoom block runs after the switchLens block and targets the correct device.
            // Updating zoomFactor synchronously here avoids a visible stall in the zoom label.
            setZoom(factor)
        }
    }

    /// Switches the active lens. No-op when `isUltraWideAvailable` is `false` or a
    /// switch is already in flight (prevents rapid-pinch from stacking capture-queue blocks).
    /// Resets zoom to 1× — optical zoom ranges differ between lenses.
    /// Published state is updated optimistically; rolls back if the hardware switch fails.
    public func switchLens(_ mode: SCLensMode) {
        guard mode == .main || isUltraWideAvailable else { return }
        guard !isSwitchingLens else { return }
        let previousMode = lensMode
        let previousZoom = zoomFactor
        isSwitchingLens = true
        lensMode   = mode
        zoomFactor = 1.0
        cameraSession.switchLens(mode) { [weak self] success in
            // Delivered on DispatchQueue.main (see SCCameraSession.switchLens).
            // Explicit Task @MainActor ensures forward-compatibility with Swift 6 strict concurrency.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSwitchingLens = false
                if !success {
                    self.lensMode   = previousMode
                    self.zoomFactor = previousZoom
                }
            }
        }
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

    /// Skips the current required shot and advances to the next one.
    /// Use this to let users bypass a shot they can't capture (e.g. no backyard).
    public func skipCurrentShot() { advanceShot() }

    // MARK: - Private

    private let cloudProvider: any SCCloudProvider
    private let cameraSession: SCCameraSession
    /// True while a hardware lens swap is in flight on captureQueue.
    /// Prevents stacking multiple `beginConfiguration` blocks from rapid pinch events.
    private var isSwitchingLens = false

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
