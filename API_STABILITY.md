# API Stability

ShotCoach follows [Semantic Versioning](https://semver.org). This document
defines exactly what is and isn't covered by that commitment.

---

## Stable Public API (from v1.0.0)

Breaking changes to any symbol below require a **major version bump** (v2.0.0).

### Protocols

| Symbol | Stable members |
|---|---|
| `SCFrameRule` | `ruleID`, `evaluate(_:)`, `feedbackMessage`, `severity` — all have defaults |
| `SCCategoryConfig` | `categoryID`, `displayName`, `requiredShots`, `onDeviceRules`, `cloudPrompt(for:)` — all have defaults |
| `SCCloudProvider` | `analyze(photo:prompt:) async throws -> SCCloudResult` — default throws `.notConfigured` |
| `SCAnalysisDelegate` | `analyzer(_:didUpdate:)`, `analyzer(_:didComplete:cloudResult:)` — both have no-op defaults |

### Core Models

| Symbol | Stable members |
|---|---|
| `SCFrame` | `pixelBuffer`, `timestamp` |
| `SCFrameResult` | `rules`, `overallGuidance`, `isReadyToCapture`, `processingMs`, `detectedShotType`, `topSceneLabel` |
| `SCRuleResult` | `passed`, `message`, `severity`, `numericScore`, `detectedShotTypeID` |
| `SCCloudResult` | `score`, `issues`, `shotType`, `recommendations`, `rawJSON` |
| `SCPhoto` | `imageData`, `frameResult`, `cloudResult` |
| `SCSessionSummary` | `photos`, `averageScore`, `completedShots` |
| `SCShotType` | `id`, `displayName`, `classificationHints` |
| `SCRuleSeverity` | `.info`, `.warning`, `.critical` |
| `SCImpactLevel` | `.low`, `.medium`, `.high` |
| `SCIssue` | `title`, `detail`, `impact` |
| `SCRecommendation` | `text`, `priority` |
| `SCFlashMode` | `.off`, `.auto`, `.on`, `symbolName` |
| `SCLensMode` | `.main`, `.ultraWide` |
| `SCCloudError` | All cases + `LocalizedError.errorDescription` |

### Built-in Categories

| Symbol | Stable members |
|---|---|
| `SCBuiltInCategory` | `.homeListing`, `.carListing`, `.productPhoto`, `.foodPhoto`, `.extending(_:)` |
| `SCCategoryOverride` | `appendPrompt(_:)`, `addRequiredShot(_:)`, `addRule(_:)` |

### Rules (on-device)

| Symbol | Notes |
|---|---|
| `SCBrightnessRule` | `init(minLuminance:maxLuminance:)` |
| `SCHorizonRule` | `init(maxTiltDegrees:)` |
| `SCBlurRule` | `init(minSharpnessScore:)` |
| `SCDistanceRule` | `init(minCoverage:maxCoverage:)` |
| `SCReflectionRule` | `init(allowedFaceCount:)` |
| `SCInstagrammabilityRule` | `init(passingThreshold:)` |
| `SCClutterRule` | **Deprecated** — use `SCInstagrammabilityRule` |

### Engine

| Symbol | Stable members |
|---|---|
| `SCFrameAnalyzer` | `init(rules:)`, `init(category:)`, `setDelegate(_:)`, `analyze(_:)`, `lastFrameResult()` |
| `SCCameraSession` | `init(category:cloudProvider:)`, `start()`, `stop()`, `capturePhoto()`, `switchLens(_:completion:)`, `setZoom(_:)`, `setFocusPoint(_:)`, `flashMode`, `maxZoomFactor`, `isUltraWideAvailable`, `nativeSession` |

### Cloud Providers

| Symbol | Stable members |
|---|---|
| `SCOpenAIProvider` | `init(apiKey:)` |
| `SCAnthropicProvider` | `init(apiKey:model:)` |
| `SCKeychainService` | `save(key:value:)`, `load(key:)`, `delete(key:)` |

---

## Semi-Stable (marked `@_spi(ShotCoachInternal)`)

These symbols are accessible but **not** covered by semver. They may change in
minor versions. To use them, import with:

```swift
@_spi(ShotCoachInternal) import ShotCoachCore
```

| Symbol | Why semi-stable |
|---|---|
| `SCAestheticModelProvider` | Novel API — shape will evolve as more verticals ship |
| `SCAestheticRule` | Depends on `SCAestheticModelProvider`; will gain per-category defaults |
| `SCShotClassifierRule` | Internal engine plumbing; most integrators never use directly |

---

## Unstable / Experimental

Not covered by semver — may change in any release:

- `ShotCoachDemo` app source (reference implementation only)
- Built-in GPT-4o / Claude prompt text (may improve in patch releases)
- Internal Vision request configuration
- `SCFrameAnalyzer` throttling interval

---

## Adding Protocol Requirements (Minor Versions)

When adding a new method to a stable protocol in a minor release, ShotCoach
**must** provide a default implementation so existing adopters don't break:

```swift
// Safe — has default
public protocol SCCategoryConfig {
    func scoringWeights() -> SCWeights  // new in v1.1
}
public extension SCCategoryConfig {
    func scoringWeights() -> SCWeights { .default }  // protects adopters
}
```

If a meaningful default isn't possible → major version bump.

---

## Versioning Policy

| Change | Version bump |
|---|---|
| New public API, backwards compatible | Minor (1.x.0) |
| Bug fix, no API change | Patch (1.0.x) |
| Improved built-in prompts | Patch (1.0.x) |
| Removing or renaming a stable symbol | Major (2.0.0) |
| Breaking protocol requirement | Major (2.0.0) |
| New required protocol method (no default) | Major (2.0.0) |
