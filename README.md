# ShotCoach

**Real-time AI camera guidance for iOS — drop it into any app in 5 lines.**

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue)](https://developer.apple.com/ios/)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## What It Does

ShotCoach analyses your camera viewfinder in real time using on-device AI, tells the photographer exactly what to fix before they shoot, then runs a deep cloud analysis after capture and returns a structured quality report.

**Zero API cost for live guidance** — all real-time feedback runs on-device with Vision.framework. Cloud analysis (GPT-4o) only fires after the user taps the shutter.

---

## 5 Lines to Working AI Camera Coaching

```swift
import ShotCoachCore
import ShotCoachUI

let sdk = ShotCoach(category: .homeListing, apiKey: "sk-...")

CameraGuidanceView(sdk: sdk)
    .onResult { photo in print(photo.cloudResult?.score ?? 0) }
```

That's it. Live overlay, shot checklist, and post-capture analysis — all included.

---

## Built-in Categories

| Category | Required Shots | Key Rules | Best For |
|---|---|---|---|
| `.homeListing` | 6 | Brightness, horizon, blur, clutter | Airbnb, Zillow, VRBO |
| `.carListing` | 8 | Brightness, reflection, blur, distance | Facebook Marketplace, AutoTrader |
| `.productPhoto` | 6 | Brightness, blur, reflection, horizon | Shopify, Etsy, Amazon |
| `.foodPhoto` | 5 | Brightness, blur, horizon (relaxed) | Delivery apps, restaurant menus |

---

## Add Your Own Category in One Struct

```swift
struct WatchListingConfig: SCCategoryConfig {
    var categoryID = "watch_listing"
    var displayName = "Watch Photography"
    var requiredShots = [
        SCShotType(id: "dial_face", displayName: "Dial Face"),
        SCShotType(id: "clasp_detail", displayName: "Clasp Detail"),
        SCShotType(id: "side_profile", displayName: "Side Profile")
    ]
    var onDeviceRules: [SCFrameRule] = [
        SCBlurRule(minSharpnessScore: 90),
        SCReflectionRule(),
        SCBrightnessRule()
    ]
    func cloudPrompt(for frame: SCFrame) -> String {
        "Analyze this watch listing photo for: dial visibility, reflection glare, clasp condition, background cleanliness. Return JSON: {shot_score, issues, recommendations}"
    }
}

let sdk = ShotCoach(category: WatchListingConfig(), apiKey: "sk-...")
```

---

## Prompt System

Three patterns — pick the one that fits your use case:

```swift
// A — Zero config. Use a built-in prompt as-is.
ShotCoach(category: .homeListing, apiKey: key)

// B — Extend a built-in. Append your own context without forking.
ShotCoach(category: SCBuiltInCategory.homeListing.extending {
    $0.appendPrompt("Also evaluate pool visibility and outdoor dining areas.")
    $0.addRequiredShot(SCShotType(id: "outdoor", displayName: "Outdoor Space"))
}, apiKey: key)

// C — Fully custom. Your prompt, your shots, your rules.
ShotCoach(category: WatchListingConfig(), apiKey: key)
```

---

## Architecture

```
ShotCoach (SPM Package)
├── ShotCoachCore        ← headless engine, no UI imports, testable on Mac
│   ├── Protocols        ← SCFrameRule, SCCategoryConfig, SCCloudProvider, SCAnalysisDelegate
│   ├── Models           ← SCFrame, SCFrameResult, SCCloudResult, SCPhoto
│   ├── Rules            ← 6 on-device Vision.framework rules (<80ms each)
│   ├── Engine           ← SCFrameAnalyzer (concurrent, throttled to 1.5s)
│   ├── Cloud            ← SCOpenAIProvider (GPT-4o, retry logic, Keychain)
│   └── BuiltIn          ← SCBuiltInCategory (4 production configs + .extending())
│
├── ShotCoachUI          ← optional SwiftUI layer (imports ShotCoachCore)
│   ├── Theme            ← SCTheme, 3 presets, SwiftUI Environment
│   ├── Overlay          ← FeedbackPill, ReadyIndicator, BoundingBoxOverlay
│   └── Views            ← SCCameraGuidanceView, SCResultsView, SCShotChecklistView
│
└── ShotCoachDemo        ← App Store reference app (source = integration tutorial)
```

**Hybrid analysis pipeline:**

| Stage | Where | Cost | Latency |
|---|---|---|---|
| Live frame feedback | On-device (Vision.framework) | Free | <80ms |
| Post-capture deep analysis | Cloud (GPT-4o) | ~$0.02–0.05 | 2–5s |

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** and enter:

```
https://github.com/you/ShotCoach
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/you/ShotCoach", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "ShotCoachCore", package: "ShotCoach"),
        .product(name: "ShotCoachUI", package: "ShotCoach")   // optional
    ])
]
```

---

## Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+
- OpenAI API key (developer-provided, stored in Keychain)

---

## Theming

```swift
CameraGuidanceView(sdk: sdk)
    .theme(SCTheme(
        accent: .green,
        overlayStyle: .frostedGlass,   // .frostedGlass | .minimal | .bold
        feedbackPosition: .bottom      // .top | .bottom
    ))

// Or use a preset
CameraGuidanceView(sdk: sdk)
    .theme(.minimal)
```

---

## API Stability

`SCFrameRule`, `SCCategoryConfig`, `SCCloudProvider`, and `SCAnalysisDelegate` are stable from v1.0.0. See [API_STABILITY.md](API_STABILITY.md) for the full semver commitment.

---

## License

MIT — see [LICENSE](LICENSE).
