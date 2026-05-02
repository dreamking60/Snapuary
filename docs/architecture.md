# Architecture notes

## App shape

The app is intentionally split into two product areas:

1. `Library`
   - screenshot expiration
   - favorites/protected tags
   - image tagging and grouping
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

## Suggested next slices

1. Build `PhotoLibraryClient` against PhotoKit.
2. Persist local metadata for tags, retention policy, and exceptions.
3. Add background cleanup scheduling.
4. Prototype watermark detection with OCR bounding boxes and keyword rules.

