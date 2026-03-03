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
                    .hideZoomControls()
                    .onResult { photo in
                        capturedImage = photo
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            // Guard against the user dismissing during the freeze-frame
                            // window — if capturedImage was cleared, don't propagate.
                            guard capturedImage != nil else { return }
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
        let base: AnyView = UIImage(data: photo.imageData).map {
            AnyView(Image(uiImage: $0).resizable().scaledToFill())
        } ?? AnyView(Color.black)
        base
            .ignoresSafeArea()
            .matchedGeometryEffect(
                id: "photo_\(shot.id)",
                in: heroNamespace,
                isSource: true
            )
    }

    private var cameraChrome: some View {
        ZStack {
            // Icon bar — GeometryReader with .ignoresSafeArea() gives geo.size = full
            // screen so barH matches the letterbox bars drawn in SCCameraGuidanceView.
            // barH = height of each dark letterbox strip.
            // Icon bar height ≈ 55 pt (6 pt v-pad × 2 + 20 pt icon + 4 spacing + 9 pt label + 4 cell-pad).
            // bottomPad = barH - 70 places the bar's top edge at the 4:3 photo boundary,
            // with its bottom just above the 60 pt capture row.
            GeometryReader { geo in
                let barH      = max(0.0, (geo.size.height - geo.size.width * 4.0 / 3.0) / 2)
                let bottomPad = max(8.0, barH - 70)
                VStack {
                    Spacer()
                    SCRuleIconBar(result: sdk.frameResult, currentShot: sdk.currentShot)
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomPad)
                }
            }
            .ignoresSafeArea()

            // Top chrome — no .ignoresSafeArea() so SwiftUI positions this VStack
            // inside the safe area, naturally clearing the Dynamic Island.
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
                .padding(.top, 8)
                .padding([.horizontal, .bottom], 16)
                Spacer()
            }
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
