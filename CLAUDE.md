# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build          # Build all targets
swift test           # Run tests (macOS only, no simulator needed)
```

ShotCoachCore has no UI dependencies — all tests run on macOS with `swift test` without launching Xcode or a simulator.

## Package Structure

Three SPM targets:

- **ShotCoachCore** — headless engine, zero UI imports, testable on Mac with XCTest
- **ShotCoachUI** — optional SwiftUI overlay layer, depends on ShotCoachCore
- **ShotCoachDemo** — App Store reference app showing all 4 built-in categories

```
Sources/
├── ShotCoachCore/
│   ├── Protocols/    ← SCFrameRule, SCCategoryConfig, SCCloudProvider, SCAnalysisDelegate
│   ├── Models/       ← SCFrame, SCFrameResult, SCCloudResult, SCPhoto, SCSessionSummary
│   ├── Rules/        ← SCBrightnessRule, SCHorizonRule, SCBlurRule, SCClutterRule, SCDistanceRule, SCReflectionRule
│   ├── Engine/       ← SCFrameAnalyzer, SCCameraSession
│   ├── Cloud/        ← SCOpenAIProvider, SCCloudError, SCKeychainService
│   └── BuiltIn/      ← SCBuiltInCategory, SCBuiltInPrompts, SCCategoryOverride
├── ShotCoachUI/
│   ├── Theme/        ← SCTheme, SCThemePresets, SCThemeEnvironmentKey
│   ├── Overlay/      ← FeedbackPill, FeedbackStack, ReadyIndicator, BoundingBoxOverlay
│   └── Views/        ← SCCameraGuidanceView, SCResultsView, SCShotChecklistView
└── ShotCoachDemo/
Tests/
└── ShotCoachCoreTests/
    ├── RuleTests/
    ├── AnalyzerTests/
    └── BuiltInTests/
```

## Architecture

**Hybrid analysis pipeline:**
- Live frame feedback: on-device via Vision.framework, free, <80ms per rule
- Post-capture deep analysis: cloud via GPT-4o, fires only after shutter tap

`SCFrameAnalyzer` runs all `SCFrameRule` instances concurrently and throttles analysis to 1500ms intervals via an actor-isolated timestamp.

Developers integrate via one of three patterns:
- **Pattern A** — `ShotCoach(category: .homeListing, apiKey: key)` (zero config)
- **Pattern B** — extend a built-in via `.extending { $0.appendPrompt("...") }`
- **Pattern C** — fully custom `SCCategoryConfig` struct

## ShotCoachCore Rules (Iron Rules)

- **NEVER import SwiftUI, UIKit, or AppKit** in ShotCoachCore. Ever.
- All public types must be `Codable` + `Sendable`
- All delegate callbacks dispatch on `@MainActor`
- API keys stored in Keychain only — never logged, printed, or embedded in URLs
- Each `SCFrameRule` must complete in under **80ms**
- New protocol requirements must always include a default implementation (no default = major version bump)
- All new `SCFrameRule` implementations must include an XCTest with a synthetic `CVPixelBuffer`

## Naming Conventions

- `SC` prefix on all public types: `SCFrame`, `SCFrameRule`, `SCCloudResult`, etc.
- Protocols: `SCFrameRule`, `SCCategoryConfig`, `SCCloudProvider`, `SCAnalysisDelegate`
- Models: `SCFrame`, `SCFrameResult`, `SCCloudResult`, `SCPhoto`, `SCSessionSummary`
- Built-in categories enum: `SCBuiltInCategory.homeListing`, `.carListing`, `.productPhoto`, `.foodPhoto`
- Prompt override: `SCBuiltInCategory.homeListing.extending { $0.appendPrompt("...") }`

## Commit Style

Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: add SCDepthRule using ARKit depth data
fix: SCBrightnessRule false positive on HDR buffers
perf: reduce SCFrameAnalyzer allocation in hot path
```

## Related Repo

**ListingApp** lives at `../ListingApp` (sibling directory). During development it references this SDK via local path:
```swift
.package(path: "../ShotCoachSDK")
```

## Do Not

- Do NOT let Claude modify `.pbxproj` files — add new files to Xcode manually
- Do NOT delete DerivedData to fix build errors — it breaks Xcode package resolution
- Do NOT add a required protocol method without a default implementation

## Current Phase

```
Week:           1
Phase:          Scaffolding
Last completed: Task 06 — SCBuiltInCategory (4 cases, SCCategoryConfig conformance), SCBuiltInPrompts (shot-specific GPT-4o templates), SCCategoryOverride (.extending builder, manual Codable, addRule) + 21 BuiltInTests — swift test 50/50 (0.53s)
Next task:      Week 1 / Task 07
Branch:         (none — on main)
Last tag:       (none)
```
