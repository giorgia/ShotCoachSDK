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
