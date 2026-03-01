import SwiftUI
import ShotCoachCore

/// Main camera guidance view — camera preview + real-time feedback overlay + capture button.
///
/// Starts and stops the capture session automatically via `onAppear` / `onDisappear`.
/// Apply `.theme()` to customise appearance and `.onResult { }` to receive captured photos.
///
/// ```swift
/// SCCameraGuidanceView(sdk: sdk)
///     .theme(.minimal)
///     .onResult { photo in print(photo.cloudResult?.score ?? 0) }
/// ```
public struct SCCameraGuidanceView: View {

    @ObservedObject private var sdk: ShotCoach
    @Environment(\.scTheme) private var theme

    private var onResultHandler: ((SCPhoto) -> Void)?

    public init(sdk: ShotCoach) {
        self._sdk = ObservedObject(wrappedValue: sdk)
    }

    public var body: some View {
        ZStack {
            // Camera preview — fills the entire view.
            cameraPreview
                .ignoresSafeArea()

            // Feedback overlay — positioned per theme.
            VStack {
                if theme.feedbackPosition == .top {
                    feedbackArea
                        .padding()
                    Spacer()
                } else {
                    Spacer()
                    feedbackArea
                        .padding()
                }
            }

            // Ready ring — centered over the preview.
            ReadyIndicator(isReady: sdk.frameResult.isReadyToCapture)
        }
        .onAppear  { sdk.start() }
        .onDisappear { sdk.stop() }
        .onChange(of: sdk.photos.count) { count in
            guard count > 0 else { return }
            onResultHandler?(sdk.photos[count - 1])
        }
    }

    // MARK: - Modifier

    /// Registers a closure that is called each time a photo is captured and
    /// the cloud analysis result arrives.
    public func onResult(_ handler: @escaping (SCPhoto) -> Void) -> Self {
        var copy = self
        copy.onResultHandler = handler
        return copy
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cameraPreview: some View {
#if canImport(UIKit)
        AVCapturePreviewView(session: sdk.captureSession)
#else
        Color.black
#endif
    }

    private var feedbackArea: some View {
        VStack(spacing: 16) {
            FeedbackStack(result: sdk.frameResult)
            captureButton
        }
    }

    private var captureButton: some View {
        Button {
            sdk.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(sdk.frameResult.isReadyToCapture ? theme.accent : Color.white.opacity(0.5))
                    .frame(width: 64, height: 64)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 74, height: 74)
            }
        }
        .disabled(sdk.isCapturing)
        .opacity(sdk.isCapturing ? 0.5 : 1)
    }
}
