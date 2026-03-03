import SwiftUI
import ShotCoachCore
import ShotCoachUI

// MARK: - CategoryInfo

/// Visual identity for one built-in category: icon, description, and camera theme.
///
/// Used by `CategoryPickerView` (cards) and `ShotCameraView` (theme injection).
struct CategoryInfo: Identifiable, Hashable {
    var id: String { category.categoryID }
    let category: SCBuiltInCategory
    let icon: String        // SF Symbols name
    let blurb: String       // One-line description on the card
    let theme: SCTheme      // Applied to SCCameraGuidanceView

    // Equality and hashing are keyed on the stable category ID.
    static func == (lhs: CategoryInfo, rhs: CategoryInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // The four built-in categories, each with a distinct accent colour.
    static let all: [CategoryInfo] = [

        // Home Listing — dark background, lime accent
        CategoryInfo(
            category: .homeListing,
            icon: "house.fill",
            blurb: "Showcase every room to maximise listing appeal.",
            theme: SCTheme(
                accent: Color(red: 0.494, green: 0.847, blue: 0.251),
                overlayStyle: .frostedGlass
            )
        ),

        // Car Listing — dark background, sky-blue accent
        CategoryInfo(
            category: .carListing,
            icon: "car.fill",
            blurb: "8 required angles for a complete vehicle listing.",
            theme: SCTheme(
                accent: Color(red: 0.220, green: 0.706, blue: 0.878),
                overlayStyle: .frostedGlass
            )
        ),

        // Product Photo — light / minimal
        CategoryInfo(
            category: .productPhoto,
            icon: "cube.box.fill",
            blurb: "Studio-quality shots for marketplace listings.",
            theme: SCTheme(
                accent: Color(red: 0.10, green: 0.10, blue: 0.10),
                overlayStyle: .minimal
            )
        ),

        // Food Photo — dark background, amber accent
        CategoryInfo(
            category: .foodPhoto,
            icon: "fork.knife",
            blurb: "Mouth-watering shots that drive orders.",
            theme: SCTheme(
                accent: Color(red: 0.831, green: 0.659, blue: 0.196),
                overlayStyle: .frostedGlass
            )
        ),
    ]
}

// MARK: - CategoryPickerView

/// 2 × 2 grid of category cards. Tap any card to open the shot-grid session for that category.
struct CategoryPickerView: View {

    @State private var activeCategory: CategoryInfo?
    @State private var showKeySetup = false
    @State private var hasAPIKey = false   // resolved in onAppear to avoid sync Keychain read at init

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack { gridContent }
    }

    // MARK: - Grid content

    @ViewBuilder
    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(CategoryInfo.all) { info in
                    CategoryCard(info: info)
                        .onTapGesture { activeCategory = info }
                }
            }
            .padding(20)
        }
        .navigationTitle("ShotCoach")
        .background(Color(white: 0.05).ignoresSafeArea())
        .onAppear {
            // Refresh key state so the toolbar icon stays in sync after updates.
            hasAPIKey = SCKeychainService.load(key: "openai_api_key") != nil
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showKeySetup = true } label: {
                    Image(systemName: hasAPIKey ? "key.fill" : "key")
                        .foregroundStyle(hasAPIKey ? Color.green : Color.secondary)
                }
                .help(hasAPIKey ? "API key configured — tap to update" : "Add OpenAI API key")
            }
        }
        .sheet(isPresented: $showKeySetup, onDismiss: {
            hasAPIKey = SCKeychainService.load(key: "openai_api_key") != nil
        }) {
            APIKeySetupView { showKeySetup = false }
        }
        .navigationDestination(item: $activeCategory) { info in
            ShotListView(info: info)
        }
    }
}

// MARK: - CategoryCard

private struct CategoryCard: View {
    let info: CategoryInfo

    /// Resolved accent — falls back to white for the "minimal" product theme
    /// so text stays legible on a light background.
    private var displayAccent: Color {
        info.theme.overlayStyle == .minimal ? .white : info.theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Top row: icon + shot-count badge ────────────────────────────────
            HStack(alignment: .top) {
                Image(systemName: info.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(displayAccent)

                Spacer()

                Text("\(info.category.requiredShots.count) shots")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(displayAccent.opacity(0.15))
                    .foregroundStyle(displayAccent)
                    .clipShape(Capsule())
            }

            Spacer()

            // ── Bottom: category name + description ──────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(info.category.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(info.blurb)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(minHeight: 148)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(displayAccent.opacity(0.30), lineWidth: 1)
        )
    }
}
