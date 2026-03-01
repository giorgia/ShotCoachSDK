import Foundation

/// GPT-4o prompt templates for each built-in SCBuiltInCategory.
/// Prompts are semi-stable: they may improve in patch releases without a major version bump.
/// This type is intentionally `internal` — `SCBuiltInCategory.cloudPrompt(for:)` is the
/// stable public API surface.
internal enum SCBuiltInPrompts {

    static func prompt(category: SCBuiltInCategory, shot: SCShotType) -> String {
        switch category {
        case .homeListing:  return homeListing(shot)
        case .carListing:   return carListing(shot)
        case .productPhoto: return productPhoto(shot)
        case .foodPhoto:    return foodPhoto(shot)
        }
    }

    // MARK: - Home Listing

    private static func homeListing(_ shot: SCShotType) -> String {
        let context: String
        switch shot.id {
        case "living_room":      context = "a living room"
        case "kitchen":          context = "a kitchen"
        case "master_bedroom":   context = "a master bedroom"
        case "bathroom":         context = "a bathroom"
        case "front_exterior":   context = "the front exterior of the home"
        case "backyard":         context = "a backyard or outdoor living space"
        default:                 context = "a room in the home"
        }
        return """
            Analyze this real-estate listing photo of \(context). Evaluate:
            • Natural light quality, evenness, and absence of harsh shadows
            • Camera level — architectural lines should be vertical and straight
            • Image sharpness, focus, and motion blur
            • Staging quality — clutter, furniture arrangement, and visual noise
            • Composition — use of space, leading lines, and depth
            • Overall listing appeal — would this photo attract a buyer?
            Return honest, actionable feedback a photographer can act on immediately.
            """
    }

    // MARK: - Car Listing

    private static func carListing(_ shot: SCShotType) -> String {
        let context: String
        switch shot.id {
        case "front_three_quarter":    context = "the front three-quarter angle"
        case "rear_three_quarter":     context = "the rear three-quarter angle"
        case "driver_side_profile":    context = "the full driver-side profile"
        case "passenger_side_profile": context = "the full passenger-side profile"
        case "dashboard":              context = "the dashboard and instrument cluster"
        case "interior_seats":         context = "the interior cabin and seating"
        case "engine_bay":             context = "the engine bay"
        case "trunk":                  context = "the trunk or cargo area"
        default:                       context = "a vehicle angle"
        }
        return """
            Analyze this car listing photo of \(context). Evaluate:
            • Lighting quality — even coverage, absence of blown highlights or deep shadows
            • Reflections and glare on body panels, glass, or chrome trim
            • Sharpness and depth of field across the vehicle
            • Subject distance and framing — is the whole subject in shot?
            • Background — is it clean, appropriate, and non-distracting?
            • Dirt, scratches, or damage visible in the frame
            Return honest, actionable feedback a photographer can act on immediately.
            """
    }

    // MARK: - Product Photo

    private static func productPhoto(_ shot: SCShotType) -> String {
        let context: String
        switch shot.id {
        case "front_view":         context = "the front face of the product"
        case "back_view":          context = "the back of the product"
        case "side_view":          context = "a side profile of the product"
        case "top_view":           context = "a top-down view of the product"
        case "detail":             context = "a close-up detail of the product"
        case "product_lifestyle":  context = "the product in a lifestyle or in-use setting"
        default:                   context = "the product"
        }
        return """
            Analyze this e-commerce product photo showing \(context). Evaluate:
            • Exposure accuracy and white balance — colours should be true-to-life
            • Sharpness and fine-detail rendering across the product surface
            • Reflections or unwanted glare on product materials
            • Background consistency — pure white, seamless, or intentional lifestyle scene
            • Framing — subject centred with adequate safe-zone margins
            • Overall marketplace quality — would this drive buyer confidence?
            Return honest, actionable feedback a photographer can act on immediately.
            """
    }

    // MARK: - Food Photo

    private static func foodPhoto(_ shot: SCShotType) -> String {
        let context: String
        switch shot.id {
        case "hero":           context = "an overhead hero shot of the dish"
        case "side_angle":     context = "a 45-degree side-angle shot of the dish"
        case "close_detail":   context = "a close-up detail of the hero element"
        case "full_plate":     context = "the complete plated dish"
        case "food_lifestyle": context = "the dish in a lifestyle or environmental setting"
        default:               context = "the dish"
        }
        return """
            Analyze this food photography shot — \(context). Evaluate:
            • Warmth, color accuracy, and flattery of the lighting on the food
            • Sharpness and depth of field on the primary hero element
            • Composition, styling, and prop selection
            • Background and surface texture — does it complement the food?
            • Appetite appeal — does the food look fresh, vibrant, and inviting?
            • Any distracting elements — stray crumbs, utensil placement, shadows
            Return honest, actionable feedback a photographer can act on immediately.
            """
    }
}
