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
            // Hints use Vision taxonomy substrings. Multiple hints per shot let the
            // classifier accumulate confidence across related observations (e.g. a
            // kitchen scores on "kitchen" + "appliance" + "counter" simultaneously).
            return [
                SCShotType(id: "living_room", displayName: "Living Room",
                           classificationHints: [
                               "living room", "living_room", "lounge", "sofa", "couch",
                               "armchair", "ottoman", "coffee table", "rug", "carpet",
                               "fireplace", "bookcase", "bookshelf", "curtain", "drape",
                               "television", "tv", "entertainment",
                           ]),
                SCShotType(id: "kitchen", displayName: "Kitchen",
                           classificationHints: [
                               "kitchen", "stove", "oven", "range", "refrigerator", "fridge",
                               "countertop", "counter", "cabinet", "cupboard", "appliance",
                               "microwave", "dishwasher", "sink", "faucet", "cooking",
                               "backsplash", "island",
                           ]),
                SCShotType(id: "master_bedroom", displayName: "Master Bedroom",
                           classificationHints: [
                               "bedroom", "bed", "pillow", "mattress", "duvet", "blanket",
                               "comforter", "nightstand", "bedside", "wardrobe", "dresser",
                               "closet", "headboard", "lamp", "sleeping",
                           ]),
                SCShotType(id: "bathroom", displayName: "Bathroom",
                           classificationHints: [
                               "bathroom", "toilet", "shower", "bathtub", "tub", "towel",
                               "tile", "mirror", "vanity", "sink", "faucet", "lavatory",
                               "restroom", "soap", "showerhead",
                           ]),
                SCShotType(id: "front_exterior", displayName: "Front Exterior",
                           classificationHints: [
                               "house", "building", "facade", "exterior", "architecture",
                               "door", "driveway", "roof", "porch", "balcony", "window",
                               "brick", "garage", "pathway", "entrance",
                           ]),
                SCShotType(id: "backyard", displayName: "Backyard",
                           classificationHints: [
                               "garden", "grass", "yard", "outdoor", "patio", "pool",
                               "tree", "lawn", "deck", "fence", "landscape", "plant",
                               "flower", "terrace", "pergola",
                           ]),
            ]
        case .carListing:
            return [
                SCShotType(id: "front_three_quarter", displayName: "Front 3/4",
                           classificationHints: [
                               "car", "automobile", "vehicle", "automotive", "headlight",
                               "hood", "bumper", "grille", "windshield", "fender",
                           ]),
                SCShotType(id: "rear_three_quarter", displayName: "Rear 3/4",
                           classificationHints: [
                               "car", "automobile", "vehicle", "automotive", "taillight",
                               "trunk", "bumper", "exhaust", "spoiler",
                           ]),
                SCShotType(id: "driver_side_profile", displayName: "Driver Side",
                           classificationHints: [
                               "car", "automobile", "vehicle", "door", "wheel", "tire",
                               "rim", "side mirror", "profile",
                           ]),
                SCShotType(id: "passenger_side_profile", displayName: "Passenger Side",
                           classificationHints: [
                               "car", "automobile", "vehicle", "door", "wheel", "tire",
                               "rim", "side mirror",
                           ]),
                SCShotType(id: "dashboard", displayName: "Dashboard",
                           classificationHints: [
                               "dashboard", "cockpit", "steering", "car interior",
                               "vehicle interior", "gauge", "speedometer", "instrument",
                               "windshield", "console", "gear", "display",
                           ]),
                SCShotType(id: "interior_seats", displayName: "Interior / Seats",
                           classificationHints: [
                               "seat", "interior", "leather", "upholstery", "headrest",
                               "car interior", "vehicle interior", "door panel", "bench",
                           ]),
                SCShotType(id: "engine_bay", displayName: "Engine Bay",
                           classificationHints: [
                               "engine", "motor", "machinery", "mechanical", "battery",
                               "oil", "radiator", "manifold",
                           ]),
                SCShotType(id: "trunk", displayName: "Trunk",
                           classificationHints: [
                               "trunk", "cargo", "storage", "hatchback", "boot", "luggage",
                           ]),
            ]
        case .productPhoto:
            // Product shots are orientation-based and product-agnostic — hints focus on
            // the studio/presentation context rather than the product itself.
            return [
                SCShotType(id: "front_view", displayName: "Front View",
                           classificationHints: [
                               "product", "object", "display", "item", "retail", "studio",
                           ]),
                SCShotType(id: "back_view", displayName: "Back View",
                           classificationHints: [
                               "product", "object", "display", "item", "retail",
                           ]),
                SCShotType(id: "side_view", displayName: "Side View",
                           classificationHints: [
                               "product", "object", "display", "item",
                           ]),
                SCShotType(id: "top_view", displayName: "Top View",
                           classificationHints: [
                               "product", "object", "flat lay", "overhead",
                           ]),
                SCShotType(id: "detail", displayName: "Detail / Close-up",
                           classificationHints: [
                               "texture", "detail", "pattern", "material", "macro", "close",
                           ]),
                // Prefixed "product_" to avoid ID collision with foodPhoto's lifestyle shot.
                SCShotType(id: "product_lifestyle", displayName: "Lifestyle / In Context",
                           classificationHints: [
                               "lifestyle", "context", "setting", "scene", "environment",
                               "table", "room",
                           ]),
            ]
        case .foodPhoto:
            return [
                SCShotType(id: "hero", displayName: "Hero Shot",
                           classificationHints: [
                               "food", "dish", "meal", "plate", "cuisine", "restaurant",
                               "eat", "dining", "delicious", "gourmet", "entree",
                           ]),
                SCShotType(id: "side_angle", displayName: "Side Angle",
                           classificationHints: [
                               "food", "dish", "meal", "plate", "cuisine", "drink",
                               "beverage", "glass", "cup",
                           ]),
                SCShotType(id: "close_detail", displayName: "Close Detail",
                           classificationHints: [
                               "food", "ingredient", "texture", "garnish", "herb",
                               "spice", "sauce", "macro",
                           ]),
                SCShotType(id: "full_plate", displayName: "Full Plate",
                           classificationHints: [
                               "plate", "bowl", "dish", "food", "meal", "serving",
                               "table", "tablecloth",
                           ]),
                // Prefixed "food_" to avoid ID collision with productPhoto's lifestyle shot.
                SCShotType(id: "food_lifestyle", displayName: "Lifestyle",
                           classificationHints: [
                               "restaurant", "cafe", "dining", "table", "setting",
                               "lifestyle", "background", "ambiance",
                           ]),
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
            // SCClutterRule is intentionally omitted: styled food photography relies on
            // props and garnish that would incorrectly trigger clutter detection.
            return [SCBrightnessRule(), SCBlurRule(), SCHorizonRule(maxTiltDegrees: 15.0)]
        }
    }

    /// Returns the GPT-4o prompt for `shot`.
    /// This is the stable API surface for the built-in prompt system; the underlying
    /// prompt text may improve in patch releases but the method signature will not change.
    public func cloudPrompt(for shot: SCShotType) -> String {
        SCBuiltInPrompts.prompt(category: self, shot: shot)
    }

    // MARK: - Extending

    /// Returns a customised copy of this category with extra prompt context, shots, and/or rules.
    ///
    /// The returned `SCCategoryOverride` is a value type — changes to `self` after
    /// calling this method do not affect the returned override.
    /// - Parameter configure: A closure that mutates the override before it is returned.
    public func extending(
        _ configure: (inout SCCategoryOverride) -> Void
    ) -> SCCategoryOverride {
        var override = SCCategoryOverride(base: self)
        configure(&override)
        return override
    }
}
