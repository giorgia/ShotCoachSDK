import SwiftUI
import ShotCoachCore
import ShotCoachUI

// MARK: - ShotEntry

/// One slot in the shot grid: the required shot type and, once captured, its photo.
struct ShotEntry: Identifiable {
    let id: String          // == shot.id
    let shot: SCShotType
    var capturedPhoto: SCPhoto?
    /// Pre-decoded image, populated off the main thread before the hero animation starts
    /// so `ShotCell` has a ready-to-render image on the first animation frame.
    var cachedImage: UIImage?
}

// MARK: - ShotListView

/// Shot-grid-first session screen.
///
/// Displays all required shots as placeholder cells. Tapping a cell opens
/// `ShotCameraView` in the same ZStack. After capture the photo hero-flies back
/// into its cell. When every slot is filled, "Send to AI" runs batch cloud analysis
/// and navigates to `SessionResultsView`.
struct ShotListView: View {

    let info: CategoryInfo

    @State private var entries: [ShotEntry]
    @State private var activeShotID: String?
    @State private var aestheticModel: HomeListingAestheticModel?
    @State private var cloudResults: [String: SCCloudResult] = [:]
    @State private var isAnalyzing = false
    @State private var navigateToResults = false
    @State private var partialError: String?
    @State private var showKeySetup = false
    @State private var analysisError: String?

    @Namespace private var heroNamespace

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    init(info: CategoryInfo) {
        self.info = info
        _entries = State(initialValue: info.category.requiredShots.map {
            ShotEntry(id: $0.id, shot: $0)
        })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1 — shot grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(entries) { entry in
                        Button { activeShotID = entry.id } label: {
                            ShotCell(
                                entry: entry,
                                isActive: activeShotID == entry.id,
                                namespace: heroNamespace,
                                aestheticModel: aestheticModel
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }

            // Layer 2 — per-shot camera overlay
            if let shotID = activeShotID,
               let entryIdx = entries.firstIndex(where: { $0.id == shotID }) {
                ShotCameraView(
                    info: info,
                    shot: entries[entryIdx].shot,
                    heroNamespace: heroNamespace,
                    aestheticModel: aestheticModel,
                    onCapture: { photo in
                        // Decode the JPEG off the main thread so the image is ready on
                        // the first animation frame — avoids the gray-box flash.
                        Task { @MainActor in
                            let img = await Task.detached(priority: .userInitiated) {
                                UIImage(data: photo.imageData)
                            }.value
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                                entries[entryIdx].capturedPhoto = photo
                                entries[entryIdx].cachedImage   = img
                                activeShotID = nil
                            }
                        }
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            activeShotID = nil
                        }
                    }
                )
                .id(shotID)             // force fresh sdk + session for each new shot
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task {
            aestheticModel = try? HomeListingAestheticModel()
        }
        .navigationTitle(info.category.displayName)
        .toolbar(activeShotID != nil ? .hidden : .visible, for: .navigationBar)
        .background(Color(white: 0.05).ignoresSafeArea())
        .toolbar {
            if entries.contains(where: { $0.capturedPhoto != nil }) {
                ToolbarItem(placement: .primaryAction) {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Button("Send to AI") {
                            let hasKey = SCKeychainService.load(key: "openai_api_key") != nil
                                      || SCKeychainService.load(key: "anthropic_api_key") != nil
                            if !hasKey {
                                showKeySetup = true
                            } else {
                                isAnalyzing = true
                                Task { await runBatchAnalysis() }
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $navigateToResults) {
            SessionResultsView(entries: entries, cloudResults: cloudResults, info: info,
                               partialError: partialError)
        }
        .sheet(isPresented: $showKeySetup) {
            APIKeySetupView { showKeySetup = false }
        }
        .alert("Analysis Failed", isPresented: Binding(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button("OK") { analysisError = nil }
        } message: {
            Text(analysisError ?? "")
        }
    }

    // MARK: - Batch analysis

    @AppStorage("preferred_provider") private var preferredProvider: String = "anthropic"

    @MainActor
    private func runBatchAnalysis() async {
        // Pick provider based on preference, falling back to whichever key is available.
        let provider: any SCCloudProvider
        let anthropicKey = SCKeychainService.load(key: "anthropic_api_key") ?? ""
        let openAIKey    = SCKeychainService.load(key: "openai_api_key")    ?? ""

        if preferredProvider == "anthropic" && !anthropicKey.isEmpty {
            provider = SCAnthropicProvider(apiKey: anthropicKey)
        } else if !openAIKey.isEmpty {
            provider = SCOpenAIProvider(apiKey: openAIKey)
        } else if !anthropicKey.isEmpty {
            provider = SCAnthropicProvider(apiKey: anthropicKey)
        } else {
            isAnalyzing = false
            showKeySetup = true
            return
        }

        // isAnalyzing was set synchronously by the caller.
        // Reset state so a retry after navigating back works correctly.
        navigateToResults = false
        cloudResults = [:]
        partialError = nil
        var firstError: String?
        // Sequential — parallel requests trigger OpenAI's per-minute rate limit.
        for entry in entries {
            guard let photo = entry.capturedPhoto else { continue }
            let prompt = info.category.cloudPrompt(for: entry.shot)
            do {
                cloudResults[entry.id] = try await provider.analyze(photo: photo, prompt: prompt)
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }
        isAnalyzing = false
        if cloudResults.isEmpty, let error = firstError {
            // Every call failed — surface the error so the user knows why nothing appeared.
            analysisError = error
        } else {
            // At least one result — navigate to results.
            // If some shots failed, surface a non-blocking warning in the results screen.
            if firstError != nil {
                partialError = firstError
            }
            navigateToResults = true
        }
    }
}

// MARK: - ShotCell

private struct ShotCell: View {
    let entry: ShotEntry
    let isActive: Bool
    let namespace: Namespace.ID
    let aestheticModel: HomeListingAestheticModel?

    /// Populated asynchronously for camera-roll photos that bypassed live analysis.
    @State private var asyncScore: Double?

    private var displayScore: Double? {
        // Live-captured photos: use the EMA score frozen at capture time.
        // Library photos (frameResult == nil): use the async score once computed.
        entry.capturedPhoto?.frameResult?.rules["sc.aesthetic"]?.numericScore ?? asyncScore
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if let img = entry.cachedImage {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(entry.shot.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .clipped()
            }
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if let score = displayScore {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.caption.weight(.semibold))
                        Text(score, format: .number.precision(.fractionLength(0))).font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(score >= 80 ? Color.green : score >= 50 ? Color.orange : Color.red)
                    .clipShape(Capsule())
                    .padding(6)
                }
            }
            .task(id: entry.capturedPhoto?.imageData) {
                // Only score asynchronously when there is no live frameResult
                // (i.e. photo came from the library, not the live camera).
                // Data is Hashable — using the full payload as the id guarantees
                // a new task fires whenever a different photo is assigned, even
                // if two photos happen to share the same byte count.
                guard entry.capturedPhoto?.frameResult?.rules["sc.aesthetic"] == nil,
                      let data = entry.capturedPhoto?.imageData,
                      let model = aestheticModel else { return }
                asyncScore = try? await model.score(imageData: data)
            }
            .matchedGeometryEffect(id: "photo_\(entry.id)", in: namespace, isSource: !isActive)
    }
}
