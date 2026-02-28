import Foundation

/// The four production-ready photography categories included with ShotCoach.
///
/// Extend any case with `.extending { }` to append extra prompt context or
/// required shots without forking the entire config (Pattern B):
///
/// ```swift
/// let extended = SCBuiltInCategory.homeListing.extending {
///     $0.appendPrompt("Also evaluate pool visibility and outdoor dining areas.")
///     $0.addRequiredShot(SCShotType(id: "outdoor", displayName: "Outdoor Space"))
/// }
/// ```
public enum SCBuiltInCategory: String, SCCategoryConfig, Codable, Sendable {
    case homeListing
    case carListing
    case productPhoto
    case foodPhoto

    // MARK: - SCCategoryConfig

    public var categoryID: String { rawValue }

    public var displayName: String {
        switch self {
        case .homeListing:  return "Home Listing"
        case .carListing:   return "Car Listing"
        case .productPhoto: return "Product Photo"
        case .foodPhoto:    return "Food Photo"
        }
    }

    public var requiredShots: [SCShotType] {
        switch self {
        case .homeListing:
            return [
                SCShotType(id: "living_room",       displayName: "Living Room"),
                SCShotType(id: "kitchen",            displayName: "Kitchen"),
                SCShotType(id: "master_bedroom",     displayName: "Master Bedroom"),
                SCShotType(id: "bathroom",           displayName: "Bathroom"),
                SCShotType(id: "front_exterior",     displayName: "Front Exterior"),
                SCShotType(id: "backyard",           displayName: "Backyard"),
            ]
        case .carListing:
            return [
                SCShotType(id: "front_three_quarter",    displayName: "Front 3/4"),
                SCShotType(id: "rear_three_quarter",     displayName: "Rear 3/4"),
                SCShotType(id: "driver_side_profile",    displayName: "Driver Side"),
                SCShotType(id: "passenger_side_profile", displayName: "Passenger Side"),
                SCShotType(id: "dashboard",              displayName: "Dashboard"),
                SCShotType(id: "interior_seats",         displayName: "Interior / Seats"),
                SCShotType(id: "engine_bay",             displayName: "Engine Bay"),
                SCShotType(id: "trunk",                  displayName: "Trunk"),
            ]
        case .productPhoto:
            return [
                SCShotType(id: "front_view",  displayName: "Front View"),
                SCShotType(id: "back_view",   displayName: "Back View"),
                SCShotType(id: "side_view",   displayName: "Side View"),
                SCShotType(id: "top_view",    displayName: "Top View"),
                SCShotType(id: "detail",      displayName: "Detail / Close-up"),
                SCShotType(id: "lifestyle",   displayName: "Lifestyle / In Context"),
            ]
        case .foodPhoto:
            return [
                SCShotType(id: "hero",         displayName: "Hero Shot"),
                SCShotType(id: "side_angle",   displayName: "Side Angle"),
                SCShotType(id: "close_detail", displayName: "Close Detail"),
                SCShotType(id: "full_plate",   displayName: "Full Plate"),
                SCShotType(id: "lifestyle",    displayName: "Lifestyle"),
            ]
        }
    }

    public var onDeviceRules: [any SCFrameRule] {
        switch self {
        case .homeListing:
            // Level horizon matters strongly for architectural shots.
            return [SCBrightnessRule(), SCHorizonRule(), SCBlurRule(), SCClutterRule()]
        case .carListing:
            // Reflections on bodywork and glass are a primary quality signal.
            return [SCBrightnessRule(), SCReflectionRule(), SCBlurRule(), SCDistanceRule()]
        case .productPhoto:
            // Reflections on product surfaces and tight framing are key.
            return [SCBrightnessRule(), SCBlurRule(), SCReflectionRule(), SCHorizonRule()]
        case .foodPhoto:
            // Overhead hero shots are deliberately tilted — relax horizon to ±15°.
            return [SCBrightnessRule(), SCBlurRule(), SCHorizonRule(maxTiltDegrees: 15.0)]
        }
    }

    public func cloudPrompt(for shot: SCShotType) -> String {
        SCBuiltInPrompts.prompt(category: self, shot: shot)
    }

    // MARK: - Extending

    /// Returns a customised copy of this category with extra prompt context and/or shots.
    ///
    /// The returned `SCCategoryOverride` is a value type — changes to `self` after
    /// calling this method do not affect the returned override.
    public func extending(
        _ configure: (inout SCCategoryOverride) -> Void
    ) -> SCCategoryOverride {
        var override = SCCategoryOverride(base: self)
        configure(&override)
        return override
    }
}
