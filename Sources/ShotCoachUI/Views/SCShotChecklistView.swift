import SwiftUI
import ShotCoachCore

/// Shows the session's required shots as a checklist.
/// Shots before `sdk.currentShot` are marked complete; the current and remaining shots are pending.
/// When `sdk.currentShot` is `nil` all shots are marked complete.
public struct SCShotChecklistView: View {

    @ObservedObject private var sdk: ShotCoach
    @Environment(\.scTheme) private var theme

    public init(sdk: ShotCoach) {
        self._sdk = ObservedObject(wrappedValue: sdk)
    }

    public var body: some View {
        List(sdk.category.requiredShots, id: \.id) { shot in
            let done = completedShotIDs.contains(shot.id)
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? theme.accent : Color.secondary)
                Text(shot.displayName)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .strikethrough(done)
            }
            .animation(.default, value: done)
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
