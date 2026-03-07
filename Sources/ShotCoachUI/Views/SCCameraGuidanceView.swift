import SwiftUI
import ShotCoachCore
import PhotosUI

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
    private var showFeedbackPills: Bool  = true
    private var showFlashButton:   Bool  = true
    private var showZoomControls:  Bool  = true
    private var showLibraryButton: Bool  = true

    // MARK: - State

    @State private var focusPoint:         CGPoint? = nil
    /// Zoom factor captured at the start of each pinch gesture.
    /// `MagnificationGesture.onChanged` supplies a cumulative scale from gesture start,
    /// so we must multiply this baseline — not the continuously-updating `sdk.virtualZoomFactor` —
    /// by `delta` to avoid exponential runaway.
    @State private var zoomAtGestureStart: CGFloat = 1.0
    @State private var focusDismissTask:   Task<Void, Never>? = nil
    @State private var pickerItem: PhotosPickerItem? = nil

    public init(sdk: ShotCoach) {
        self._sdk = ObservedObject(wrappedValue: sdk)
    }

    public var body: some View {
        ZStack {
            // Camera preview fills the entire view.
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
        .onAppear {
            sdk.start()
            // Seed gesture baseline from the SDK's current lens so the first pinch
            // doesn't jump when a lens was preset before the view appeared.
            zoomAtGestureStart = sdk.virtualZoomFactor
        }
        .onDisappear {
            sdk.stop()
            focusDismissTask?.cancel()
        }
        .onChange(of: sdk.photos.count) { newCount in
            guard newCount > 0 else { return }
            onResultHandler?(sdk.photos[newCount - 1])
        }
    }

    // MARK: - Modifiers

    /// Registers a closure called each time cloud analysis completes for a captured photo.
    public func onResult(_ handler: @escaping (SCPhoto) -> Void) -> Self {
        var copy = self; copy.onResultHandler = handler; return copy
    }

    /// Hides the built-in `FeedbackStack` text pills above the capture button.
    public func hideFeedbackPills() -> Self {
        var copy = self; copy.showFeedbackPills = false; return copy
    }

    /// Hides the flash toggle button in the capture row.
    public func hideFlashButton() -> Self {
        var copy = self; copy.showFlashButton = false; return copy
    }

    /// Hides the zoom pill row and pinch-to-zoom gesture.
    public func hideZoomControls() -> Self {
        var copy = self; copy.showZoomControls = false; return copy
    }

    /// Hides the photo-library picker button in the capture row.
    public func hideLibraryButton() -> Self {
        var copy = self; copy.showLibraryButton = false; return copy
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cameraPreview: some View {
#if canImport(UIKit)
        GeometryReader { geo in
            // Height of each letterbox bar so the clear window is a 4:3 rectangle.
            // On devices where the screen is already ≤ 4:3 this is 0 (no bars needed).
            let barH = max(0, (geo.size.height - geo.size.width * 4.0 / 3.0) / 2)

            AVCapturePreviewView(
                session: sdk.captureSession,
                onTap: { layerPoint, devicePoint in
                    // layerPoint is already in view/screen coordinates — use it directly
                    // for FocusSquare so it appears exactly where the user tapped.
                    // devicePoint drives AVFoundation focus (separate concern).
                    withAnimation(.easeOut(duration: 0.15)) { focusPoint = layerPoint }
                    sdk.setFocusPoint(devicePoint)
                    focusDismissTask?.cancel()
                    focusDismissTask = Task {
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.25)) { focusPoint = nil }
                    }
                }
            )
            .ignoresSafeArea()
            // Letterbox: semi-transparent dark bars that show the 4:3 capture window.
            // The preview layer uses resizeAspectFill so the scene is still visible (dimmed)
            // in the bar areas, matching the native iOS camera appearance.
            .overlay(alignment: .top) {
                if barH > 0 {
                    Color.black.opacity(0.5)
                        .frame(maxWidth: .infinity)
                        .frame(height: barH)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .overlay(alignment: .bottom) {
                if barH > 0 {
                    Color.black.opacity(0.5)
                        .frame(maxWidth: .infinity)
                        .frame(height: barH)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .overlay { FocusSquare(focusPoint: focusPoint, size: geo.size) }
            .gesture(
                MagnificationGesture()
                    .onChanged { delta in
                        sdk.setVirtualZoom(zoomAtGestureStart * delta)
                    }
                    .onEnded { _ in
                        zoomAtGestureStart = sdk.virtualZoomFactor
                    }
            )
            .onChange(of: sdk.lensMode) { _ in
                // Zoom ranges differ between lenses. Reset the gesture baseline so
                // the first pinch after a switch doesn't jump to a stale factor.
                zoomAtGestureStart = sdk.virtualZoomFactor
            }
        }
#endif
    }

    /// Zoom pill row — mirrors the native iOS Camera control.
    /// Shows 0.5× only when an ultra-wide lens is available.
    /// The active level is highlighted white; others are semi-transparent.
    @ViewBuilder
    private var zoomPills: some View {
        if showZoomControls {
            let v = sdk.virtualZoomFactor
            HStack(spacing: 4) {
                if sdk.isUltraWideAvailable {
                    ZoomPill(label: "0.5×", active: v < 1.0) { sdk.setVirtualZoom(0.5) }
                }
                ZoomPill(label: "1×",   active: v >= 1.0 && v < 1.5) { sdk.setVirtualZoom(1.0) }
                ZoomPill(label: "2×",   active: v >= 1.5) { sdk.setVirtualZoom(2.0) }
            }
        }
    }

    /// Flash cycle button — sits at the right end of the capture row, balancing `libraryButton`.
    @ViewBuilder
    private var flashButton: some View {
        if showFlashButton {
            Button { sdk.cycleFlash() } label: {
                Image(systemName: sdk.flashMode.symbolName)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .foregroundStyle(.white)
            }
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var feedbackArea: some View {
        VStack(spacing: 16) {
            if showFeedbackPills {
                FeedbackStack(result: sdk.frameResult)
            }
            zoomPills
            captureRow
        }
    }

    private var captureRow: some View {
        HStack {
            libraryButton
            Spacer()
            captureButton
            Spacer()
            flashButton
        }
    }

    private var captureButton: some View {
        Button {
            sdk.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(sdk.frameResult.isReadyToCapture ? theme.accent : Color.white.opacity(0.5))
                    .frame(width: 52, height: 52)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 60, height: 60)
            }
        }
        .disabled(sdk.isCapturing)
        .opacity(sdk.isCapturing ? 0.5 : 1)
    }

    @ViewBuilder
    private var libraryButton: some View {
        if showLibraryButton {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .onChange(of: pickerItem) { item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        await sdk.analyzePhoto(imageData: data)
                    }
                    pickerItem = nil
                }
            }
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

// MARK: - ZoomPill

/// A single zoom-level capsule button styled like the native iOS Camera pill row.
private struct ZoomPill: View {
    let label:  String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(active ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Color.white : Color.black.opacity(0.45))
                .clipShape(Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: active)
    }
}
