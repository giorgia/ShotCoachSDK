import Foundation
import AVFoundation
import CoreVideo

/// Manages the AVCaptureSession lifecycle, feeds frames to SCFrameAnalyzer,
/// and triggers cloud analysis after each photo capture.
///
/// Usage:
/// ```swift
/// let session = SCCameraSession(category: .homeListing, cloudProvider: provider)
/// session.delegate = self
/// session.start()
/// let photo = try await session.capturePhoto()
/// ```
///
/// Threading note: `delegate` and `photoHandler` are accessed from both the caller's
/// concurrency context and `captureQueue`. Under Swift 5.9 minimal concurrency checking
/// this does not generate errors, but callers should treat `SCCameraSession` as
/// single-owner (i.e., not shared across actors) to avoid races. A full actor-based
/// refactor is tracked for a future release.
public final class SCCameraSession: NSObject {

    // MARK: - Public

    /// Receives frame-analysis updates and post-capture cloud results.
    /// Held weakly via the AnyObject box pattern (direct `weak var: any Protocol` is unsound).
    public var delegate: (any SCAnalysisDelegate)? {
        get { _delegateObject as? any SCAnalysisDelegate }
        set { _delegateObject = newValue }
    }

    public init(category: any SCCategoryConfig, cloudProvider: any SCCloudProvider) {
        self.analyzer      = SCFrameAnalyzer(category: category)
        self.cloudProvider = cloudProvider
        self.category      = category
        super.init()
        configureSession()
        // NOTE: we intentionally do NOT set a delegate on `analyzer` here.
        // `SCFrameAnalyzer.notifyDelegate` is a no-op when no analyzer delegate is set;
        // `SCCameraSession` owns all delegate dispatch so there is no double notification.
    }

    /// Starts the capture session on a background queue.
    public func start() {
        captureQueue.async { [session] in session.startRunning() }
    }

    /// Stops the capture session.
    public func stop() {
        captureQueue.async { [session] in session.stopRunning() }
    }

    /// Captures a still photo and returns an `SCPhoto` with the raw image data
    /// and the most-recent on-device frame result.
    /// Cloud analysis is dispatched concurrently; results arrive via
    /// `SCAnalysisDelegate.analyzer(_:didComplete:cloudResult:)`.
    /// - Note: Concurrent calls are not supported. A second call while a capture
    ///   is in-flight will abandon the previous continuation.
    public func capturePhoto() async throws -> SCPhoto {
        let frameResult = await analyzer.lastFrameResult()
        let imageData   = try await captureRawPhotoData()
        let photo       = SCPhoto(imageData: imageData, frameResult: frameResult)

        // Fallback prompt when no required shots are defined for the category.
        let snapPrompt   = category.requiredShots.first
            .map { category.cloudPrompt(for: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Analyse this photo for overall quality, composition, and lighting."

        let snapProvider = cloudProvider
        let snapAnalyzer = analyzer
        let snapDelegate = delegate

        Task {
            let cloudResult = try? await snapProvider.analyze(photo: photo, prompt: snapPrompt)
            let enriched    = SCPhoto(imageData: imageData, frameResult: frameResult, cloudResult: cloudResult)
            await MainActor.run {
                snapDelegate?.analyzer(snapAnalyzer, didComplete: enriched, cloudResult: cloudResult)
            }
        }

        return photo
    }

    // MARK: - Private — session setup

    private let session      = AVCaptureSession()
    private let videoOutput  = AVCaptureVideoDataOutput()
    private let photoOutput  = AVCapturePhotoOutput()
    private let captureQueue = DispatchQueue(label: "com.shotcoach.capture", qos: .userInitiated)

    private let analyzer:      SCFrameAnalyzer
    private let cloudProvider: any SCCloudProvider
    private let category:      any SCCategoryConfig

    // AnyObject box for weak delegate (direct `weak var: any Protocol` is unsound).
    private weak var _delegateObject: AnyObject?

    // Retained for the duration of each AVCapturePhoto callback.
    private var photoHandler: PhotoCaptureHandler?

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Camera input — prefer the back wide-angle camera on iOS; fall back to
        // the system default on macOS (which has no back/front distinction).
        let device: AVCaptureDevice?
#if os(iOS)
        device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
#else
        device = AVCaptureDevice.default(for: .video)
#endif

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        // Video output — feeds pixel buffers to SCFrameAnalyzer.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Photo output — used by capturePhoto().
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
    }

    // MARK: - Private — photo capture bridge

    private func captureRawPhotoData() async throws -> Data {
        defer { photoHandler = nil }   // Release handler after continuation resolves.
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: SCCloudError.invalidResponse)
                return
            }
            let handler = PhotoCaptureHandler(continuation: continuation)
            self.photoHandler = handler   // Retain for duration of AVFoundation callback.
            self.photoOutput.capturePhoto(
                with: AVCapturePhotoSettings(),
                delegate: handler
            )
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension SCCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts    = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let frame = SCFrame(timestamp: ts, pixelBuffer: pixelBuffer)

        // Capture locals before crossing into the Task — avoids capturing `self`.
        let snapAnalyzer = analyzer
        let snapDelegate = delegate

        Task {
            let result = await snapAnalyzer.analyze(frame)
            await MainActor.run {
                snapDelegate?.analyzer(snapAnalyzer, didUpdate: result)
            }
        }
    }
}

// MARK: - PhotoCaptureHandler (private helper)

private final class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate {

    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer { continuation = nil }

        if let error {
            // Map camera-hardware errors to networkFailure; a dedicated SCCaptureError
            // type is planned for a future release.
            continuation?.resume(throwing: SCCloudError.networkFailure(error.localizedDescription))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: SCCloudError.invalidResponse)
            return
        }
        continuation?.resume(returning: data)
    }
}
