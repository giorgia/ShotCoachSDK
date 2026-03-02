import SwiftUI
import ShotCoachCore
import ShotCoachUI

/// Per-shot camera overlay embedded in `ShotListView`'s ZStack.
///
/// Creates a `SingleShotCategory` that narrows the SDK to one specific shot so the
/// classifier hints and on-device rules focus on the target. Cloud analysis is deferred
/// — the provider is initialised with an empty key; batch analysis runs in `ShotListView`.
///
/// Capture sequence:
/// 1. Live camera is shown.
/// 2. User taps the capture button → `SCCameraGuidanceView` fires `.onResult`.
/// 3. `capturedImage` is set → fullscreen freeze-frame appears (hero `isSource: true`).
/// 4. After 150 ms → `onCapture(photo)` is called.
/// 5. Parent runs `withAnimation { entries[idx].capturedPhoto = photo; activeShotID = nil }`.
/// 6. Overlay fades out; cell hero-flies from fullscreen to grid position.
struct ShotCameraView: View {

    let info: CategoryInfo
    let shot: SCShotType
    let heroNamespace: Namespace.ID
    let onCapture: (SCPhoto) -> Void
    let onDismiss: () -> Void

    @StateObject private var sdk: ShotCoach
    @State private var capturedImage: SCPhoto?

    init(
        info: CategoryInfo,
        shot: SCShotType,
        heroNamespace: Namespace.ID,
        onCapture: @escaping (SCPhoto) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.info         = info
        self.shot         = shot
        self.heroNamespace = heroNamespace
        self.onCapture    = onCapture
        self.onDismiss    = onDismiss
        _sdk = StateObject(wrappedValue: ShotCoach(
            category: SingleShotCategory(base: info.category, targetShot: shot),
            apiKey: ""   // cloud deferred to batch in ShotListView
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let captured = capturedImage {
                // Freeze-frame — hero source for fly-back animation.
                freezeFrame(photo: captured)
            } else {
                // Live camera + chrome.
                SCCameraGuidanceView(sdk: sdk)
                    .hideFeedbackPills()
                    .onResult { photo in
                        capturedImage = photo
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            onCapture(photo)
                        }
                    }
                    .theme(info.theme)
                    .ignoresSafeArea()

                cameraChrome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func freezeFrame(photo: SCPhoto) -> some View {
#if canImport(UIKit)
        if let ui = UIImage(data: photo.imageData) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .matchedGeometryEffect(
                    id: "photo_\(shot.id)",
                    in: heroNamespace,
                    isSource: true
                )
        }
#else
        if let ns = NSImage(data: photo.imageData) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .matchedGeometryEffect(
                    id: "photo_\(shot.id)",
                    in: heroNamespace,
                    isSource: true
                )
        }
#endif
    }

    private var cameraChrome: some View {
        VStack {
            HStack(alignment: .top) {
                // Dismiss — top-left
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .foregroundStyle(.white)
                }

                Spacer()

                // Shot name — top-right
                Text(shot.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .padding(16)

            Spacer()

            // Rule icon bar — above the capture button rendered by SCCameraGuidanceView.
            // 110 pt inset clears the 74 pt button ring + 16 pt padding + safe area.
            SCRuleIconBar(result: sdk.frameResult, currentShot: sdk.currentShot)
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
        }
    }
}

// MARK: - SingleShotCategory

/// Narrows a built-in category to a single target shot.
///
/// Passing this to `ShotCoach(category:apiKey:)` limits the classifier hints to that
/// one shot and restricts `requiredShots` to `[targetShot]` so the SDK's shot-advance
/// logic fires after the first capture.
private struct SingleShotCategory: SCCategoryConfig {
    let base: SCBuiltInCategory
    let targetShot: SCShotType

    var categoryID: String               { base.categoryID }
    var displayName: String              { base.displayName }
    var requiredShots: [SCShotType]      { [targetShot] }
    var onDeviceRules: [any SCFrameRule] { base.onDeviceRules }

    func cloudPrompt(for shot: SCShotType) -> String {
        base.cloudPrompt(for: shot)
    }
}
