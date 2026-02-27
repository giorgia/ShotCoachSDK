# Contributing to ShotCoach

Thanks for your interest in contributing. Here's everything you need to know.

---

## What We're Looking For

### High priority
- New `SCCategoryConfig` implementations for underserved verticals (fashion, jewelry, real estate exterior, motorcycles, boats)
- Improvements to built-in GPT-4o prompts (open a PR with before/after examples)
- New `SCFrameRule` implementations using Vision.framework
- Additional `SCCloudProvider` implementations (Claude, Gemini, etc.)
- DocC documentation improvements

### Not currently accepting
- New UI themes (too subjective — use `.theme()` customization instead)
- Changes to the public API contract without prior discussion in an issue
- New SPM targets

---

## Development Setup

```bash
git clone https://github.com/you/ShotCoach
cd ShotCoach

# Build
swift build

# Test (runs on macOS, no simulator needed)
swift test

# ShotCoachCore has zero UI deps — all tests run without Xcode
```

---

## Rules for Pull Requests

### Code
- `ShotCoachCore` must never import `SwiftUI`, `UIKit`, or `AppKit`
- All new public types must be `Codable` and `Sendable`
- New `SCFrameRule` implementations must include an XCTest with a synthetic CVPixelBuffer
- New protocol requirements must have a default implementation
- All public symbols require DocC documentation comments

### Commits
Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: add SCDepthRule using ARKit depth data
fix: SCBrightnessRule false positive on HDR buffers
docs: improve SCCategoryConfig protocol documentation
perf: reduce SCFrameAnalyzer allocation in hot path
```

### Tests
- `swift test` must pass with zero failures before opening a PR
- New `SCFrameRule`: include unit test + performance assertion (<80ms)
- New `SCCategoryConfig`: include test asserting non-empty `requiredShots` and `onDeviceRules`

---

## Adding a New Built-in Category

1. Create `Sources/ShotCoachCore/BuiltIn/SC[Name]Config.swift`
2. Conform to `SCCategoryConfig`
3. Add a case to `SCBuiltInCategory` enum
4. Write a GPT-4o prompt in `cloudPrompt(for:)` — be specific about the JSON response format
5. Add unit tests in `Tests/ShotCoachCoreTests/BuiltInTests/`
6. Add a demo screen in `ShotCoachDemo`
7. Update `README.md` built-in categories table
8. Add a `CHANGELOG.md` entry

---

## Community Categories (ShotCoachKit)

For more niche categories that don't belong in the core SDK, consider contributing to [ShotCoachKit](https://github.com/you/ShotCoachKit) — a separate community package with PR-driven additions.

---

## Questions

Open an issue. We'll respond within a few days.
