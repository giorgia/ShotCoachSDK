# ShotCoach Integration Guide

ShotCoach has three integration patterns, ordered by complexity. Start with Pattern A
and only move to B or C when you need something the built-in categories don't provide.

---

## Pattern A — Zero config (built-in category)

The simplest integration. Pick a built-in category, supply your API key, done.

```swift
import ShotCoachCore
import ShotCoachUI

// 1. Create the SDK instance — one line.
let sdk = ShotCoach(category: .homeListing, apiKey: myApiKey)

// 2. Present the camera view — works like any SwiftUI view.
SCCameraGuidanceView(sdk: sdk)
    .theme(SCTheme(accent: .green, overlayStyle: .frostedGlass))
    .onResult { photo in
        // photo.cloudResult is nil here; GPT-4o populates it asynchronously.
        save(photo)
    }
```

Four built-in categories are available out of the box:

| Category | `SCBuiltInCategory` | On-device rules | Required shots |
|---|---|---|---|
| Home listing | `.homeListing` | Brightness, Horizon, Blur, Clutter | 6 |
| Car listing | `.carListing` | Brightness, Reflection, Blur, Distance | 8 |
| Product photo | `.productPhoto` | Brightness, Blur, Reflection, Horizon | 6 |
| Food photo | `.foodPhoto` | Brightness, Blur, Horizon | 5 |

**See `CameraSessionView.swift` in this demo for a fully annotated Pattern A example.**

---

## Pattern B — Extend a built-in

Add your own GPT-4o prompt, required shots, or on-device rules on top of a built-in
category. Your customisations stay in your app; the SDK prompt is untouched.

```swift
// Build the extended config — use .extending { } on any SCBuiltInCategory.
let config = SCBuiltInCategory.homeListing.extending { override in

    // Append extra evaluation criteria to the GPT-4o prompt.
    override.appendPrompt("""
        Additionally evaluate:
        (1) Natural light quality — rate window light vs artificial.
        (2) Outdoor amenities — pool, hot tub, patio furniture if present.
        (3) Whether the space looks 'Instagram-worthy' for short-term guests.
        """)

    // Add a required shot unique to your use case.
    override.addRequiredShot(SCShotType(id: "outdoor_space", displayName: "Outdoor Space"))
}

// Pass the override to ShotCoach exactly like a built-in.
let sdk = ShotCoach(category: config, apiKey: myApiKey)
```

**Note:** custom rules added via `override.addRule(_:)` are runtime-only.
After decoding a serialised `SCCategoryOverride` from JSON, re-apply rules via
`.extending { $0.addRule(MyRule()) }`.

---

## Pattern C — Fully custom category

Conform any struct to `SCCategoryConfig` for complete control.

```swift
struct ApartmentRentalConfig: SCCategoryConfig {

    var categoryID: String { "apartment_rental" }
    var displayName: String { "Apartment Rental" }

    // Required shots drive the checklist strip inside SCCameraGuidanceView.
    var requiredShots: [SCShotType] {[
        SCShotType(id: "living",   displayName: "Living Room"),
        SCShotType(id: "kitchen",  displayName: "Kitchen"),
        SCShotType(id: "bedroom",  displayName: "Bedroom"),
        SCShotType(id: "bathroom", displayName: "Bathroom"),
        SCShotType(id: "view",     displayName: "View / Balcony"),
    ]}

    // On-device rules run every 1.5 s, must complete in < 80 ms.
    var onDeviceRules: [any SCFrameRule] {[
        SCBrightnessRule(),
        SCHorizonRule(),
        SCBlurRule(),
    ]}

    // Cloud prompt is called once per captured photo, with the active shot type.
    func cloudPrompt(for shot: SCShotType) -> String {
        """
        You are evaluating a rental apartment photo for the '\(shot.displayName)' shot.
        Rate from 0–100 and return JSON: { "score": Int, "issues": [...], "recommendations": [...] }
        Criteria: natural light, tidiness, composition, sense of space.
        """
    }
}

// Usage is identical to Pattern A.
let sdk = ShotCoach(category: ApartmentRentalConfig(), apiKey: myApiKey)
```

---

## Theming

`SCTheme` controls the accent colour, overlay style, and feedback position.
Apply it via the `.theme()` view modifier — it propagates through the environment
to all SDK overlays automatically.

```swift
// Dark UI, lime accent (as used in this demo for homeListing)
SCTheme(accent: Color(red: 0.494, green: 0.847, blue: 0.251), overlayStyle: .frostedGlass)

// Light / clean (productPhoto)
SCTheme(accent: .black, overlayStyle: .minimal)

// Three presets (defined in SCThemePresets.swift)
.theme(.minimal)
.theme(.bold)
```

---

## API key security

ShotCoach never logs, prints, or embeds your API key in URLs.
Always store it in the Keychain via `SCKeychainService`:

```swift
// Save (overwrites any existing value)
SCKeychainService.save(key: "openai_api_key", value: userInput)

// Load — returns nil if not set
let key = SCKeychainService.load(key: "openai_api_key")

// Delete
SCKeychainService.delete(key: "openai_api_key")
```

Never pass a hardcoded key literal to `ShotCoach(category:apiKey:)`.

---

## Camera permissions

Add `NSCameraUsageDescription` to your app's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>ShotCoach needs camera access to guide and analyse your photos.</string>
```

`SCCameraSession` requests permission automatically on first `start()` call.
