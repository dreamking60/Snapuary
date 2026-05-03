# Snapuary

Snapuary is an iOS app focused on screenshot lifecycle control and privacy protection.

## Product direction

### 1. Screenshot library governance
- Classify images into screenshots and non-screenshots, with `PhotoKit` system screenshot detection as the primary rule.
- Set flexible expiration rules for screenshots.
- Auto-clean screenshots that are no longer needed.
- Keep selected screenshots in a protected collection so they never auto-clean.
- Organize screenshots and other images with custom tags, search, and smart groupings.

### 2. Watermark privacy inspection
- Analyze screenshots for visible watermarks.
- Flag screenshots with privacy risk before they are shared or exported.
- Support future expansion for on-device OCR and watermark heuristics.

## Tech choice

This repository is prepared for **native iOS development with Swift and SwiftUI**.

Why:
- Xcode, signing, simulator, Instruments, and device debugging require macOS.
- Windows can still be used for editing docs or code, but the main app workflow should stay on Mac.
- Flutter is not necessary here because your product needs deep integration with Photos permissions, background tasks, and on-device image analysis.

## Project setup

This repo uses `XcodeGen` so the project file can be regenerated instead of manually maintained.

### On Mac

1. Install Xcode from the App Store.
2. Install XcodeGen:

```bash
brew install xcodegen
```

3. Generate the Xcode project:

```bash
./scripts/bootstrap_ios.sh
```

4. Open `Snapuary.xcodeproj` in Xcode.

## Current library implementation

- Reads photo assets through `PhotoKit`
- Classifies system screenshots using `PHAsset.mediaSubtypes.contains(.photoScreenshot)`
- Treats all other images as non-screenshot photos by default
- Persists local overrides for protected screenshots, tags, manual screenshot-like classification, and retention rules
- Schedules the next cleanup reminder through local notifications

## Current structure

```text
App/
  Core/
  Features/
  Resources/
  SnapuaryApp/
Tests/
docs/
scripts/
project.yml
```

## Near-term implementation plan

1. Add `PhotoKit` integration and a local persistence layer.
2. Implement screenshot detection with `photoScreenshot` and manual screenshot-like exceptions.
3. Implement screenshot retention presets, custom durations, and protected collections.
4. Build watermark detection pipeline with Vision/OCR-based heuristics.
5. Add unit tests and snapshot/UI tests.
