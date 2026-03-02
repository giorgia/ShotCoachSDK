import SwiftUI
import ShotCoachCore
import ShotCoachUI

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
                    ForEach(entries) { entry in
                        ResultRow(entry: entry, cloudResult: cloudResults[entry.id])
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }

                        if entry.id != entries.last?.id {
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
            SCResultsView(photo: SCPhoto(
                imageData: entry.capturedPhoto!.imageData,
                frameResult: entry.capturedPhoto!.frameResult,
                cloudResult: cloudResults[entry.id]
            ))
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
        return total / cloudResults.count
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - ResultRow

private struct ResultRow: View {
    let entry: ShotEntry
    let cloudResult: SCCloudResult?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
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
#if canImport(UIKit)
            if let ui = UIImage(data: photo.imageData) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.2)
            }
#else
            if let ns = NSImage(data: photo.imageData) {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.2)
            }
#endif
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

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}
