import SwiftUI
import ShotCoachCore
import ShotCoachUI

/// Full-screen camera session for one built-in category.
///
/// This file is the integration reference — notice how little code is required.
/// Three steps, then ShotCoach handles everything: camera lifecycle, live on-device
/// rules, real-time feedback overlays, capture, and cloud analysis.
///
/// ```
/// Step 1 — ShotCoach(category: .homeListing, apiKey: key)
/// Step 2 — SCCameraGuidanceView(sdk: sdk)
///               .onResult { photo in … }   // ← must come before .theme()
///               .theme(theme)
/// ```
struct CameraSessionView: View {

    let category: SCBuiltInCategory
    let theme: SCTheme

    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    // ─────────────────────────────────────────────────────────────────────────
    // STEP 1 — Create a ShotCoach instance.
    //
    // Pass any SCCategoryConfig (built-in enum, .extending { } override, or a
    // fully custom struct) plus your API key. ShotCoach wires up:
    //   • SCCameraSession  — AVCapture lifecycle
    //   • SCFrameAnalyzer  — concurrent on-device rules, throttled to 1.5 s
    //   • SCOpenAIProvider — GPT-4o cloud analysis after capture
    // No further setup required.
    // ─────────────────────────────────────────────────────────────────────────
    @StateObject private var sdk: ShotCoach

    init(category: SCBuiltInCategory, theme: SCTheme) {
        self.category = category
        self.theme = theme

        // Read the key from Keychain — never hardcode or log API keys.
        let apiKey = SCKeychainService.load(key: "openai_api_key") ?? ""

        // This is all you need — one line to get a fully-configured SDK:
        _sdk = StateObject(wrappedValue: ShotCoach(category: category, apiKey: apiKey))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            // ─────────────────────────────────────────────────────────────────
            // STEP 2 — Present SCCameraGuidanceView.
            //
            // Drop it in like any SwiftUI view. It self-manages AVCaptureSession
            // (starts on appear, stops on disappear) and renders:
            //   • FeedbackStack     — top 3 rule failures, sorted by severity
            //   • ReadyIndicator    — pulsing ring when isReadyToCapture == true
            //   • Capture button    — accent-tinted, disabled while capturing
            //   • ShotChecklist     — tracks progress through required shots
            // All of it responds to the theme you supply below.
            // ─────────────────────────────────────────────────────────────────
            SCCameraGuidanceView(sdk: sdk)

                // ─────────────────────────────────────────────────────────────
                // STEP 3 — Handle results.
                //
                // onResult fires immediately after capture with the new SCPhoto.
                // photo.cloudResult is nil at first; GPT-4o populates it a few
                // seconds later. Observe sdk.photos for live updates, or present
                // SCResultsView which handles the async loading for you.
                //
                // Note: call .onResult before .theme() — .theme() is a generic
                // View modifier that erases the concrete type, so modifiers
                // returning Self must come first.
                // ─────────────────────────────────────────────────────────────
                .onResult { photo in
                    store.add(photo, categoryName: category.displayName)
                }

                // Apply the per-category accent colour and overlay style.
                .theme(theme)

                .ignoresSafeArea()

            // Dismiss button — top-leading so it never overlaps the overlays.
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .foregroundStyle(.white)
            }
            .padding(16)
        }
    }
}
