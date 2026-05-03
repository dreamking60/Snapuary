# Architecture notes

## App shape

The app is intentionally split into two product areas:

1. `Library`
   - screenshot vs non-screenshot classification
   - screenshot expiration
   - protected screenshot collection
   - image tagging, search, and grouping
2. `WatermarkPrivacy`
   - watermark detection
   - privacy risk review
   - future export/share interception

## Technical direction

- UI: SwiftUI
- Concurrency: Swift Concurrency
- Persistence: SwiftData or Core Data after requirements stabilize
- Photos integration: PhotoKit
- On-device analysis: Vision + OCR + custom heuristics

## Current screenshot classification

- `systemScreenshot`: mapped from `PHAsset.mediaSubtypes` containing `photoScreenshot`
- `photo`: any other image asset from the photo library
- `importedScreenshotLike`: reserved for future user-defined overrides persisted locally

## Local metadata persistence

- PhotoKit remains the source of truth for raw photo assets
- Snapuary persists app-specific metadata separately by `PHAsset.localIdentifier`
- Persisted fields:
  - protected screenshot state
  - manual screenshot-like override
  - custom tags
  - screenshot retention rule override

## Cleanup reminder scheduling

- Snapuary schedules the nearest upcoming screenshot cleanup date through local notifications
- The reminder layer is separate from cleanup execution, so scheduling can evolve into background refresh later

## Suggested next slices

1. Build `PhotoLibraryClient` against PhotoKit with `photoScreenshot` classification.
2. Persist local metadata for tags, screenshot retention rules, and protected exceptions.
3. Add background cleanup scheduling for screenshot assets only.
4. Prototype watermark detection with OCR bounding boxes and keyword rules.
