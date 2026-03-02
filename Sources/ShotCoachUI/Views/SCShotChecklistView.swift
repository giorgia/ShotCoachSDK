import SwiftUI
import ShotCoachCore

/// Shows the session's required shots as a checklist.
///
/// Shots before `sdk.currentShot` are marked complete; the current and remaining
/// shots are pending. When `sdk.currentShot` is `nil` all shots are marked complete.
///
/// When `SCShotClassifierRule` identifies the scene in the current frame with
/// sufficient confidence, the matching row is highlighted with a camera icon and
/// a subtle "Detected" badge — useful when the user is shooting out of order or
/// wants visual confirmation that the SDK recognises the current scene.
public struct SCShotChecklistView: View {

    @ObservedObject private var sdk: ShotCoach
    @Environment(\.scTheme) private var theme

    public init(sdk: ShotCoach) {
        self._sdk = ObservedObject(wrappedValue: sdk)
    }

    public var body: some View {
        List(sdk.category.requiredShots, id: \.id) { shot in
            let done     = completedShotIDs.contains(shot.id)
            let detected = sdk.frameResult.detectedShotType?.id == shot.id && !done

            HStack(spacing: 12) {
                // Icon: checkmark when done, camera when detected, circle otherwise.
                Image(systemName: done     ? "checkmark.circle.fill"
                                : detected ? "camera.fill"
                                           : "circle")
                    .foregroundStyle(done || detected ? theme.accent : Color.secondary)

                Text(shot.displayName)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .strikethrough(done)

                Spacer()

                // "Detected" badge — appears on the row whose scene the camera
                // currently recognises (confidence > classifier threshold).
                if detected {
                    Text("Detected")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.accent.opacity(0.12))
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: done)
            .animation(.easeInOut(duration: 0.25), value: detected)
        }
        .listStyle(.plain)
    }

    // MARK: - Private

    /// IDs of all shots that precede `currentShot` in the required-shots list.
    /// - `currentShot == nil`  → session complete; returns all shot IDs.
    /// - `currentShot` not found in `requiredShots` → defensive; returns empty set.
    private var completedShotIDs: Set<String> {
        guard let current = sdk.currentShot else {
            // Session complete — all required shots captured.
            return Set(sdk.category.requiredShots.map(\.id))
        }
        guard let idx = sdk.category.requiredShots.firstIndex(of: current) else {
            // currentShot not in requiredShots — treat as no shots completed.
            return []
        }
        return Set(sdk.category.requiredShots.prefix(idx).map(\.id))
    }
}
