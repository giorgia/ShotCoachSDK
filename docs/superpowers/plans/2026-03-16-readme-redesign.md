# README Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite README.md as a dual-purpose document — architecture-led portfolio piece and iOS developer integration reference.

**Architecture:** Option B structure: precise one-liner → architecture centrepiece → quick start → category/rule tables → CoreML pipeline → installation. Marketing prose and implementation-detail sections (Claude API, Theming, API Stability) are removed.

**Tech Stack:** Markdown, Git

**Spec:** `docs/superpowers/specs/2026-03-16-readme-redesign.md`

---

## Chunk 1: Skeleton + Header

### Task 1: Replace README with skeleton

**Files:**
- Modify: `README.md` (full rewrite)

- [ ] **Step 1: Replace the entire README with the new skeleton**

The full content of `README.md` should become:

```markdown
# ShotCoach

Real-time camera coaching for iOS. On-device Vision analysis every frame, cloud AI after the shutter.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue)](https://developer.apple.com/ios/)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## Architecture

## Quick Start

## Built-in Categories

## On-Device Rules

## CoreML Aesthetic Pipeline

## Installation

## Requirements

## License
```

- [ ] **Step 2: Verify the file renders correctly**

Check that all section headings are present and the badges line is intact.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: scaffold README redesign skeleton"
```

---

## Chunk 2: Architecture Section

### Task 2: Write the Architecture section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fill in the Architecture section**

Replace the empty `## Architecture` heading with:

```markdown
## Architecture

ShotCoach runs a hybrid analysis pipeline — on-device for every frame, cloud only after capture.

```
SCFrame (CVPixelBuffer + metadata)
        │
        ├── SCFrameAnalyzer (actor)
        │       ├── SCBrightnessRule    ─┐
        │       ├── SCHorizonRule        │
        │       ├── SCBlurRule           ├── concurrent withTaskGroup, throttled to 1.5s
        │       ├── SCDistanceRule       │
        │       ├── SCReflectionRule     │
        │       └── SCInstagrammabilityRule ─┘
        │               │
        │               ▼
        │       SCFrameResult  → SCAnalysisDelegate (MainActor)
        │
        └── (on shutter tap)
                SCOpenAIProvider / SCAnthropicProvider
                        │
                        ▼
                SCCloudResult { score, issues, recommendations }
```

**Why hybrid?** Vision.framework gives sub-80ms feedback with zero API cost. GPT-4o or Claude fires once per shot for the structured quality report that on-device models can't produce.

**Why actor isolation for SCFrameAnalyzer?** Rules run concurrently via `withTaskGroup`. The analyzer is an actor so the 1.5s throttle timestamp is mutation-safe across concurrent callers without a lock.

**Why protocol injection for CoreML models?** `SCAestheticRule` accepts any `SCAestheticModelProvider` — the SDK ships no bundled model weights. App targets own the `.mlpackage`, so model updates don't require an SDK release.
```

- [ ] **Step 2: Verify the diagram renders legibly in a Markdown previewer**

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Architecture section to README"
```

---

## Chunk 3: Quick Start Section

### Task 3: Write the Quick Start section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fill in the Quick Start section**

Replace the empty `## Quick Start` heading with:

```markdown
## Quick Start

### Pattern A — Zero config

```swift
import ShotCoachCore
import ShotCoachUI

let sdk = ShotCoach(category: .homeListing, apiKey: "sk-...")

SCCameraGuidanceView(sdk: sdk)
    .onResult { photo in print(photo.cloudResult?.score ?? 0) }
```

### Pattern B — Extend a built-in

```swift
ShotCoach(
    category: SCBuiltInCategory.homeListing.extending {
        $0.appendPrompt("Also evaluate pool visibility and outdoor dining areas.")
        $0.addRequiredShot(SCShotType(id: "outdoor", displayName: "Outdoor Space"))
    },
    apiKey: key
)
```

### Pattern C — Fully custom

```swift
struct WatchListingConfig: SCCategoryConfig {
    var categoryID = "watch_listing"
    var displayName = "Watch Photography"
    var requiredShots = [
        SCShotType(id: "dial_face",    displayName: "Dial Face"),
        SCShotType(id: "clasp_detail", displayName: "Clasp Detail"),
        SCShotType(id: "side_profile", displayName: "Side Profile"),
    ]
    var onDeviceRules: [any SCFrameRule] = [
        SCBlurRule(minSharpnessScore: 90),
        SCReflectionRule(),
        SCBrightnessRule(),
    ]
    func cloudPrompt(for shot: SCShotType) -> String {
        "Evaluate this watch listing photo: dial legibility, glare on crystal, clasp condition, background. Return JSON: {score, issues, recommendations}"
    }
}

let sdk = ShotCoach(category: WatchListingConfig(), apiKey: key)
```
```

- [ ] **Step 2: Verify all three code blocks are syntactically correct Swift**

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Quick Start section to README"
```

---

## Chunk 4: Categories + Rules Tables

### Task 4: Write the Built-in Categories and On-Device Rules sections

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fill in the Built-in Categories section**

Replace the empty `## Built-in Categories` heading with:

```markdown
## Built-in Categories

| Category | Shots | On-Device Rules |
|---|---|---|
| `.homeListing` | 6 | Brightness, Horizon, Blur, Instagrammability |
| `.carListing` | 8 | Brightness, Reflection, Blur, Distance |
| `.productPhoto` | 6 | Brightness, Blur, Reflection, Horizon |
| `.foodPhoto` | 5 | Brightness, Blur, Horizon (±15°), Instagrammability |
```

- [ ] **Step 2: Fill in the On-Device Rules section**

Replace the empty `## On-Device Rules` heading with:

```markdown
## On-Device Rules

All rules conform to `SCFrameRule` and must complete in under 80ms. They run concurrently per frame inside `SCFrameAnalyzer`.

| Rule | Measures | Signal |
|---|---|---|
| `SCBrightnessRule` | Average luminance (Rec.709) | Under/overexposure |
| `SCHorizonRule` | Horizon tilt via `VNDetectHorizonRequest` | Skewed architectural shots |
| `SCBlurRule` | Laplacian variance sharpness | Camera shake or missed focus |
| `SCDistanceRule` | Subject bounding box area | Subject too far or too close |
| `SCReflectionRule` | Specular highlight ratio | Glare on surfaces or glass |
| `SCInstagrammabilityRule` | Focal clarity, compositional balance, visual variety, lighting | Overall composition quality |
| `SCShotClassifierRule` | Scene type via hint-based Vision scoring | Wrong room detection |
```

- [ ] **Step 3: Verify both tables render correctly**

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add Built-in Categories and On-Device Rules sections to README"
```

---

## Chunk 5: CoreML Pipeline + Installation + Requirements + License

### Task 5: Write the CoreML Aesthetic Pipeline section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fill in the CoreML Aesthetic Pipeline section**

Replace the empty `## CoreML Aesthetic Pipeline` heading with:

```markdown
## CoreML Aesthetic Pipeline

`SCAestheticRule` blends a CoreML model with the Vision heuristic on every live frame.

```
CVPixelBuffer
    ├── mobileclip_s0_image  (CLIP encoder → 512-D embedding)  ─┐
    │                                                             ├── raw score (70%)
    ├── home_head_s0         (embedding → sigmoid [0, 1])       ─┘
    │
    └── SCInstagrammabilityRule  (Vision heuristic)  ── heuristic score (30%)
                │
                ▼
        blended score 0–100
                │
                ▼
        EMA  (α = 0.3)    ← suppresses per-frame jitter without external state
                │
                ▼
        SCRuleResult { passed, numericScore, message }
```

The model is injected via `SCAestheticModelProvider` — a `Sendable` protocol the app target implements. The SDK ships no model weights. `DemoApp/MLModels/` contains the reference `.mlpackage` files and `DemoApp/HomeListingAestheticModel.swift` is the full integration example.

```swift
ShotCoach(
    category: SCBuiltInCategory.homeListing.extending {
        $0.addRule(SCAestheticRule(model: try HomeListingAestheticModel()))
    },
    apiKey: key
)
```
```

- [ ] **Step 2: Fill in the Installation section**

Replace the empty `## Installation` heading with:

```markdown
## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/giorgia/ShotCoachSDK", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "ShotCoachCore", package: "ShotCoachSDK"),  // headless engine
        .product(name: "ShotCoachUI",   package: "ShotCoachSDK"),  // SwiftUI layer (optional)
    ]),
]
```

Or in Xcode: **File → Add Package Dependencies** and enter `https://github.com/giorgia/ShotCoachSDK`.
```

- [ ] **Step 3: Fill in the Requirements section**

Replace the empty `## Requirements` heading with:

```markdown
## Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+
- OpenAI API key (stored in Keychain, never logged or embedded in URLs)
```

- [ ] **Step 4: Fill in the License section**

Replace the empty `## License` heading with:

```markdown
## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 5: Read the full README from top to bottom and verify**

Check:
- No `CameraGuidanceView` (must be `SCCameraGuidanceView`)
- No Claude/Anthropic API mention
- No marketing phrases ("drop it in", "That's it", "5 lines")
- All code examples are syntactically valid Swift
- No broken section headings or orphaned content from the old README

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: complete README redesign — architecture-led, dual-purpose"
```

- [ ] **Step 7: Push and tag**

```bash
git push
git tag v1.0.4
git push origin v1.0.4
```
