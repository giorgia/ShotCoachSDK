import SwiftUI
import ShotCoachCore
import ShotCoachUI

// MARK: - ShotEntry

/// One slot in the shot grid: the required shot type and, once captured, its photo.
struct ShotEntry: Identifiable {
    let id: String          // == shot.id
    let shot: SCShotType
    var capturedPhoto: SCPhoto?
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
    @State private var cloudResults: [String: SCCloudResult] = [:]
    @State private var isAnalyzing = false
    @State private var navigateToResults = false
    @State private var showKeySetup = false

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
                        ShotCell(
                            entry: entry,
                            isActive: activeShotID == entry.id,
                            namespace: heroNamespace
                        )
                        .onTapGesture { activeShotID = entry.id }
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
                    onCapture: { photo in
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                            entries[entryIdx].capturedPhoto = photo
                            activeShotID = nil
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
        .navigationTitle(info.category.displayName)
        .toolbar(activeShotID != nil ? .hidden : .visible, for: .navigationBar)
        .background(Color(white: 0.05).ignoresSafeArea())
        .toolbar {
            if entries.allSatisfy({ $0.capturedPhoto != nil }) {
                ToolbarItem(placement: .primaryAction) {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Button("Send to AI") {
                            if SCKeychainService.load(key: "openai_api_key") == nil {
                                showKeySetup = true
                            } else {
                                // Set isAnalyzing synchronously before the Task suspends
                                // to prevent a double-tap from launching two analyses.
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
            SessionResultsView(entries: entries, cloudResults: cloudResults, info: info)
        }
        .sheet(isPresented: $showKeySetup) {
            APIKeySetupView { showKeySetup = false }
        }
    }

    // MARK: - Batch analysis

    @MainActor
    private func runBatchAnalysis() async {
        let key = SCKeychainService.load(key: "openai_api_key") ?? ""
        // isAnalyzing was set synchronously by the caller.
        // Reset state so a retry after navigating back works correctly.
        navigateToResults = false
        cloudResults = [:]
        let provider = SCOpenAIProvider(apiKey: key)
        await withTaskGroup(of: (String, SCCloudResult?).self) { group in
            for entry in entries {
                guard let photo = entry.capturedPhoto else { continue }
                let prompt = info.category.cloudPrompt(for: entry.shot)
                let entryID = entry.id
                group.addTask {
                    return (entryID, try? await provider.analyze(photo: photo, prompt: prompt))
                }
            }
            for await (id, result) in group {
                if let result { cloudResults[id] = result }
            }
        }
        isAnalyzing = false
        navigateToResults = true
    }
}

// MARK: - ShotCell

private struct ShotCell: View {
    let entry: ShotEntry
    let isActive: Bool
    let namespace: Namespace.ID

    // Decoded once via .task(id:) — avoids re-decoding multi-megabyte JPEG on every render.
#if canImport(UIKit)
    @State private var cached: UIImage?
#else
    @State private var cached: NSImage?
#endif

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if entry.capturedPhoto != nil {
                        cachedPhotoView.scaledToFill()
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
            .matchedGeometryEffect(id: "photo_\(entry.id)", in: namespace, isSource: !isActive)
            .task(id: entry.capturedPhoto?.imageData.hashValue) {
                guard let data = entry.capturedPhoto?.imageData else { return }
#if canImport(UIKit)
                cached = UIImage(data: data)
#else
                cached = NSImage(data: data)
#endif
            }
    }

    @ViewBuilder
    private var cachedPhotoView: some View {
        if let cached {
#if canImport(UIKit)
            Image(uiImage: cached).resizable()
#else
            Image(nsImage: cached).resizable()
#endif
        } else {
            Color(white: 0.2)
        }
    }
}
