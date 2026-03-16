# README Redesign Spec

**Date:** 2026-03-16
**Status:** Approved

---

## Goal

Rewrite README.md as a dual-purpose document: a portfolio piece demonstrating engineering depth for technical hiring audiences, and a practical integration reference for iOS developers.

Architecture is the centrepiece. Quick start and integration patterns are present but secondary.

---

## Structure

### 1. Header

- Title: `# ShotCoach`
- One-liner: "Real-time camera coaching for iOS. On-device Vision analysis every frame, cloud AI after the shutter."
- Badges: Swift 5.9+, iOS 16+, SPM-compatible, MIT

### 2. Architecture

Opens immediately after the header — no prose preamble.

**Contents:**
- Hybrid pipeline diagram (ASCII) showing on-device → cloud flow
- Three design decisions with rationale:
  1. **Why hybrid?** Vision.framework gives sub-80ms feedback at zero API cost. GPT-4o fires once per shot for the structured quality report on-device models can't produce.
  2. **Why actor isolation for SCFrameAnalyzer?** Rules run concurrently via `withTaskGroup`. The analyzer is an actor so the 1.5s throttle timestamp is mutation-safe across concurrent callers without a lock.
  3. **Why protocol injection for CoreML models?** `SCAestheticRule` accepts any `SCAestheticModelProvider` — the SDK ships no bundled model weights. App targets own the `.mlpackage`, so model updates don't require an SDK release.

### 3. Quick Start

Three patterns, code-only, minimal prose:

- **Pattern A** — Zero config: `ShotCoach(category:apiKey:)` + `SCCameraGuidanceView`
- **Pattern B** — Extend a built-in: `.extending { }` with `appendPrompt` and `addRequiredShot`
- **Pattern C** — Fully custom: custom `SCCategoryConfig` struct

### 4. Built-in Categories

Table: Category | Shots | Rules

| Category | Shots | Rules |
|---|---|---|
| `.homeListing` | 6 | Brightness, Horizon, Blur, Instagrammability |
| `.carListing` | 8 | Brightness, Reflection, Blur, Distance |
| `.productPhoto` | 6 | Brightness, Blur, Reflection, Horizon |
| `.foodPhoto` | 5 | Brightness, Blur, Horizon (±15°), Instagrammability |

### 5. On-Device Rules

Table: Rule | Measures | Budget

| Rule | Measures | Budget |
|---|---|---|
| `SCBrightnessRule` | Average luminance (Rec.709) | <80ms |
| `SCHorizonRule` | Horizon tilt via `VNDetectHorizonRequest` | <80ms |
| `SCBlurRule` | Laplacian variance sharpness | <80ms |
| `SCDistanceRule` | Subject bounding box area | <80ms |
| `SCReflectionRule` | Specular highlight ratio | <80ms |
| `SCInstagrammabilityRule` | Focal clarity, balance, variety, lighting | <80ms |
| `SCShotClassifierRule` | Scene type via hint-based Vision scoring | <80ms |

### 6. CoreML Aesthetic Pipeline

- ASCII diagram: `CVPixelBuffer` → `mobileclip_s0_image` (CLIP encoder) → `home_head_s0` (sigmoid head) → blended with `SCInstagrammabilityRule` heuristic → EMA smoothing → `SCRuleResult`
- Weights: CoreML 70%, Vision heuristic 30%
- EMA α = 0.3 — suppresses per-frame jitter without external state
- Protocol injection note: `SCAestheticModelProvider` is `Sendable`; reference implementation at `DemoApp/HomeListingAestheticModel.swift`

### 7. Installation

SPM snippet only:
```swift
.package(url: "https://github.com/giorgia/ShotCoachSDK", from: "1.0.0")
```
Note: import `ShotCoachCore` for headless engine, `ShotCoachUI` for SwiftUI layer.

### 8. Requirements

- iOS 16+
- Xcode 15+
- Swift 5.9+
- OpenAI API key (stored in Keychain, never logged or embedded in URLs)

### 9. License

MIT — one line.

---

## What Is Removed vs Current README

| Removed | Reason |
|---|---|
| "What It Does" marketing prose | Replaced by precise one-liner + architecture section |
| Claude/Anthropic API mention | Implementation detail, not a selling point |
| Theming section | Not core to architecture or integration; can live in docs |
| API Stability reference | Belongs in API_STABILITY.md, not README |
| Prompt System standalone section | Covered by Pattern B in Quick Start |
| Custom category prose example with wrong signature | Replaced by clean Pattern C reference |
| `CameraGuidanceView` (wrong name) | Corrected to `SCCameraGuidanceView` throughout |

---

## Tone

- No marketing language ("drop it into any app in 5 lines", "That's it")
- Technically precise — names, measurements, and decisions stated as facts
- Rationale included for non-obvious architectural choices
- Code examples are accurate and match the actual public API
