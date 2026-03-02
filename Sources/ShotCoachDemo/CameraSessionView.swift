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
///               .hideFeedbackPills()          // replaced by SCRuleIconBar below
///               .onResult { photo in … }      // ← must come before .theme()
///               .theme(theme)
/// ```
struct CameraSessionView: View {

    let category: SCBuiltInCategory
    let theme: SCTheme

    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    // ─────────────────────────────────────────────────────────────────────────
    // STEP 1 — Create a ShotCoach instance.
    // ─────────────────────────────────────────────────────────────────────────
    @StateObject private var sdk: ShotCoach

    /// Wraps SCPhoto so it can drive `.sheet(item:)` — SCPhoto is a value type
    /// without a stable identity, so we assign one at capture time.
    private struct ResultItem: Identifiable {
        let id = UUID()
        let photo: SCPhoto
    }

    @State private var resultItem: ResultItem?
    @State private var showChecklist = false

    init(category: SCBuiltInCategory, theme: SCTheme) {
        self.category = category
        self.theme    = theme
        let apiKey    = SCKeychainService.load(key: "openai_api_key") ?? ""
        _sdk = StateObject(wrappedValue: ShotCoach(category: category, apiKey: apiKey))
    }

    var body: some View {
        ZStack {

            // ─────────────────────────────────────────────────────────────────
            // STEP 2 — Camera preview + capture button.
            //
            // .hideFeedbackPills() suppresses the built-in text-pill overlay;
            // the SCRuleIconBar below replaces it with colour-coded icons.
            // ─────────────────────────────────────────────────────────────────
            SCCameraGuidanceView(sdk: sdk)
                .hideFeedbackPills()
                .onResult { photo in
                    store.add(photo, categoryName: category.displayName)
                    resultItem = ResultItem(photo: photo)
                }
                .theme(theme)
                .ignoresSafeArea()

            // ── Top chrome ───────────────────────────────────────────────────
            VStack {
                HStack(alignment: .top) {

                    // Dismiss button (leading).
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Shot progress + checklist button (trailing).
                    VStack(alignment: .trailing, spacing: 6) {

                        // Checklist — opens SCShotChecklistView.
                        Button { showChecklist = true } label: {
                            Image(systemName: "list.bullet")
                                .font(.body.weight(.semibold))
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }

                        // Current shot name + "Shot X of Y".
                        if let shot = sdk.currentShot {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(shot.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Shot \(sdk.photos.count + 1) of \(sdk.category.requiredShots.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(16)

                Spacer()

                // ── Rule icon bar ─────────────────────────────────────────────
                // Sits directly above the capture button (which SCCameraGuidanceView
                // renders at the bottom of its own layout). The 110 pt bottom inset
                // clears the button (74 pt outer ring + 16 pt padding + safe area).
                //
                // Each icon is colour-coded green / orange / red per rule result.
                // The rightmost icon shows the classifier's detected scene label.
                SCRuleIconBar(result: sdk.frameResult, currentShot: sdk.currentShot)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
            }
        }
        // ── Sheets ───────────────────────────────────────────────────────────
        .sheet(item: $resultItem) { item in
            SCResultsView(photo: item.photo)
        }
        .sheet(isPresented: $showChecklist) {
            SCShotChecklistView(sdk: sdk)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
