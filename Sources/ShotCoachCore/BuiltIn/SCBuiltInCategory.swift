import Foundation

/// The four production-ready photography categories included with ShotCoach.
/// Extend any case with `.extending { ... }` to append prompts or add required shots.
public enum SCBuiltInCategory: SCCategoryConfig {
    case homeListing
    case carListing
    case productPhoto
    case foodPhoto
}
