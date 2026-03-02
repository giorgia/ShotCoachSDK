import SwiftUI
import ShotCoachCore

/// Displays the cloud analysis result for a captured photo: quality score, issues list,
/// and ranked recommendations. Shows a "no analysis" placeholder when `photo.cloudResult`
/// is nil (e.g. no API key configured or cloud call failed).
public struct SCResultsView: View {

    let photo: SCPhoto
    @Environment(\.scTheme) private var theme

    public init(photo: SCPhoto) {
        self.photo = photo
    }

    public var body: some View {
        if let result = photo.cloudResult {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    scoreGauge(result.score)

                    if !result.issues.isEmpty {
                        issuesSection(result.issues)
                    }
                    if !result.recommendations.isEmpty {
                        recommendationsSection(result.recommendations)
                    }
                }
                .padding()
            }
        } else {
            // cloudResult is nil: either no API key is configured or the cloud call failed.
            // onResult fires after the cloud task completes, so nil always means "no result"
            // — never "in progress". Show a static placeholder instead of an infinite spinner.
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Photo saved")
                    .font(.headline)
                Text("Add an OpenAI API key in Settings to unlock AI scoring and recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Score gauge

    private func scoreGauge(_ score: Int) -> some View {
        VStack(spacing: 8) {
            Text("Quality Score")
                .font(.headline)
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        scoreColor(score),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
            }
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Issues

    private func issuesSection(_ issues: [SCIssue]) -> some View {
        let sorted = issues.sorted { impactRank($0.impact) > impactRank($1.impact) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Issues")
                .font(.headline)
            // Use indices as stable IDs — issue titles are not guaranteed unique.
            ForEach(sorted.indices, id: \.self) { i in
                let issue = sorted[i]
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(impactColor(issue.impact))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.subheadline.weight(.semibold))
                        Text(issue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Recommendations

    private func recommendationsSection(_ recs: [SCRecommendation]) -> some View {
        let sorted = recs.sorted { $0.priority < $1.priority }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations")
                .font(.headline)
            // Use indices as stable IDs — recommendation texts are not guaranteed unique.
            ForEach(sorted.indices, id: \.self) { i in
                let rec = sorted[i]
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .padding(.top, 3)
                    Text(rec.text)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60...: return .orange
        default:    return .red
        }
    }

    private func impactColor(_ impact: SCImpactLevel) -> Color {
        switch impact {
        case .low:    return .yellow
        case .medium: return .orange
        case .high:   return .red
        }
    }

    private func impactRank(_ impact: SCImpactLevel) -> Int {
        switch impact {
        case .low:    return 0
        case .medium: return 1
        case .high:   return 2
        }
    }
}
