    # API Stability Audit + v1.0.0 Tag Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit every public symbol in ShotCoachCore, mark semi-stable symbols with `@_spi(ShotCoachInternal)`, update `API_STABILITY.md` and `CHANGELOG.md` to reflect the v1.0.0 surface, then tag and push.

**Architecture:** Documentation-first audit. `@_spi` applied in source; docs updated to reflect real symbols. No behaviour changes — pure API surface work.

**Tech Stack:** Swift 5.9, SPM, `@_spi` attribute, semantic versioning.

---

## Chunk 1: Mark semi-stable symbols with @_spi

Three symbols are likely to evolve — they exist for one use-case (home listing aesthetics) and the pattern will change as more models ship:

- `SCAestheticModelProvider` — novel protocol, only 1 model available today
- `SCAestheticRule` — depends on user-supplied model, API shape likely to grow
- `SCShotClassifierRule` — internal engine plumbing; most SDK users never touch it directly

### Task 1: Mark `SCAestheticModelProvider` as @_spi

**Files:**
- Modify: `Sources/ShotCoachCore/Protocols/SCAestheticModelProvider.swift`

- [ ] **Step 1: Add @_spi attribute**

Replace the file contents with:

```swift
import CoreVideo

/// Conforming types wrap a CoreML aesthetic model and produce a score in [0, 100].
/// The SDK ships no model — conformances live in the app target alongside the
/// `.mlpackage` resource.
///
/// - Note: Marked `@_spi(ShotCoachInternal)` — semi-stable. The aesthetic model
///   API will evolve as additional verticals ship. Import with:
///   `@_spi(ShotCoachInternal) import ShotCoachCore`
@_spi(ShotCoachInternal)
public protocol SCAestheticModelProvider: Sendable {
    func score(_ pixelBuffer: CVPixelBuffer) async throws -> Double
}
```

- [ ] **Step 2: Verify build still passes**

```bash
swift build
```
Expected: `Build complete!`

---

### Task 2: Mark `SCAestheticRule` as @_spi

**Files:**
- Modify: `Sources/ShotCoachCore/Rules/SCAestheticRule.swift`

- [ ] **Step 1: Add @_spi to the class declaration**

Change the actor declaration line from:
```swift
public actor SCAestheticRule: SCFrameRule {
```
to:
```swift
@_spi(ShotCoachInternal)
public actor SCAestheticRule: SCFrameRule {
```

- [ ] **Step 2: Verify build still passes**

```bash
swift build
```
Expected: `Build complete!`

---

### Task 3: Mark `SCShotClassifierRule` as @_spi

**Files:**
- Modify: `Sources/ShotCoachCore/Rules/SCShotClassifierRule.swift`

- [ ] **Step 1: Read the file to find the struct declaration**

- [ ] **Step 2: Add @_spi to the struct declaration**

Add `@_spi(ShotCoachInternal)` on the line immediately before `public struct SCShotClassifierRule`.

- [ ] **Step 3: Verify build and tests pass**

```bash
swift build && swift test --no-parallel
```
Expected: `Build complete!` and all 99 tests pass (classifier tests will still compile since they're in the same package).

- [ ] **Step 4: Commit**

```bash
git add Sources/ShotCoachCore/Protocols/SCAestheticModelProvider.swift \
        Sources/ShotCoachCore/Rules/SCAestheticRule.swift \
        Sources/ShotCoachCore/Rules/SCShotClassifierRule.swift
git commit -m "chore: mark semi-stable symbols @_spi(ShotCoachInternal) for v1.0.0"
```

---

## Chunk 2: Update API_STABILITY.md

The existing file has several inaccuracies and is missing symbols added since it was first drafted. Fix it completely.

### Task 4: Rewrite API_STABILITY.md

**Files:**
- Modify: `API_STABILITY.md`

- [ ] **Step 1: Replace the file with the corrected version**

```markdown
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
```

- [ ] **Step 2: Verify build passes (doc changes only)**

```bash
swift build
```

- [ ] **Step 3: Commit**

```bash
git add API_STABILITY.md
git commit -m "docs: rewrite API_STABILITY.md for v1.0.0 — full symbol inventory"
```

---

## Chunk 3: Write CHANGELOG.md v1.0.0 entry

### Task 5: Fill in the v1.0.0 CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Replace `[Unreleased]` section and `[0.1.0-dev]` entry**

Replace the entire file with:

```markdown
# Changelog

All notable changes to ShotCoach will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
ShotCoach follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-03-13

First stable release. All symbols listed in `API_STABILITY.md` are now under
semver commitment.

### Added

**Protocols**
- `SCFrameRule` — on-device rule protocol; all requirements have defaults
- `SCCategoryConfig` — category config protocol; all requirements have defaults
- `SCCloudProvider` — cloud analysis protocol; default throws `.notConfigured`
- `SCAnalysisDelegate` — `@MainActor` delegate for live + post-capture callbacks

**Core Models**
- `SCFrame` — pixel buffer + timestamp container (`Codable`, `Sendable`)
- `SCFrameResult` — per-frame rule results, guidance, shot detection
- `SCRuleResult` — individual rule outcome with numeric score
- `SCCloudResult` — cloud analysis result (score 0–100, issues, recommendations)
- `SCPhoto` — captured photo with optional frame + cloud results
- `SCSessionSummary` — multi-shot session aggregate
- `SCShotType` — named shot with Vision classification hints
- `SCRuleSeverity` — `.info`, `.warning`, `.critical`
- `SCImpactLevel` — `.low`, `.medium`, `.high`
- `SCIssue` — structured cloud issue (title, detail, impact)
- `SCRecommendation` — structured cloud recommendation (text, priority)
- `SCFlashMode` — `.off`, `.auto`, `.on` with SF Symbol names
- `SCLensMode` — `.main`, `.ultraWide`
- `SCCloudError` — typed cloud errors with `LocalizedError` descriptions

**Built-in Categories**
- `SCBuiltInCategory` — `.homeListing`, `.carListing`, `.productPhoto`, `.foodPhoto`
- `SCCategoryOverride` — category extension via `.extending(_:)`

**On-Device Rules** (Vision.framework, <80ms each)
- `SCBrightnessRule` — luminance range check
- `SCHorizonRule` — tilt detection via edge analysis
- `SCBlurRule` — sharpness via Laplacian variance
- `SCDistanceRule` — subject coverage via saliency
- `SCReflectionRule` — photographer-in-frame detection via face detection
- `SCInstagrammabilityRule` — compositional quality score (replaces `SCClutterRule`)

**Engine**
- `SCFrameAnalyzer` — concurrent rule runner, actor-isolated, 1.5s throttle
- `SCCameraSession` — AVFoundation session with zoom, flash, focus, lens switching

**Cloud Providers**
- `SCOpenAIProvider` — GPT-4o integration with retry and Keychain key storage
- `SCAnthropicProvider` — Claude integration (default: `claude-sonnet-4-6`)
- `SCKeychainService` — API key storage (save, load, delete)

**MLModels (bundled)**
- `MLModels/home_head_s0.mlpackage` — aesthetic scorer for home listing photos
- `MLModels/mobileclip_s0_image.mlpackage` — MobileClip S0 CLIP encoder

### Deprecated

- `SCClutterRule` — use `SCInstagrammabilityRule` instead

### Semi-Stable (not under semver — see API_STABILITY.md)

- `SCAestheticModelProvider` — CoreML aesthetic model protocol (`@_spi(ShotCoachInternal)`)
- `SCAestheticRule` — EMA-smoothed CoreML + Vision blended scorer (`@_spi(ShotCoachInternal)`)
- `SCShotClassifierRule` — Vision scene classifier for shot type detection (`@_spi(ShotCoachInternal)`)

---

## [0.1.0-dev] — 2026-01-01

Initial development build. Not suitable for production use.

### Added
- SPM package scaffold (ShotCoachCore, ShotCoachUI, ShotCoachDemo targets)
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: write CHANGELOG.md v1.0.0 entry"
```

---

## Chunk 4: Verify, tag, push

### Task 6: Full verification and tag

- [ ] **Step 1: swift package resolve**

```bash
swift package resolve
```
Expected: resolves cleanly, no errors.

- [ ] **Step 2: swift build**

```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: swift test**

```bash
swift test --no-parallel
```
Expected: 99 tests pass, 0 failures.

- [ ] **Step 4: Create and push v1.0.0 tag**

```bash
git tag -a v1.0.0 -m "ShotCoachCore v1.0.0 — first stable release"
git push origin v1.0.0
```

- [ ] **Step 5: Push branch and open PR**

```bash
git push
```
Then open a PR targeting `main` with title `chore: API stability audit + v1.0.0 tag`.
