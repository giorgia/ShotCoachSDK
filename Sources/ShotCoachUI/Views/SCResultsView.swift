import SwiftUI
import ShotCoachCore

/// Displays the cloud analysis result for a captured photo: quality score, issues list,
/// and ranked recommendations. Shows a loading spinner when `photo.cloudResult` is nil.
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
            VStack(spacing: 12) {
                ProgressView()
                Text("Analyzing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Issues")
                .font(.headline)
            ForEach(
                issues.sorted { impactRank($0.impact) > impactRank($1.impact) },
                id: \.title
            ) { issue in
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations")
                .font(.headline)
            ForEach(
                recs.sorted { $0.priority < $1.priority },
                id: \.text
            ) { rec in
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
