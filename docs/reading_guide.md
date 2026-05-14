# Snapuary Reading Guide

## Goal

This document is a practical map for reading the codebase without getting lost in the large SwiftUI files.

## Fast path

If you only have 15 to 20 minutes, read these files first:

1. [LibraryHomeViewModel.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Features/Library/LibraryHomeViewModel.swift)
2. [LibraryHomeView.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Features/Library/LibraryHomeView.swift)
3. [PhotoLibraryServing.swift](/Users/chenzihan/ios-app-dev/Snapuary/App/Core/Services/PhotoLibraryServing.swift)

That gives you:

- the app’s main state
- the major screens
- the real photo-library data source

## How to read `LibraryHomeViewModel`

Read it in this order.

### 1. Inputs and owned state

Look at the stored properties near the top:

- `assets`
- `cleanupScopedAssets`
- `orbitCollections`
- `orbitHistory`
- `pendingDeletionAssets`
- authorization and loading flags

These tell you what the entire UI is derived from.

### 2. Public loading APIs

Then read:

- `loadForBrowsing()`
- `load()`
- `loadMoreIfNeeded(...)`
- `prepareCleanupData()`
- `handleAppDidBecomeActive()`

These explain when the app performs a lightweight browse load versus a full load.

### 3. Derived collections

Then read the computed properties:

- `availableTags`
- `tagLibrary`
- `visibleAssets`
- `cleanupReviewQueue`
- `weeklyOrbitRecap`

These show how the raw asset array is transformed into what the UI actually renders.

### 4. Mutation APIs

Then read the write actions:

- tag APIs
- cleanup APIs
- Orbit APIs
- retention/protection APIs

These are the main places where user actions turn into persistent changes.

### 5. Private persistence helpers

Finally read:

- `persistMetadata(...)`
- `persistSnapshot()`
- `refreshTagSources()`
- `persistOrbitLibrary()`
- `refreshForExternalLibraryChange(...)`

These explain why changes survive relaunches and how the app avoids unnecessary reloads.

## How to read `LibraryHomeView`

This file is big. Do not read it top to bottom in one pass.

Instead, read by tab.

### `LibraryHomeView`

Focus on:

- `LibraryHeader`
- `LibraryFilterStrip`
- `LibraryGrid`

This is the browse flow.

### `TagHomeView`

Focus on:

- `TagFolderRow`
- `TagDetailView`

This is the tag-management flow.

### `OrbitHomeView`

Focus on:

- `OrbitReviewView`
- `OrbitReviewCard`
- `OrbitRailView`
- `OrbitRecipeStrip`

This is the Orbit sort-and-assign flow.

### `CleanupHomeView`

Focus on:

- `CleanupReviewView`
- `CleanupReviewCard`
- `PendingDeletionBar`

This is the keep/delete review flow.

## How to read photo loading

To understand library loading, follow this path:

1. `LibraryHomeViewModel.load(...)`
2. `photoLibraryService.libraryFingerprint()`
3. `PhotoLibraryAssetSource.refreshSnapshot(...)`
4. `LibraryHomeViewModel.loadNextPage(...)`
5. `MetadataMergingPhotoLibraryService.fetchAssetPage(...)`

This shows the full sequence from cache check to paged load to metadata merge.

## How to read Orbit

Follow this path:

1. `OrbitHomeView`
2. `OrbitReviewView`
3. `OrbitReviewCard`
4. `LibraryHomeViewModel.assignAsset(...)`
5. `persistMetadata(...)`
6. `persistOrbitLibrary()`

That tells you:

- where the gesture starts
- where the asset gets assigned
- where the state is persisted

## How to read Cleanup

Follow this path:

1. `CleanupHomeView`
2. `CleanupReviewView`
3. `CleanupReviewCard`
4. `stageAssetForDeletion(...)`
5. `commitPendingDeletions()`

That shows the difference between:

- staging a delete
- actually asking PhotoKit to delete

## How to read tags

Start here:

1. `tagLibrary`
2. `TagHomeView`
3. `AssetEditorSheet`
4. `addTag(...)`
5. `addTags(...)`
6. `renameTag(...)`
7. `mergeTag(...)`

Important concept:

- tags exist both on assets and in the reusable saved tag catalog

## How to read caching

There are two different caches:

### Asset snapshot cache

Handled by the asset index cache.

Purpose:

- relaunch faster
- reuse library state if the PhotoKit fingerprint did not change

### Thumbnail cache

Handled by `PhotoLibraryThumbnailStore`.

Purpose:

- reuse thumbnails between cells
- avoid repeating `PHAsset` lookups
- preheat thumbnails during grid scroll

## When a photo changes outside the app

Read:

- `PhotoLibraryChangeObserverProxy`
- `handleObservedPhotoLibraryChange()`
- `refreshForExternalLibraryChange(...)`

This is the path that keeps Snapuary in sync with changes made in the system Photos app.

## If you want to add a feature

Use this shortcut:

- new visual screen or card:
  start in `LibraryHomeView.swift`
- new state or new user action:
  start in `LibraryHomeViewModel.swift`
- new photo-loading behavior:
  start in `PhotoLibraryServing.swift`
- new image performance work:
  start in `PhotoLibraryThumbnailStore.swift` and `AssetCollectionGridView.swift`
- new persistence behavior:
  start in the service injected into `LibraryHomeViewModel`

## Common traps

- `LibraryHomeView.swift` contains several screens, not just one.
- `cleanupReviewQueue` is not the raw asset list; it is filtered and mode-dependent.
- `Orbit` and `Cleanup` now have separate flows even though they still share the same view model.
- PhotoKit state and app metadata are separate layers.
- The view model is `@MainActor`; keep state mutation there.
