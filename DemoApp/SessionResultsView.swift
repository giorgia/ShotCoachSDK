import SwiftUI
import ShotCoachCore
import ShotCoachUI

// MARK: - Helpers

private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return .green
    case 60..<80: return .orange
    default: return .red
    }
}

// MARK: - SessionResultsView

/// Post-analysis results screen shown after "Send to AI" batch analysis completes.
///
/// Header shows the average quality score across all shots (or a "no analysis" state
/// if no API key was configured). Scrollable list of rows — tap any row to open the
/// full `SCResultsView` sheet for that shot.
struct SessionResultsView: View {

    let entries: [ShotEntry]
    let cloudResults: [String: SCCloudResult]
    let info: CategoryInfo

    @State private var selectedEntry: ShotEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Average score header — centred above the list.
                scoreHeader
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                // Shot rows.
                LazyVStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { i in
                        let entry = entries[i]
                        ResultRow(entry: entry, cloudResult: cloudResults[entry.id])
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }

                        if i < entries.count - 1 {
                            Divider()
                                .padding(.leading, 88)
                        }
                    }
                }
                .background(Color(white: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .navigationTitle("Results")
        .background(Color(white: 0.05).ignoresSafeArea())
        .sheet(item: $selectedEntry) { entry in
            // capturedPhoto is guaranteed non-nil by the time SessionResultsView is
            // presented (ShotListView only navigates when all slots are filled).
            // Guard defensively to avoid a crash if used in isolation (e.g. Previews).
            if let photo = entry.capturedPhoto {
                SCResultsView(photo: SCPhoto(
                    imageData: photo.imageData,
                    frameResult: photo.frameResult,
                    cloudResult: cloudResults[entry.id]
                ))
            }
        }
    }

    // MARK: - Score header

    @ViewBuilder
    private var scoreHeader: some View {
        if let avg = averageScore {
            VStack(spacing: 6) {
                Text("\(avg)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(avg))
                Text("Average Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Surface partial scoring so the average isn't silently misleading.
                if cloudResults.count < entries.count {
                    Text("\(cloudResults.count) of \(entries.count) shots scored")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("All shots captured")
                    .font(.headline)
                Text("Add an OpenAI API key to unlock AI scoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var averageScore: Int? {
        guard !cloudResults.isEmpty else { return nil }
        let total = cloudResults.values.reduce(0) { $0 + $1.score }
        // Use Double division and round to avoid integer truncation bias
        // (e.g. 79.5 should round to 80/green, not truncate to 79/orange).
        return Int((Double(total) / Double(cloudResults.count)).rounded())
    }
}

// MARK: - ResultRow

private struct ResultRow: View {
    let entry: ShotEntry
    let cloudResult: SCCloudResult?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail — decoded once via ThumbnailView, not on every render.
            thumbnailView
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 12)

            // Shot name + top issue
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.shot.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let issue = topIssue {
                    Text(issue.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if cloudResult == nil {
                    Text("No analysis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Score badge
            if let score = cloudResult?.score {
                Text("\(score)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(scoreColor(score))
                    .padding(.trailing, 4)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailView: some View {
        if let photo = entry.capturedPhoto {
            ThumbnailView(data: photo.imageData)
        } else {
            Color(white: 0.2)
        }
    }

    // MARK: - Helpers

    private var topIssue: SCIssue? {
        cloudResult?.issues
            .sorted { impactRank($0.impact) > impactRank($1.impact) }
            .first
    }

    private func impactRank(_ impact: SCImpactLevel) -> Int {
        switch impact {
        case .low:    return 0
        case .medium: return 1
        case .high:   return 2
        }
    }
}

// MARK: - ThumbnailView

/// Decodes image data once via `.task(id:)` and caches the result so that
/// `UIImage(data:)` is never called on every view render.
private struct ThumbnailView: View {
    let data: Data

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(white: 0.2)
            }
        }
        .task(id: data.hashValue) {
            image = UIImage(data: data)
        }
    }
}
