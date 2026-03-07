import SwiftUI
import ShotCoachCore

/// A horizontal row of colour-coded icons showing live rule status and scene classification.
///
/// Place this above the capture button as a replacement for the built-in `FeedbackStack`
/// text pills. Use `.hideFeedbackPills()` on `SCCameraGuidanceView` to suppress the
/// default pills when using this bar:
///
/// ```swift
/// // In your ZStack overlay, above the capture-button area:
/// SCRuleIconBar(result: sdk.frameResult, currentShot: sdk.currentShot)
///     .padding(.horizontal, 16)
/// ```
///
/// Each icon is coloured:
/// - **Green**  — rule passed.
/// - **Orange** — rule failed, severity `.warning`.
/// - **Red**    — rule failed, severity `.critical`.
///
/// The classification entry (rightmost) shows the top Vision scene label and is:
/// - **Green**  — detected scene matches the current required shot.
/// - **Orange** — detected scene is a recognised shot but not the current one.
/// - **Secondary** — Vision returned a label below the taxonomy threshold.
public struct SCRuleIconBar: View {

    public let result: SCFrameResult
    /// The current required shot — used to decide whether the detected scene icon
    /// is green (match) or orange (recognised but different shot).
    public let currentShot: SCShotType?

    public init(result: SCFrameResult, currentShot: SCShotType? = nil) {
        self.result      = result
        self.currentShot = currentShot
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(entries, id: \.id) { entry in
                iconCell(entry: entry)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // Animate colour changes as the live analysis updates every 1.5 s.
        .animation(.easeInOut(duration: 0.3), value: animationKey)
    }

    // MARK: - Private types

    private struct Entry: Identifiable {
        let id: String
        let icon: String
        let label: String
        let color: Color
    }

    // MARK: - Private helpers

    /// Fixed display order for quality rules. Only rules present in `result.rules` appear.
    private static let ruleVisuals: [(id: String, icon: String, label: String)] = [
        ("sc.brightness",        "sun.max",                              "Light"),
        ("sc.blur",              "camera.aperture",                      "Sharp"),
        ("sc.horizon",           "level",                                "Level"),
        ("sc.aesthetic",         "sparkles",                             "Vibe"),
        ("sc.instagrammability", "sparkles",                             "Vibe"),
        ("sc.distance",          "arrow.up.left.and.arrow.down.right",   "Distance"),
        ("sc.reflection",        "rays",                                 "Refl."),
    ]

    private var entries: [Entry] {
        var out: [Entry] = []

        // Quality rules — only show rules active for the current category
        // (present in result.rules). Inactive rules are omitted entirely.
        for (id, icon, defaultLabel) in Self.ruleVisuals {
            guard let r = result.rules[id] else { continue }
            let color: Color = r.passed ? .green : (r.severity == .critical ? .red : .orange)
            // Instagrammability rule: show numeric score when available, else fall back to label.
            let label: String
            if (id == "sc.aesthetic" || id == "sc.instagrammability"), let score = r.numericScore {
                label = String(format: "%.1f", score)
            } else {
                label = defaultLabel
            }
            out.append(Entry(id: id, icon: icon, label: label, color: color))
        }

        // Scene classification — always appended last.
        let hasLabel    = result.topSceneLabel != nil
        let hasMatch    = result.detectedShotType != nil
        let matchesCurr = hasMatch && result.detectedShotType?.id == currentShot?.id
        let sceneColor: Color = matchesCurr ? .green
                              : hasMatch     ? .orange
                              : hasLabel     ? Color(white: 0.75)
                                            : Color(white: 0.40)
        let sceneIcon  = matchesCurr ? "checkmark.circle.fill" : "viewfinder"
        let sceneLabel = result.topSceneLabel ?? "Scene"
        out.append(Entry(id: "sc.shot_classifier",
                         icon: sceneIcon,
                         label: sceneLabel,
                         color: sceneColor))
        return out
    }

    @ViewBuilder
    private func iconCell(entry: Entry) -> some View {
        VStack(spacing: 4) {
            Image(systemName: entry.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(entry.color)
            Text(entry.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(entry.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
    }

    /// A compact string that changes whenever any rule status or the scene label changes.
    /// Used as the `value` for `.animation` so each 1.5 s frame update triggers a smooth
    /// colour transition rather than an abrupt swap.
    private var animationKey: String {
        let rules = result.rules
            .sorted { $0.key < $1.key }
            .map    { "\($0.key)=\($0.value.passed)" }
            .joined(separator: ",")
        return rules + "|" + (result.topSceneLabel ?? "")
    }
}
