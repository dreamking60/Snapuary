# Snapuary Codebase Overview

## What the app does

Snapuary is a photo-library organizer built around four main flows:

- `Library`: browse the library, search, filter, and open an asset editor.
- `Tags`: treat tags like lightweight folders and manage them across the whole library.
- `Orbit`: review photos and drag them into named Orbit collections.
- `Cleanup`: review screenshot-like assets and batch-delete or keep them.

The app is intentionally split between:

- a thin UI layer in SwiftUI
- one main state coordinator
- small service objects for PhotoKit, metadata, caching, reminders, and persistence

## Best entry points

If you want to understand the code quickly, start here in order:

1. [App/Features/Library/LibraryHomeViewModel.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Features/Library/LibraryHomeViewModel.swift)
2. [App/Features/Library/LibraryHomeView.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Features/Library/LibraryHomeView.swift)
3. [App/Core/Services/PhotoLibraryServing.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Core/Services/PhotoLibraryServing.swift)
4. [App/Core/Services/PhotoLibraryThumbnailStore.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Core/Services/PhotoLibraryThumbnailStore.swift)
5. [App/Features/Library/AssetCollectionGridView.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Features/Library/AssetCollectionGridView.swift)

## Core architecture

### `LibraryHomeViewModel`

This is the main orchestrator. It owns:

- loaded `assets`
- cleanup queues and deletion staging
- tag catalog state
- Orbit collections and Orbit history
- paging progress
- snapshot reuse and cache hydration
- reactions to `PHPhotoLibrary` changes

Almost every screen in the app reads from or writes through this view model.

### `LibraryHomeView`

This file contains most of the app’s main screens:

- `LibraryHomeView`
- `TagHomeView`
- `OrbitHomeView`
- `CleanupHomeView`

It also contains many supporting subviews used by those tabs, such as review cards, recap cards, rail views, and editor helpers.

### Photo library services

`PhotoLibraryServing.swift` defines the photo library abstraction.

Important layers:

- `PhotoKitPhotoLibraryService`
  talks directly to `PHPhotoLibrary` and `PHAsset`
- `MetadataMergingPhotoLibraryService`
  overlays app-owned metadata such as tags, orbit IDs, protection flags, and retention rules
- `PhotoLibraryAssetSource`
  keeps a serial PhotoKit snapshot so the app can page reliably

### Thumbnail store

`PhotoLibraryThumbnailStore` wraps `PHCachingImageManager` and handles:

- thumbnail requests
- preview requests
- preheating
- local `PHAsset` reuse

This keeps the grid and preview surfaces from doing repeated PhotoKit lookups.

## Data flow

### Read path

1. The UI asks `LibraryHomeViewModel` to load.
2. The view model first tries `MediaAssetIndexCache`.
3. If cache is usable, it hydrates from disk immediately.
4. The view model checks a `PhotoLibraryFingerprint`.
5. If the fingerprint changed, it reloads from PhotoKit page by page.
6. Each page is merged with locally saved metadata.
7. The UI updates from the main actor.

### Write path

When a user:

- adds or removes a tag
- protects an asset
- changes retention rules
- assigns an Orbit
- deletes an asset

the view model updates local memory first, then persists metadata or library snapshots through service objects.

## Caching and persistence

The app uses several different persisted stores:

- `MediaAssetIndexCache`
  stores the lightweight library snapshot used for fast relaunch
- metadata store
  stores tags, orbit IDs, retention rules, and protection flags by local identifier
- tag catalog store
  stores reusable tag templates
- Orbit library store
  stores named Orbit collections and Orbit history

The important distinction is:

- PhotoKit owns the real photo library
- Snapuary owns app-specific metadata layered on top of it

## Orbit vs Cleanup

These are intentionally separate now.

### Orbit

Orbit is for:

- sorting
- assigning photos into named collections
- recipe-driven review
- future smart classification

### Cleanup

Cleanup is for:

- keeping
- staging deletes
- batch deletion
- screenshot review

This split reduces UI overload and keeps the gestures focused.

## Concurrency model

The most important rule is:

- `LibraryHomeViewModel` is `@MainActor`

That means:

- SwiftUI reads happen on the main actor
- array mutation also happens on the main actor
- PhotoKit fetches can still be awaited, but state writes stay serialized

This was added specifically to avoid array mutation races during pagination.

## Tabs and startup

Current top-level tab wiring lives in:

- [App/SnapuaryApp/RootTabView.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/SnapuaryApp/RootTabView.swift)
- [App/SnapuaryApp/RootTabViewModel.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/SnapuaryApp/RootTabViewModel.swift)
- [App/SnapuaryApp/AppSettingsStore.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/SnapuaryApp/AppSettingsStore.swift)

`AppSettingsStore` controls the default launch tab and some user-facing preferences.

## Localization

Localized strings are stored under:

- `App/Resources/en.lproj`
- `App/Resources/zh-Hans.lproj`
- `App/Resources/zh-Hant.lproj`
- `App/Resources/ja.lproj`
- `App/Resources/ko.lproj`

Most UI text is routed through `L10n.text(...)`.

## System integrations

App Intents and shortcut-related routing live under:

- [App/SnapuaryApp/SnapuaryAppIntents.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/SnapuaryApp/SnapuaryAppIntents.swift)
- [App/SnapuaryApp/AppRouteStore.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/SnapuaryApp/AppRouteStore.swift)

These are the first files to inspect if you want to add:

- Shortcuts support
- deep-link style app routing
- future widgets or share flows

## Recommended reading order for feature work

If you are editing a specific feature:

- browse/grid performance:
  `LibraryHomeViewModel` -> `AssetCollectionGridView` -> `PhotoLibraryThumbnailStore`
- cleanup review:
  `LibraryHomeViewModel` -> `CleanupReviewView` -> `CleanupReviewCard`
- Orbit:
  `LibraryHomeViewModel` -> `OrbitHomeView` -> `OrbitReviewView` -> `OrbitRailView`
- tag system:
  `LibraryHomeViewModel` -> `TagHomeView` -> metadata store / tag catalog store
