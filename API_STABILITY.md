# API Stability

ShotCoach follows [Semantic Versioning](https://semver.org). This document defines exactly what is and isn't covered by that commitment.

---

## Stable Public API (from v1.0.0)

Breaking changes to these symbols require a **major version bump** (v2.0.0):

### Protocols
| Symbol | Notes |
|---|---|
| `SCFrameRule` | `ruleID`, `evaluate(_:)`, `feedbackMessage`, `severity` |
| `SCCategoryConfig` | `categoryID`, `displayName`, `requiredShots`, `onDeviceRules`, `cloudPrompt(for:)` |
| `SCCloudProvider` | `analyze(image:prompt:)` |
| `SCAnalysisDelegate` | All four delegate methods |

### Core Models
| Symbol | Notes |
|---|---|
| `SCFrame` | `pixelBuffer`, `timestamp` |
| `SCFrameResult` | `rules`, `overallGuidance`, `isReadyToCapture`, `processingMs` |
| `SCRuleResult` | `passed`, `message`, `severity` |
| `SCCloudResult` | `score`, `issues`, `shotType`, `recommendations` |
| `SCPhoto` | `imageData`, `frameResult`, `cloudResult` |
| `SCSessionSummary` | `photos`, `averageScore`, `completedShots` |
| `SCShotType` | `id`, `displayName` |
| `SCRuleSeverity` | All cases |

### Entry Point
| Symbol | Notes |
|---|---|
| `ShotCoach` | `init(category:apiKey:)`, `startSession()`, `stopSession()`, `capturePhoto()` |
| `SCBuiltInCategory` | All four cases + `.extending()` modifier |

### UI (ShotCoachUI)
| Symbol | Notes |
|---|---|
| `SCCameraGuidanceView` | `init(sdk:)`, `.theme()`, `.onResult()`, `.onSessionEnd()` |
| `SCResultsView` | `init(photo:)` |
| `SCShotChecklistView` | `init(sdk:mode:)` |
| `SCTheme` | All properties and presets |

---

## Semi-Stable (marked `@_spi(ShotCoachInternal)`)

These are accessible but not covered by semver. They may change in minor versions:

- Internal rule scoring algorithms
- GPT-4o prompt templates (improve via patch releases)
- Animation timing constants in ShotCoachUI
- `SCFrameAnalyzer` internal throttling implementation

---

## Unstable / Experimental

Not covered by semver — may change in any release:

- `ShotCoachDemo` app source code (reference only)
- Any symbol marked `@_spi`
- Anything in `Internal/` folders

---

## Adding Protocol Requirements (Minor Versions)

When adding a new method to a stable protocol in a minor release, ShotCoach **must** provide a default implementation so existing adopters don't break:

```swift
// Safe — has default
public protocol SCCategoryConfig {
    func scoringWeights() -> SCWeights  // new in v1.1
}
public extension SCCategoryConfig {
    func scoringWeights() -> SCWeights { .default }  // default protects adopters
}
```

If a meaningful default isn't possible, it's a major version bump.

---

## Versioning Policy

| Change | Version bump |
|---|---|
| New public API, backwards compatible | Minor (1.1.0) |
| Bug fix, no API change | Patch (1.0.1) |
| Improved built-in prompts | Patch (1.0.x) |
| Removing or renaming stable symbol | Major (2.0.0) |
| Breaking protocol requirement change | Major (2.0.0) |
| New required protocol method (no default) | Major (2.0.0) |
