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
    /// When `true` (default) the built-in `FeedbackStack` text pills are rendered.
    /// Set to `false` via `.hideFeedbackPills()` when you supply your own feedback UI
    /// (e.g. `SCRuleIconBar`) in an external overlay.
    private var showFeedbackPills: Bool = true

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
        // onChange(of:perform:) — available macOS 13+ / iOS 16+; closure receives the new value.
        .onChange(of: sdk.photos.count) { newCount in
            guard newCount > 0 else { return }
            onResultHandler?(sdk.photos[newCount - 1])
        }
    }

    // MARK: - Modifiers

    /// Registers a closure called each time cloud analysis completes for a captured photo.
    /// `photo.cloudResult` may be `nil` if the cloud provider failed or was not configured.
    public func onResult(_ handler: @escaping (SCPhoto) -> Void) -> Self {
        var copy = self
        copy.onResultHandler = handler
        return copy
    }

    /// Hides the built-in `FeedbackStack` text pills above the capture button.
    /// Use when you are rendering your own feedback UI (e.g. `SCRuleIconBar`) in an
    /// external overlay — the capture button and `ReadyIndicator` are unaffected.
    public func hideFeedbackPills() -> Self {
        var copy = self
        copy.showFeedbackPills = false
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
            if showFeedbackPills {
                FeedbackStack(result: sdk.frameResult)
            }
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
