import SwiftUI
import ShotCoachCore
import ShotCoachUI

/// Gallery tab — a scrollable grid of every photo captured this session.
///
/// Tap any thumbnail to open `SCResultsView`, which shows the score, issues,
/// and recommendations from cloud analysis (loading shimmer while pending).
struct GalleryView: View {

    @EnvironmentObject private var store: SessionStore
    @State private var selectedEntry: SessionStore.Entry?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    photoGrid
                }
            }
            .navigationTitle("Gallery")
            .background(Color.black.ignoresSafeArea())
        }
        // Tap a thumbnail → SCResultsView sheet (handles async cloud loading internally).
        .sheet(item: $selectedEntry) { entry in
            SCResultsView(photo: entry.photo)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("No photos yet")
                .font(.headline)

            Text("Pick a category and take your first shot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photoGrid: some View {
        let cloudEnabled = SCKeychainService.load(key: "openai_api_key") != nil
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(store.entries) { entry in
                    PhotoThumbnail(entry: entry, cloudEnabled: cloudEnabled)
                        .onTapGesture { selectedEntry = entry }
                }
            }
        }
    }
}

// MARK: - PhotoThumbnail

private struct PhotoThumbnail: View {
    let entry: SessionStore.Entry
    let cloudEnabled: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            photoImage
                .aspectRatio(1, contentMode: .fill)
                .clipped()

            scoreBadge
                .padding(6)
        }
    }

    // Platform-safe image loading: UIImage on iOS, NSImage on macOS.
    @ViewBuilder
    private var photoImage: some View {
#if canImport(UIKit)
        if let ui = UIImage(data: entry.photo.imageData) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
        } else {
            Color(white: 0.15)
        }
#else
        if let ns = NSImage(data: entry.photo.imageData) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFill()
        } else {
            Color(white: 0.15)
        }
#endif
    }

    // Score badge once cloud analysis arrives.
    // Shows a spinner while waiting (key configured) or "Local" when cloud is off.
    @ViewBuilder
    private var scoreBadge: some View {
        if let score = entry.photo.cloudResult?.score {
            Text("\(score)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(scoreColor(score).opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(Capsule())
        } else if cloudEnabled {
            // Key is set but result hasn't arrived yet — still waiting on GPT-4o.
            ProgressView()
                .scaleEffect(0.7)
                .padding(6)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        } else {
            // No API key — on-device analysis only.
            Text("Local")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.7))
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}
