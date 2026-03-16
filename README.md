# ShotCoach

Real-time camera coaching for iOS. On-device Vision analysis every frame, cloud AI after the shutter.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue)](https://developer.apple.com/ios/)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## Architecture

ShotCoach runs a hybrid analysis pipeline — on-device for every frame, cloud only after capture.

```
SCFrame (CVPixelBuffer + metadata)
        │
        ├── SCFrameAnalyzer (actor)
        │       ├── SCBrightnessRule       ─┐
        │       ├── SCHorizonRule           │
        │       ├── SCBlurRule              ├── concurrent withTaskGroup, throttled to 1.5s
        │       ├── SCDistanceRule          │
        │       ├── SCReflectionRule        │
        │       └── SCInstagrammabilityRule ─┘
        │               │
        │               ▼
        │       SCFrameResult → SCAnalysisDelegate (@MainActor)
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

## Quick Start

## Built-in Categories

## On-Device Rules

## CoreML Aesthetic Pipeline

## Installation

## Requirements

## License
