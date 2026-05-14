import Photos
import SwiftUI

/// Main Library tab that combines browse filters, recap metrics, and the paged photo grid.
struct LibraryHomeView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?
    @State private var isShowingProfileSheet = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    /// Stores the shared view model inside local SwiftUI state so the tab can mutate it directly.
    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let languageRefreshKey = settings.preferredLanguage.rawValue
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                if !viewModel.authorizationStatus.canReadAssets,
                   let message = viewModel.authorizationErrorMessage {
                    LibraryAuthorizationView(
                        message: message,
                        authorizationStatus: viewModel.authorizationStatus,
                        onRequestAccess: {
                            await viewModel.requestPhotoLibraryAccessForBrowsing()
                        }
                    )
                } else {
                    VStack(spacing: 18) {
                        LibraryHeader(viewModel: viewModel)
                        if viewModel.weeklyOrbitRecap.assignedCount > 0
                            || viewModel.weeklyOrbitRecap.keptCount > 0
                            || viewModel.weeklyOrbitRecap.deletedCount > 0 {
                            OrbitRecapCard(recap: viewModel.weeklyOrbitRecap)
                        }
                        LibraryFilterStrip(viewModel: viewModel)
                        LibraryGrid(
                            assets: viewModel.visibleAssets,
                            thumbnailStore: viewModel.thumbnailStore,
                            isLoading: viewModel.isLoading,
                            isLoadingMore: viewModel.isLoadingMore,
                            loadedAssetCount: viewModel.loadedAssetCount,
                            totalAssetCount: viewModel.totalAssetCount,
                            progress: viewModel.loadProgress,
                            columns: gridColumns,
                            onApproachingEnd: { index in
                                Task {
                                    await viewModel.loadMoreIfNeeded(visibleIndex: index)
                                }
                            },
                            onSelect: { selectedAsset = $0 }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .id(languageRefreshKey)
                }
            }
            .navigationTitle(L10n.text("library.title", fallback: "Library"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: L10n.text("library.search_prompt", fallback: "Search title or tag"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingProfileSheet = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel(L10n.text("settings.title", fallback: "Profile"))
                }
            }
            .task {
                if viewModel.authorizationStatus == .notDetermined {
                    await viewModel.requestPhotoLibraryAccessForBrowsing()
                } else {
                    await viewModel.loadForBrowsing()
                }
            }
            .alert(
                viewModel.cleanupPromptTitle,
                isPresented: Binding(
                    get: { viewModel.shouldPromptForCleanup },
                    set: { newValue in
                        if !newValue {
                            viewModel.dismissCleanupPrompt()
                        }
                    }
                )
            ) {
                Button(L10n.text("common.later", fallback: "Later"), role: .cancel) {
                    viewModel.dismissCleanupPrompt()
                }
                Button(L10n.text("cleanup.clean_now", fallback: "Clean Now"), role: .destructive) {
                    Task {
                        await viewModel.runCleanupNow()
                    }
                }
            } message: {
                Text(viewModel.cleanupPromptMessage)
            }
            .sheet(isPresented: $isShowingProfileSheet) {
                AppProfileSheet(photoAuthorizationStatus: viewModel.authorizationStatus)
            }
            .sheet(item: $selectedAsset) { asset in
                AssetEditorSheet(
                    asset: asset,
                    tagLibrary: viewModel.tagLibrary,
                    tagSuggestions: { await viewModel.autoTagSuggestions(for: asset) },
                    onRefresh: {
                        await viewModel.loadForBrowsing()
                        selectedAsset = refreshedAsset(from: asset, in: viewModel.assets)
                    },
                    onToggleProtection: { await viewModel.toggleProtection(for: asset) },
                    onToggleScreenshotLike: { await viewModel.toggleImportedScreenshotLike(for: asset) },
                    onApplyRetentionRule: { rule in
                        await viewModel.applyRetentionRule(rule, to: asset)
                    },
                    onAddTag: { name, colorHex in
                        await viewModel.addTag(name: name, colorHex: colorHex, to: asset)
                    },
                    onAddTags: { entries in
                        await viewModel.addTags(entries, to: asset)
                    },
                    onRemoveTag: { tag in
                        await viewModel.removeTag(tag, from: asset)
                    }
                )
                .presentationDetents([.large])
            }
        }
    }

    /// Re-resolves a sheet asset after the library reloads so editors keep pointing at the latest value.
    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }
}

/// Orbit tab that focuses on assigning photos into named Orbit collections.
struct OrbitHomeView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?
    @State private var previewAsset: MediaAsset?
    @State private var reviewIndex = 0
    @State private var isShowingCreateOrbit = false
    @State private var draftOrbitName = ""

    /// Stores the shared view model inside local SwiftUI state for the Orbit tab.
    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let languageRefreshKey = settings.preferredLanguage.rawValue
        NavigationStack {
            Group {
                if !viewModel.authorizationStatus.canReadAssets,
                   let message = viewModel.authorizationErrorMessage {
                    LibraryAuthorizationView(
                        message: message,
                        authorizationStatus: viewModel.authorizationStatus,
                        onRequestAccess: {
                            await viewModel.requestPhotoLibraryAccessForBrowsing()
                            await viewModel.prepareCleanupData()
                        }
                    )
                } else {
                    OrbitReviewView(
                        assets: viewModel.cleanupReviewQueue,
                        thumbnailStore: viewModel.thumbnailStore,
                        currentIndex: $reviewIndex,
                        isRefreshing: viewModel.isSyncingCleanupData,
                        orbitCollections: viewModel.orbitCollections,
                        selectedOrbitID: Binding(
                            get: { viewModel.focusedOrbitID },
                            set: { viewModel.focusOrbit($0) }
                        ),
                        orbitAssetCounts: viewModel.orbitAssetCounts,
                        orbitAssets: viewModel.assets(in: viewModel.focusedOrbitID),
                        recipeCollections: viewModel.recipeCollections,
                        activeRecipe: viewModel.activeRecipe,
                        smartSuggestionsProvider: { asset in
                            viewModel.orbitSuggestions(for: asset)
                        },
                        onPreview: { asset in
                            previewAsset = asset
                        },
                        onOrbit: { asset in
                            let targetOrbitID = viewModel.focusedOrbitID
                                ?? viewModel.orbitSuggestions(for: asset).first?.orbitID
                                ?? viewModel.orbitCollections.first?.id
                            if let targetOrbitID {
                                await viewModel.assignAsset(asset, to: targetOrbitID)
                                await viewModel.protectFromCleanup(asset)
                                clampReviewIndex()
                            } else {
                                isShowingCreateOrbit = true
                            }
                        },
                        onCreateOrbit: {
                        isShowingCreateOrbit = true
                        },
                        onSelectRecipe: { orbit in
                        let shouldClear = viewModel.activeRecipe == orbit.recipe
                        viewModel.focusOrbit(orbit.id)
                        viewModel.activateRecipe(shouldClear ? nil : orbit.recipe)
                        }
                    )
                    .padding()
                    .id(languageRefreshKey)
                }
            }
                    .navigationTitle(L10n.text("tab.orbit", fallback: "Orbit"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.cleanupReviewMode != .allPhotos {
                    viewModel.cleanupReviewMode = .allPhotos
                }
                if viewModel.authorizationStatus == .notDetermined {
                    await viewModel.requestPhotoLibraryAccessForBrowsing()
                    await viewModel.prepareCleanupData()
                } else {
                    await viewModel.prepareCleanupData()
                }
                if viewModel.focusedOrbitID == nil {
                    viewModel.focusOrbit(viewModel.orbitCollections.first?.id)
                }
            }
            .onChange(of: viewModel.orbitCollections.map(\.id)) { _, ids in
                guard let first = ids.first else {
                    viewModel.focusOrbit(nil)
                    return
                }
                if viewModel.focusedOrbitID == nil || !ids.contains(viewModel.focusedOrbitID ?? "") {
                    viewModel.focusOrbit(first)
                }
            }
            .alert(L10n.text("orbit.create", fallback: "Create Orbit"), isPresented: $isShowingCreateOrbit) {
                TextField(L10n.text("orbit.new_name", fallback: "New orbit"), text: $draftOrbitName)
                Button(L10n.text("common.cancel", fallback: "Cancel"), role: .cancel) {
                    draftOrbitName = ""
                }
                Button(L10n.text("common.save", fallback: "Save")) {
                    Task {
                        let pendingName = draftOrbitName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !pendingName.isEmpty else {
                            return
                        }
                        let orbit = await viewModel.createOrbit(
                            name: pendingName,
                            colorHex: TagColorPreset.ocean.hex
                        )
                        viewModel.focusOrbit(orbit?.id)
                        draftOrbitName = ""
                    }
                }
            }
            .sheet(item: $selectedAsset) { asset in
                AssetEditorSheet(
                    asset: asset,
                    tagLibrary: viewModel.tagLibrary,
                    tagSuggestions: { await viewModel.autoTagSuggestions(for: asset) },
                    onRefresh: {
                        await viewModel.load()
                        selectedAsset = refreshedAsset(from: asset, in: viewModel.assets)
                    },
                    onToggleProtection: { await viewModel.toggleProtection(for: asset) },
                    onToggleScreenshotLike: { await viewModel.toggleImportedScreenshotLike(for: asset) },
                    onApplyRetentionRule: { rule in
                        await viewModel.applyRetentionRule(rule, to: asset)
                    },
                    onAddTag: { name, colorHex in
                        await viewModel.addTag(name: name, colorHex: colorHex, to: asset)
                    },
                    onAddTags: { entries in
                        await viewModel.addTags(entries, to: asset)
                    },
                    onRemoveTag: { tag in
                        await viewModel.removeTag(tag, from: asset)
                    }
                )
                .presentationDetents([.large])
            }
            .fullScreenCover(item: $previewAsset) { asset in
                PhotoPreviewSheet(asset: asset, thumbnailStore: viewModel.thumbnailStore)
            }
        }
    }

    /// Re-resolves a selected asset after a reload so sheets continue showing the current model.
    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }

    /// Clamps the current review index after assets leave the queue.
    private func clampReviewIndex() {
        let count = viewModel.cleanupReviewQueue.count
        if count == 0 {
            reviewIndex = 0
        } else {
            reviewIndex = min(reviewIndex, count - 1)
        }
    }

    /// Advances the Orbit review cursor to the next remaining asset.
    private func advanceReviewIndex() {
        let count = viewModel.cleanupReviewQueue.count
        guard count > 0 else {
            reviewIndex = 0
            return
        }

        reviewIndex = min(reviewIndex + 1, count - 1)
    }
}

/// Cleanup tab that focuses only on keep, inspect, and batch-delete review actions.
struct CleanupHomeView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?
    @State private var previewAsset: MediaAsset?
    @State private var reviewIndex = 0

    /// Stores the shared view model inside local SwiftUI state for the cleanup tab.
    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let languageRefreshKey = settings.preferredLanguage.rawValue
        NavigationStack {
            Group {
                if !viewModel.authorizationStatus.canReadAssets,
                   let message = viewModel.authorizationErrorMessage {
                    LibraryAuthorizationView(
                        message: message,
                        authorizationStatus: viewModel.authorizationStatus,
                        onRequestAccess: {
                            await viewModel.requestPhotoLibraryAccessForBrowsing()
                            await viewModel.prepareCleanupData()
                        }
                    )
                } else {
                    CleanupReviewView(
                        assets: viewModel.cleanupReviewQueue,
                        thumbnailStore: viewModel.thumbnailStore,
                        currentIndex: $reviewIndex,
                        reviewMode: $viewModel.cleanupReviewMode,
                        isRefreshing: viewModel.isSyncingCleanupData,
                        pendingDeletionCount: viewModel.pendingDeletionCount,
                        pendingDeletionLimit: viewModel.pendingDeletionLimit,
                        pendingDeletionPreviewAsset: viewModel.lastPendingDeletionAsset,
                        isCommittingDeletion: viewModel.isRunningCleanup,
                        onOpenDetail: { asset in
                            selectedAsset = asset
                        },
                        onPreview: { asset in
                            previewAsset = asset
                        },
                        onKeep: { asset in
                            await viewModel.protectFromCleanup(asset)
                            clampReviewIndex()
                        },
                        onDelete: { asset in
                            let staged = viewModel.stageAssetForDeletion(asset)
                            if staged {
                                clampReviewIndex()
                            }
                            return staged
                        }
                    ) {
                        viewModel.undoLastStagedDeletion()
                        clampReviewIndex()
                    } onCommitDelete: {
                        _ = await viewModel.commitPendingDeletions()
                        clampReviewIndex()
                    }
                    .padding()
                    .id(languageRefreshKey)
                }
            }
            .navigationTitle(L10n.text("tab.cleanup", fallback: "Cleanup"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.cleanupReviewMode != AppContainer.live.settingsStore.preferredCleanupReviewMode {
                    viewModel.cleanupReviewMode = AppContainer.live.settingsStore.preferredCleanupReviewMode
                }
                if viewModel.authorizationStatus == .notDetermined {
                    await viewModel.requestPhotoLibraryAccessForBrowsing()
                    await viewModel.prepareCleanupData()
                } else {
                    await viewModel.prepareCleanupData()
                }
            }
            .alert(
                L10n.text("cleanup.action_title", fallback: "Cleanup Action"),
                isPresented: Binding(
                    get: { viewModel.cleanupReviewMessage != nil },
                    set: { newValue in
                        if !newValue {
                            viewModel.dismissCleanupReviewMessage()
                        }
                    }
                )
            ) {
                Button(L10n.text("common.ok", fallback: "OK")) {
                    viewModel.dismissCleanupReviewMessage()
                }
            } message: {
                Text(viewModel.cleanupReviewMessage ?? "")
            }
            .sheet(item: $selectedAsset) { asset in
                AssetEditorSheet(
                    asset: asset,
                    tagLibrary: viewModel.tagLibrary,
                    tagSuggestions: { await viewModel.autoTagSuggestions(for: asset) },
                    onRefresh: {
                        await viewModel.load()
                        selectedAsset = refreshedAsset(from: asset, in: viewModel.assets)
                    },
                    onToggleProtection: { await viewModel.toggleProtection(for: asset) },
                    onToggleScreenshotLike: { await viewModel.toggleImportedScreenshotLike(for: asset) },
                    onApplyRetentionRule: { rule in
                        await viewModel.applyRetentionRule(rule, to: asset)
                    },
                    onAddTag: { name, colorHex in
                        await viewModel.addTag(name: name, colorHex: colorHex, to: asset)
                    },
                    onAddTags: { entries in
                        await viewModel.addTags(entries, to: asset)
                    },
                    onRemoveTag: { tag in
                        await viewModel.removeTag(tag, from: asset)
                    }
                )
                .presentationDetents([.large])
            }
            .fullScreenCover(item: $previewAsset) { asset in
                PhotoPreviewSheet(asset: asset, thumbnailStore: viewModel.thumbnailStore)
            }
        }
    }

    /// Re-resolves a selected asset after a reload so sheets continue showing the current model.
    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }

    /// Clamps the current cleanup review index after assets leave the queue.
    private func clampReviewIndex() {
        let count = viewModel.cleanupReviewQueue.count
        if count == 0 {
            reviewIndex = 0
        } else {
            reviewIndex = min(reviewIndex, count - 1)
        }
    }
}

/// Tag management tab that exposes the library's folder-like tag catalog.
struct TagHomeView: View {
    @Environment(AppSettingsStore.self) private var settings
    @State private var viewModel: LibraryHomeViewModel

    /// Stores the shared view model inside local SwiftUI state for the tags tab.
    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let languageRefreshKey = settings.preferredLanguage.rawValue
        NavigationStack {
            Group {
                if let message = viewModel.authorizationErrorMessage {
                    LibraryAuthorizationView(
                        message: message,
                        authorizationStatus: viewModel.authorizationStatus,
                        onRequestAccess: {
                            await viewModel.requestPhotoLibraryAccess()
                        }
                    )
                } else {
                    List {
                        Section {
                            Text(L10n.text("tags.intro", fallback: "Manage your library by tag, like folders. Open a tag to see every photo inside it."))
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.tagLibrary.isEmpty {
                            Section(L10n.text("tab.tags", fallback: "Tags")) {
                                Text(L10n.text("tags.empty", fallback: "No tags yet. Open a photo in Library and add tags first."))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Section(L10n.text("tab.tags", fallback: "Tags")) {
                                ForEach(viewModel.tagLibrary) { entry in
                                    let tagAssets = viewModel.assets(for: entry)
                                    NavigationLink {
                                        TagDetailView(viewModel: viewModel, tagEntry: entry)
                                    } label: {
                                        TagFolderRow(entry: entry, assets: tagAssets, thumbnailStore: viewModel.thumbnailStore)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .id(languageRefreshKey)
                }
            }
            .navigationTitle(L10n.text("tab.tags", fallback: "Tags"))
            .task {
                if viewModel.authorizationStatus == .notDetermined {
                    await viewModel.requestPhotoLibraryAccess()
                } else if viewModel.assets.isEmpty {
                    await viewModel.load()
                } else {
                    await viewModel.ensureFullLibraryLoaded()
                }
            }
        }
    }
}

/// Detail page for one tag, including rename, merge, delete, and asset browsing actions.
private struct TagDetailView: View {
    @State private var viewModel: LibraryHomeViewModel
    let tagEntry: TagLibraryEntry
    @State private var selectedAsset: MediaAsset?
    @State private var isShowingRenamePrompt = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingMergePrompt = false
    @State private var draftTagName = ""
    @State private var mergeTargetID = ""

    private let gridColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    /// Stores the shared view model inside local SwiftUI state for the selected tag.
    init(viewModel: LibraryHomeViewModel, tagEntry: TagLibraryEntry) {
        _viewModel = State(initialValue: viewModel)
        self.tagEntry = tagEntry
    }

    var body: some View {
        VStack(spacing: 16) {
            SnapuaryCard(title: tagEntry.name) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: tagEntry.colorHex) ?? .accentColor)
                        .frame(width: 14, height: 14)
                    Text(photoCountLabel(for: assets.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            LibraryGrid(
                assets: assets,
                thumbnailStore: viewModel.thumbnailStore,
                isLoading: false,
                isLoadingMore: false,
                loadedAssetCount: assets.count,
                totalAssetCount: assets.count,
                progress: 1,
                columns: gridColumns,
                onApproachingEnd: { _ in },
                onSelect: { selectedAsset = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .navigationTitle(tagEntry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu(L10n.text("common.manage", fallback: "Manage")) {
                    Button(L10n.text("common.rename", fallback: "Rename")) {
                        draftTagName = tagEntry.name
                        isShowingRenamePrompt = true
                    }

                    Button(L10n.text("tags.merge_into", fallback: "Merge Into...")) {
                        mergeTargetID = mergeTargets.first?.id ?? ""
                        isShowingMergePrompt = true
                    }
                    .disabled(mergeTargets.isEmpty)

                    Button(L10n.text("tags.delete_tag", fallback: "Delete Tag"), role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
        }
        .alert(L10n.text("tags.rename_title", fallback: "Rename Tag"), isPresented: $isShowingRenamePrompt) {
            TextField(L10n.text("tags.tag_name", fallback: "Tag name"), text: $draftTagName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(L10n.text("common.cancel", fallback: "Cancel"), role: .cancel) {}
            Button(L10n.text("common.save", fallback: "Save")) {
                Task {
                    await viewModel.renameTag(tagEntry, to: draftTagName)
                    await viewModel.load()
                }
            }
        } message: {
            Text(L10n.text("tags.rename_message", fallback: "Update this tag across every photo that uses it."))
        }
        .alert(L10n.text("tags.delete_confirm_title", fallback: "Delete Tag?"), isPresented: $isShowingDeleteConfirmation) {
            Button(L10n.text("common.cancel", fallback: "Cancel"), role: .cancel) {}
            Button(L10n.text("common.delete", fallback: "Delete"), role: .destructive) {
                Task {
                    await viewModel.deleteTag(tagEntry)
                    await viewModel.load()
                }
            }
        } message: {
            Text(L10n.text("tags.delete_confirm_message", fallback: "This removes the tag from every photo that currently uses it."))
        }
        .alert(L10n.text("tags.merge_title", fallback: "Merge Tag"), isPresented: $isShowingMergePrompt) {
            Picker(L10n.text("tags.merge_picker", fallback: "Merge into"), selection: $mergeTargetID) {
                ForEach(mergeTargets) { entry in
                    Text(entry.name).tag(entry.id)
                }
            }
            Button(L10n.text("common.cancel", fallback: "Cancel"), role: .cancel) {}
            Button(L10n.text("common.merge", fallback: "Merge")) {
                guard let destination = mergeTargets.first(where: { $0.id == mergeTargetID }) else {
                    return
                }
                Task {
                    await viewModel.mergeTag(tagEntry, into: destination)
                    await viewModel.load()
                }
            }
        } message: {
            Text(L10n.text("tags.merge_message", fallback: "Every photo using %@ will be reassigned to the selected tag.", tagEntry.name))
        }
        .sheet(item: $selectedAsset) { asset in
            AssetEditorSheet(
                asset: asset,
                tagLibrary: viewModel.tagLibrary,
                tagSuggestions: { await viewModel.autoTagSuggestions(for: asset) },
                onRefresh: {
                    await viewModel.load()
                    selectedAsset = refreshedAsset(from: asset, in: viewModel.assets)
                },
                onToggleProtection: { await viewModel.toggleProtection(for: asset) },
                onToggleScreenshotLike: { await viewModel.toggleImportedScreenshotLike(for: asset) },
                onApplyRetentionRule: { rule in
                    await viewModel.applyRetentionRule(rule, to: asset)
                },
                onAddTag: { name, colorHex in
                    await viewModel.addTag(name: name, colorHex: colorHex, to: asset)
                },
                onAddTags: { entries in
                    await viewModel.addTags(entries, to: asset)
                },
                onRemoveTag: { tag in
                    await viewModel.removeTag(tag, from: asset)
                }
            )
            .presentationDetents([.large])
        }
    }

    private var assets: [MediaAsset] {
        viewModel.assets(for: tagEntry)
    }

    private var mergeTargets: [TagLibraryEntry] {
        viewModel.tagLibrary.filter { $0.id != tagEntry.id }
    }

    /// Re-resolves a selected asset after edits so the detail sheet stays in sync.
    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }

}

/// Permission gate shown when Photos access is missing or restricted.
private struct LibraryAuthorizationView: View {
    let message: String
    let authorizationStatus: PhotoLibraryAuthorizationStatus
    let onRequestAccess: () async -> Void

    var body: some View {
        ScrollView {
            SnapuaryCard(title: L10n.text("photo_access.title", fallback: "Photo Access")) {
                Text(message)
                    .foregroundStyle(.secondary)

                if authorizationStatus == .notDetermined {
                    Button(L10n.text("photo_access.allow_button", fallback: "Allow Photo Access")) {
                        Task {
                            await onRequestAccess()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}

/// Compact row used by the Tags tab to preview one tag and its asset count.
private struct TagFolderRow: View {
    let entry: TagLibraryEntry
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore

    var body: some View {
        HStack(spacing: 12) {
            TagCoverPreview(entry: entry, assets: assets, thumbnailStore: thumbnailStore)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.headline)
                Text(photoCountLabel(for: assets.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Small cover collage used in tag rows to preview recent assets for a tag.
private struct TagCoverPreview: View {
    let entry: TagLibraryEntry
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((Color(hex: entry.colorHex) ?? .accentColor).opacity(0.14))

            if assets.isEmpty {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color(hex: entry.colorHex) ?? .accentColor)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(assets.prefix(4))) { asset in
                        PhotoThumbnailView(asset: asset, thumbnailStore: thumbnailStore, cornerRadius: 8)
                            .frame(height: 24)
                    }
                }
                .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Intro card at the top of the browse tab that summarizes what the Library tab can do.
private struct LibraryHeader: View {
    let viewModel: LibraryHomeViewModel

    var body: some View {
        SnapuaryCard(title: L10n.text("library.browse_title", fallback: "Browse")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("library.browse_body", fallback: "Tap any photo to tag it, mark it as a screenshot, protect it, or set cleanup rules."))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    PhotoCountBadge(title: L10n.text("library.collection.all", fallback: "All"), count: viewModel.filteredAssets.count)
                    PhotoCountBadge(title: L10n.text("library.collection.screenshots", fallback: "Screenshots"), count: viewModel.screenshotAssets.count)
                    PhotoCountBadge(title: L10n.text("library.collection.photos", fallback: "Photos"), count: viewModel.nonScreenshotAssets.count)
                }
            }
        }
    }
}

/// Search, collection, and tag filter controls for the Library grid.
private struct LibraryFilterStrip: View {
    @Bindable var viewModel: LibraryHomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.text("library.collection_picker", fallback: "Collection"), selection: $viewModel.selectedCollection) {
                ForEach(LibraryCollection.allCases) { collection in
                    Text(collection.title).tag(collection)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: L10n.text("tags.all_tags", fallback: "All Tags"),
                        isSelected: viewModel.selectedTag == nil
                    ) {
                        viewModel.selectedTag = nil
                    }

                    ForEach(viewModel.availableTags) { tag in
                        FilterChip(
                            title: tag.name,
                            isSelected: viewModel.selectedTag?.normalizedName == tag.normalizedName
                        ) {
                            viewModel.toggleTag(tag)
                        }
                    }
                }
            }

            if !viewModel.searchText.isEmpty || viewModel.selectedTag != nil {
                Button(L10n.text("common.clear_filters", fallback: "Clear Filters")) {
                    viewModel.clearFilters()
                }
                .font(.footnote)
            }
        }
    }
}

/// Wrapper around the asset grid that also handles loading and empty states.
private struct LibraryGrid: View {
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore
    let isLoading: Bool
    let isLoadingMore: Bool
    let loadedAssetCount: Int
    let totalAssetCount: Int
    let progress: Double
    let columns: [GridItem]
    let onApproachingEnd: (Int) -> Void
    let onSelect: (MediaAsset) -> Void

    var body: some View {
        if assets.isEmpty, isLoading {
            SnapuaryCard(title: L10n.text("library.loading_title", fallback: "Loading Library")) {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: progress, total: 1)
                    Text(progressLabel)
                        .foregroundStyle(.secondary)
                }
            }
        } else if assets.isEmpty {
            SnapuaryCard(title: L10n.text("library.no_results_title", fallback: "No Results")) {
                Text(L10n.text("library.no_results_body", fallback: "No photos match the current collection, search, or tag filter."))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading || isLoadingMore {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress, total: 1)
                            .controlSize(.small)
                        Text(progressLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                AssetCollectionGridView(
                    assets: assets,
                    thumbnailStore: thumbnailStore,
                    onSelect: onSelect,
                    onApproachingEnd: onApproachingEnd
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    /// Builds the progress label shown while the library is scanning or paging more assets.
    private var progressLabel: String {
        if totalAssetCount > 0 {
            if loadedAssetCount >= totalAssetCount {
                return L10n.text("library.loaded_all", fallback: "Loaded all %lld photos.", totalAssetCount)
            }

            let percentage = Int((progress * 100).rounded())
            return L10n.text(
                "library.loaded_progress",
                fallback: "Loaded %lld of %lld photos (%d%%).",
                loadedAssetCount,
                totalAssetCount,
                percentage
            )
        }

        return L10n.text("library.scanning", fallback: "Scanning your photo library and showing photos as they are discovered.")
    }
}

/// Full-screen cleanup review surface with review-mode switching and batch delete controls.
private struct CleanupReviewView: View {
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore
    @Binding var currentIndex: Int
    @Binding var reviewMode: CleanupReviewMode
    let isRefreshing: Bool
    let pendingDeletionCount: Int
    let pendingDeletionLimit: Int
    let pendingDeletionPreviewAsset: MediaAsset?
    let isCommittingDeletion: Bool
    let onOpenDetail: (MediaAsset) -> Void
    let onPreview: (MediaAsset) -> Void
    let onKeep: (MediaAsset) async -> Void
    let onDelete: (MediaAsset) async -> Bool
    let onUndoDelete: () -> Void
    let onCommitDelete: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            reviewHeader

            if let asset = currentAsset {
                CleanupReviewCard(
                    asset: asset,
                    nextAsset: nextAsset,
                    thumbnailStore: thumbnailStore,
                    onPreview: { onPreview(asset) },
                    onOpenDetail: { onOpenDetail(asset) },
                    onKeep: {
                        await onKeep(asset)
                        advanceAfterAction()
                    },
                    onDelete: {
                        let deleted = await onDelete(asset)
                        if deleted {
                            advanceAfterAction()
                        }
                    }
                )
                .id(asset.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SnapuaryCard(title: L10n.text("cleanup.all_clear_title", fallback: "All Clear")) {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if pendingDeletionCount > 0 {
                PendingDeletionBar(
                    pendingCount: pendingDeletionCount,
                    pendingLimit: pendingDeletionLimit,
                    previewAsset: pendingDeletionPreviewAsset,
                    isDeleting: isCommittingDeletion,
                    itemLabel: reviewMode == .screenshots ? L10n.text("cleanup.item.screenshot", fallback: "screenshot") : L10n.text("cleanup.item.photo", fallback: "photo"),
                    onUndo: onUndoDelete,
                    onDeleteNow: {
                        await onCommitDelete()
                    }
                )
            }
        }
        .onChange(of: assets.count) { _, newCount in
            if newCount == 0 {
                currentIndex = 0
            } else {
                currentIndex = min(currentIndex, newCount - 1)
            }
        }
        .onChange(of: reviewMode) { _, _ in
            currentIndex = 0
        }
    }

    /// Returns the asset currently being reviewed.
    private var currentAsset: MediaAsset? {
        guard assets.indices.contains(currentIndex) else {
            return assets.first
        }

        return assets[currentIndex]
    }

    /// Returns the asset previewed underneath the current review card.
    private var nextAsset: MediaAsset? {
        let nextIndex = currentIndex + 1
        guard assets.indices.contains(nextIndex) else {
            return nil
        }

        return assets[nextIndex]
    }

    /// Returns the empty-state copy for the current cleanup review mode.
    private var emptyStateMessage: String {
        switch reviewMode {
        case .screenshots:
            L10n.text("cleanup.empty_screenshots", fallback: "No screenshots are waiting for review.")
        case .allPhotos:
            L10n.text("cleanup.empty_photos", fallback: "No photos are waiting for review.")
        }
    }

    /// Builds the top-of-screen controls for cleanup review.
    private var reviewHeader: some View {
        VStack(spacing: 12) {
            ReviewModePicker(reviewMode: $reviewMode)

            if isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("library.refreshing", fallback: "Refreshing library"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Keeps the review cursor inside bounds after an asset leaves the queue.
    private func advanceAfterAction() {
        if assets.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, max(assets.count - 1, 0))
        }
    }
}

/// Swipe-driven cleanup card that supports keep, inspect, and staged-delete actions.
private struct CleanupReviewCard: View {
    let asset: MediaAsset
    let nextAsset: MediaAsset?
    let thumbnailStore: PhotoLibraryThumbnailStore
    let onPreview: () -> Void
    let onOpenDetail: () -> Void
    let onKeep: () async -> Void
    let onDelete: () async -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isActing = false

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { _ in
                ZStack {
                    if let nextAsset {
                        ReviewCardFace(
                            asset: nextAsset,
                            thumbnailStore: thumbnailStore,
                            overlayOpacity: 0.18
                        )
                        .scaleEffect(0.94)
                        .offset(y: 18)
                    }

                    ReviewCardFace(
                        asset: asset,
                        thumbnailStore: thumbnailStore,
                        overlayOpacity: 0
                    )
                    .onTapGesture(perform: onPreview)
                    .overlay(alignment: .topLeading) {
                        if dragOffset.width > 24 {
                            swipeCue(
                                systemImage: "bookmark.fill",
                                tint: .green,
                                emphasis: min(abs(dragOffset.width) / 140, 1)
                            )
                            .padding(.top, 28)
                            .padding(.leading, 18)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if dragOffset.width < -24 {
                            swipeCue(
                                systemImage: "trash.fill",
                                tint: .red,
                                emphasis: min(abs(dragOffset.width) / 140, 1)
                            )
                            .padding(.top, 28)
                            .padding(.trailing, 18)
                        }
                    }
                    .offset(x: dragOffset.width)
                    .rotationEffect(.degrees(Double(dragOffset.width / 18)))
                    .shadow(color: Color.black.opacity(0.14), radius: 30, y: 22)
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard !isActing else { return }
                                dragOffset = CGSize(width: value.translation.width, height: 0)
                            }
                            .onEnded { value in
                                guard !isActing else { return }

                                if value.translation.width > 120 {
                                    Task { await performKeep() }
                                } else if value.translation.width < -120 {
                                    Task { await performDelete() }
                                } else {
                                    resetDragOffset()
                                }
                            }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: 470)

            HStack(spacing: 16) {
                ActionOrbButton(
                    title: L10n.text("cleanup.delete", fallback: "Delete"),
                    systemImage: "trash.fill",
                    tint: .red,
                    isEnabled: !isActing
                ) {
                    Task { await performDelete() }
                }

                ActionOrbButton(
                    title: L10n.text("cleanup.inspect", fallback: "Inspect"),
                    systemImage: "slider.horizontal.3",
                    tint: .blue,
                    isEnabled: !isActing,
                    action: onOpenDetail
                )

                ActionOrbButton(
                    title: L10n.text("cleanup.keep", fallback: "Keep"),
                    systemImage: "bookmark.fill",
                    tint: .green,
                    isEnabled: !isActing
                ) {
                    Task { await performKeep() }
                }
            }
            .padding(.horizontal, 8)

            if !asset.title.isEmpty {
                Text(asset.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Performs the keep action once and then resets the local drag state.
    private func performKeep() async {
        guard !isActing else { return }
        isActing = true
        await onKeep()
        resetDragOffset(animated: false)
        isActing = false
    }

    /// Performs the staged-delete action once and then resets the local drag state.
    private func performDelete() async {
        guard !isActing else { return }
        isActing = true
        await onDelete()
        resetDragOffset(animated: false)
        isActing = false
    }

    /// Resets the swipe offset, optionally with a spring animation.
    private func resetDragOffset(animated: Bool = true) {
        let action = { dragOffset = .zero }
        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82), action)
        } else {
            action()
        }
    }
}

/// Orbit review surface that combines recipe shortcuts, the active review card, and the Orbit rail.
private struct OrbitReviewView: View {
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore
    @Binding var currentIndex: Int
    let isRefreshing: Bool
    let orbitCollections: [OrbitCollection]
    @Binding var selectedOrbitID: String?
    let orbitAssetCounts: [String: Int]
    let orbitAssets: [MediaAsset]
    let recipeCollections: [OrbitCollection]
    let activeRecipe: OrbitRecipeKind?
    let smartSuggestionsProvider: (MediaAsset) -> [OrbitSuggestion]
    let onPreview: (MediaAsset) -> Void
    let onOrbit: (MediaAsset) async -> Void
    let onCreateOrbit: () -> Void
    let onSelectRecipe: (OrbitCollection) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                if isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.text("orbit.refreshing", fallback: "Refreshing Orbit inbox"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                OrbitRecipeStrip(
                    collections: recipeCollections,
                    activeRecipe: activeRecipe,
                    onSelect: onSelectRecipe
                )

                if let asset = currentAsset {
                    OrbitReviewCard(
                        asset: asset,
                        nextAsset: nextAsset,
                        thumbnailStore: thumbnailStore,
                        onPreview: { onPreview(asset) },
                        onOrbit: {
                            await onOrbit(asset)
                            advanceAfterAction()
                        }
                    )
                    .id(asset.id)
                    .frame(maxWidth: .infinity)
                } else {
                    SnapuaryCard(title: L10n.text("orbit.empty_title", fallback: "Orbit Inbox Clear")) {
                        Text(L10n.text("orbit.empty_body", fallback: "No more photos are waiting to be sorted into an Orbit right now."))
                            .foregroundStyle(.secondary)
                    }
                }

                OrbitRailView(
                    collections: orbitCollections,
                    selectedOrbitID: $selectedOrbitID,
                    assetCounts: orbitAssetCounts,
                    assets: orbitAssets,
                    thumbnailStore: thumbnailStore,
                    suggestions: currentAsset.map(smartSuggestionsProvider) ?? [],
                    onCreateOrbit: onCreateOrbit
                )

                if let title = currentAsset?.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 20)
        }
        .onChange(of: assets.count) { _, newCount in
            if newCount == 0 {
                currentIndex = 0
            } else {
                currentIndex = min(currentIndex, newCount - 1)
            }
        }
    }

    /// Returns the asset currently at the top of the Orbit inbox.
    private var currentAsset: MediaAsset? {
        guard assets.indices.contains(currentIndex) else {
            return assets.first
        }

        return assets[currentIndex]
    }

    /// Returns the asset previewed behind the current Orbit card.
    private var nextAsset: MediaAsset? {
        let nextIndex = currentIndex + 1
        guard assets.indices.contains(nextIndex) else {
            return nil
        }

        return assets[nextIndex]
    }

    /// Keeps the Orbit review cursor inside bounds after one asset gets assigned.
    private func advanceAfterAction() {
        if assets.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, max(assets.count - 1, 0))
        }
    }
}

/// Downward-drag Orbit card that turns a photo into a targeted Orbit assignment gesture.
private struct OrbitReviewCard: View {
    let asset: MediaAsset
    let nextAsset: MediaAsset?
    let thumbnailStore: PhotoLibraryThumbnailStore
    let onPreview: () -> Void
    let onOrbit: () async -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isActing = false

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let activeVerticalOffset = max(dragOffset.height, 0)
                let orbitProgress = min(max((activeVerticalOffset - 12) / 210, 0), 1)
                let orbitCueProgress = min(max(activeVerticalOffset / 150, 0), 1)
                let targetSize: CGFloat = 68
                let baseHeight: CGFloat = 440
                let baseWidth = max(min(geometry.size.width, 380), targetSize)
                let cardWidth = baseWidth - ((baseWidth - targetSize) * orbitProgress)
                let cardHeight = baseHeight - ((baseHeight - targetSize) * orbitProgress)
                let cardCornerRadius = 28 + ((targetSize / 2 - 28) * orbitProgress)

                ZStack {
                    if let nextAsset {
                        ReviewCardFace(
                            asset: nextAsset,
                            thumbnailStore: thumbnailStore,
                            overlayOpacity: 0.18
                        )
                        .scaleEffect(0.94)
                        .offset(y: 18)
                    }

                    ReviewCardFace(
                        asset: asset,
                        thumbnailStore: thumbnailStore,
                        overlayOpacity: 0
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                    .onTapGesture(perform: onPreview)
                    .overlay(alignment: .bottom) {
                        orbitDropTarget(emphasis: orbitCueProgress)
                            .padding(.bottom, 18)
                    }
                    .offset(y: activeVerticalOffset * 0.82)
                    .shadow(color: Color.black.opacity(0.14), radius: 30, y: 22)
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard !isActing else { return }
                                dragOffset = CGSize(width: 0, height: max(value.translation.height, 0))
                            }
                            .onEnded { value in
                                guard !isActing else { return }

                                if value.translation.height > 130 {
                                    Task { await performOrbit() }
                                } else {
                                    resetDragOffset()
                                }
                            }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: 470)
        }
    }

    /// Builds the floating Orbit target that appears as the card shrinks into a ball.
    private func orbitDropTarget(emphasis: Double) -> some View {
        let strokeColor = Color.accentColor.opacity(0.18 + (0.26 * emphasis))
        let shadowColor = Color.accentColor.opacity(0.08 + (0.1 * emphasis))

        return Image(systemName: "circle.hexagongrid.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.accentColor.opacity(0.92))
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(strokeColor, lineWidth: 1.2))
            .shadow(color: shadowColor, radius: 14, y: 6)
            .opacity(0.2 + (0.6 * emphasis))
            .scaleEffect(0.86 + (0.14 * emphasis))
    }

    /// Performs the Orbit assignment once and then resets the drag state.
    private func performOrbit() async {
        guard !isActing else { return }
        isActing = true
        await onOrbit()
        resetDragOffset(animated: false)
        isActing = false
    }

    /// Resets the downward drag offset, optionally with animation.
    private func resetDragOffset(animated: Bool = true) {
        let action = { dragOffset = .zero }
        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82), action)
        } else {
            action()
        }
    }
}

/// Segmented pill control for toggling cleanup review modes.
private struct ReviewModePicker: View {
    @Binding var reviewMode: CleanupReviewMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CleanupReviewMode.allCases) { mode in
                Button {
                    reviewMode = mode
                } label: {
                    Text(mode.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(reviewMode == mode ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if reviewMode == mode {
                                    Capsule().fill(Color.accentColor)
                                } else {
                                    Capsule().fill(Color(.secondarySystemBackground))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(.tertiarySystemBackground), in: Capsule())
    }
}

/// Floating swipe cue used by cleanup review to hint at keep or delete outcomes.
private func swipeCue(
    systemImage: String,
    tint: Color,
    emphasis: Double
) -> some View {
    Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(tint.opacity(0.95))
        .frame(width: 34, height: 34)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                }
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        .opacity(0.58 + (0.2 * emphasis))
        .scaleEffect(0.94 + (0.05 * emphasis))
}

/// Horizontal rail that shows Orbit collections and the assets already placed into the active Orbit.
private struct OrbitRailView: View {
    let collections: [OrbitCollection]
    @Binding var selectedOrbitID: String?
    let assetCounts: [String: Int]
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore
    let suggestions: [OrbitSuggestion]
    let onCreateOrbit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let topSuggestion = suggestions.first,
               let suggestedOrbit = collections.first(where: { $0.id == topSuggestion.orbitID }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Smart Orbit: \(suggestedOrbit.name)")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(collections) { orbit in
                        Button {
                            selectedOrbitID = orbit.id
                        } label: {
                            OrbitTagCapsule(
                                title: orbit.name,
                                colorHex: orbit.colorHex,
                                symbolName: orbit.symbolName,
                                count: assetCounts[orbit.id] ?? 0,
                                isSelected: selectedOrbitID == orbit.id
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onCreateOrbit) {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(assets, id: \.gridIdentifier) { asset in
                        PhotoThumbnailView(asset: asset, thumbnailStore: thumbnailStore, cornerRadius: 999, contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
                            }
                            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 38)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemBackground).opacity(0.72))
        )
    }
}

/// Capsule-style Orbit selector shown inside the Orbit rail.
private struct OrbitTagCapsule: View {
    let title: String
    let colorHex: String
    let symbolName: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: colorHex) ?? .accentColor)
                .frame(width: 8, height: 8)
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isSelected ? Color.white.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .overlay {
            Capsule()
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

/// Horizontal recipe strip for task-style Orbit review sessions.
private struct OrbitRecipeStrip: View {
    let collections: [OrbitCollection]
    let activeRecipe: OrbitRecipeKind?
    let onSelect: (OrbitCollection) -> Void

    var body: some View {
        if !collections.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(collections) { collection in
                        let isSelected = activeRecipe == collection.recipe
                        Button {
                            onSelect(collection)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(collection.recipe?.title ?? collection.name, systemImage: collection.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                if let subtitle = collection.recipe?.subtitle {
                                    Text(subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Weekly recap card surfaced on the Library tab.
private struct OrbitRecapCard: View {
    let recap: OrbitWeeklyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Recap")
                .font(.headline)

            HStack(spacing: 12) {
                recapMetric(title: "Orbited", value: recap.assignedCount)
                recapMetric(title: "Kept", value: recap.keptCount)
                recapMetric(title: "Deleted", value: recap.deletedCount)
            }

            if !recap.topOrbitNames.isEmpty {
                Text("Top orbits: \(recap.topOrbitNames.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    /// Builds one metric column inside the weekly recap card.
    private func recapMetric(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold))
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Placeholder cluster card used for grouped review concepts.
private struct OrbitClusterCard: View {
    let cluster: OrbitReviewCluster

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.down.right")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cluster Review")
                    .font(.headline)
                Text("\(cluster.count) related items around \(cluster.title)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

/// Shared visual face used by both cleanup and Orbit review cards.
private struct ReviewCardFace: View {
    let asset: MediaAsset
    let thumbnailStore: PhotoLibraryThumbnailStore
    let overlayOpacity: Double

    var body: some View {
        PhotoThumbnailView(asset: asset, thumbnailStore: thumbnailStore, cornerRadius: 28, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 440)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(overlayOpacity))
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    metadataChip(
                        title: asset.kind.displayName,
                        systemImage: asset.kind == .photo ? "photo" : "camera.viewfinder"
                    )

                    if asset.isProtectedFromCleanup {
                        metadataChip(
                            title: L10n.text("cleanup.keep", fallback: "Keep"),
                            systemImage: "bookmark.fill"
                        )
                    } else if !asset.tags.isEmpty {
                        metadataChip(title: tagLabel, systemImage: "tag.fill")
                    }
                }
                .padding(18)
            }
    }

    /// Builds the small metadata chips layered above the review card image.
    private func metadataChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Bottom bar that manages the staged deletion queue and commit action.
private struct PendingDeletionBar: View {
    let pendingCount: Int
    let pendingLimit: Int
    let previewAsset: MediaAsset?
    let isDeleting: Bool
    let itemLabel: String
    let onUndo: () -> Void
    let onDeleteNow: () async -> Void

    @State private var isSubmitting = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(queueCountLabel)
                    .font(.subheadline.weight(.semibold))
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(L10n.text("common.undo", fallback: "Undo"), action: onUndo)
                .buttonStyle(.bordered)
                .disabled(isDeleting || isSubmitting)

            Button {
                Task { await submitDeletion() }
            } label: {
                Text(isDeleting || isSubmitting ? L10n.text("cleanup.deleting", fallback: "Deleting...") : L10n.text("cleanup.delete_count", fallback: "Delete %lld", pendingCount))
            }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting || isSubmitting)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Returns the secondary status line shown under the queue count.
    private var statusLine: String {
        if pendingCount >= pendingLimit {
            return L10n.text("cleanup.queue_full", fallback: "Queue is full. Delete or undo before adding more screenshots.")
        }

        if let previewAsset {
            return L10n.text("cleanup.latest_queued", fallback: "Latest queued: %@", previewAsset.title)
        }

        return L10n.text("cleanup.review_or_delete_batch", fallback: "Review more screenshots or delete this batch now.")
    }

    /// Returns the localized queue-count label for the staged deletion batch.
    private var queueCountLabel: String {
        if pendingCount == 1 {
            return L10n.text("cleanup.queue_count_singular", fallback: "1 %@ queued", itemLabel)
        }

        return L10n.text("cleanup.queue_count_plural", fallback: "%lld %@s queued", pendingCount, itemLabel)
    }

    /// Submits the staged deletion batch while preventing duplicate taps.
    private func submitDeletion() async {
        guard !isSubmitting else {
            return
        }

        isSubmitting = true
        await onDeleteNow()
        isSubmitting = false
    }
}

private extension ReviewCardFace {
    /// Formats the tag area of the review card when one or more tags are attached.
    var tagLabel: String {
        if asset.tags.count == 1 {
            return L10n.text("tags.count.singular", fallback: "1 tag")
        }

        return L10n.text("tags.count.plural", fallback: "%lld tags", asset.tags.count)
    }
}

private struct ActionOrbButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
    }
}

private struct SnapshotOverviewCard: View {
    let viewModel: LibraryHomeViewModel

    var body: some View {
        SnapuaryCard(title: "Cleanup Overview") {
            if viewModel.isSyncingCleanupData {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing cleanup data in the background.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(label: "Screenshots", value: "\(viewModel.cleanupSummary.totalScreenshotCount)")
                StatTile(label: "Auto-managed", value: "\(viewModel.cleanupSummary.autoManagedCount)")
                StatTile(label: "Expiring Soon", value: "\(viewModel.cleanupSummary.expiringSoonCount)")
                StatTile(label: "Protected", value: "\(viewModel.cleanupSummary.protectedCount)")
                StatTile(label: "Ready to Clean", value: "\(viewModel.cleanupSummary.readyToCleanCount)")
            }
        }
    }
}

private struct CleanupReminderCard: View {
    let viewModel: LibraryHomeViewModel

    var body: some View {
        SnapuaryCard(title: "Cleanup Reminder") {
            Text(statusLine)
                .foregroundStyle(.secondary)

            if let reminder = viewModel.nextCleanupReminder {
                Text("Next reminder: \(reminder.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                Text("Assets due that day: \(reminder.candidateCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.cleanupReminderStatus == .notDetermined || viewModel.cleanupReminderStatus == .denied {
                Button("Enable Cleanup Reminders") {
                    Task {
                        await viewModel.requestCleanupReminderPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(viewModel.isSchedulingReminder ? "Scheduling..." : "Schedule Next Reminder") {
                    Task {
                        await viewModel.scheduleNextCleanupReminder()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSchedulingReminder)
            }
        }
    }

    private var statusLine: String {
        switch viewModel.cleanupReminderStatus {
        case .notDetermined:
            return "Notifications are not configured yet."
        case .denied:
            return "Notifications are disabled. Enable them in Settings to get cleanup reminders."
        case .authorized:
            return "Cleanup reminders are enabled."
        case .provisional:
            return "Cleanup reminders are provisionally authorized."
        case .ephemeral:
            return "Cleanup reminders are temporarily authorized."
        }
    }
}

private struct CleanupQueueCard: View {
    let viewModel: LibraryHomeViewModel
    let onSelect: (MediaAsset) -> Void

    var body: some View {
        SnapuaryCard(title: "Cleanup Queue") {
            if let result = viewModel.lastCleanupResult {
                Text("Last cleanup deleted \(result.deletedCount) screenshot(s).")
                    .foregroundStyle(.secondary)
            }

            if viewModel.cleanupCandidates.isEmpty {
                Text("No expired screenshots are waiting for cleanup.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.cleanupCandidates) { asset in
                    Button {
                        onSelect(asset)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(asset.title)
                                    .font(.subheadline.weight(.medium))
                                if let expirationDate = asset.expirationDate {
                                    Text("Expired \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(asset.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                Button(viewModel.isRunningCleanup ? "Cleaning..." : "Run Cleanup Now") {
                    Task {
                        await viewModel.runCleanupNow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunningCleanup)
            }
        }
    }
}

private struct DefaultCleanupPoolCard: View {
    let title: String
    let subtitle: String
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore
    let emptyText: String
    let onSelect: (MediaAsset) -> Void

    var body: some View {
        SnapuaryCard(title: title) {
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if assets.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets) { asset in
                    AssetRow(asset: asset, thumbnailStore: thumbnailStore) {
                        onSelect(asset)
                    }
                }
            }
        }
    }
}

private struct AssetRow: View {
    let asset: MediaAsset
    let thumbnailStore: PhotoLibraryThumbnailStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                PhotoThumbnailView(asset: asset, thumbnailStore: thumbnailStore, cornerRadius: 12)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(asset.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if asset.isProtectedFromCleanup {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(asset.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let expirationDate = asset.expirationDate {
                        Text("Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !asset.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(asset.tags) { tag in
                                    TagPill(tag: tag)
                                }
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct AssetGridTile: View {
    let asset: MediaAsset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(tileBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        PhotoThumbnailView(asset: asset, cornerRadius: 0, contentMode: .fill)
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            if asset.isScreenshot {
                                TileBadge(systemImage: "camera.viewfinder")
                            }
                            if asset.isProtectedFromCleanup {
                                TileBadge(systemImage: "bookmark.fill")
                            }
                        }
                        .padding(8)
                    }

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.58)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)

                    if !asset.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(asset.tags.prefix(2)) { tag in
                                    CompactTagPill(tag: tag)
                                }
                                if asset.tags.count > 2 {
                                    Text("+\(asset.tags.count - 2)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.white.opacity(0.9))
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .buttonStyle(.plain)
    }

    private var tileBackground: LinearGradient {
        if asset.isScreenshot {
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PhotoThumbnailView: View {
    let asset: MediaAsset
    let thumbnailStore: PhotoLibraryThumbnailStore
    let cornerRadius: CGFloat
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    /// Initializes a thumbnail view for one asset and its desired display style.
    init(
        asset: MediaAsset,
        thumbnailStore: PhotoLibraryThumbnailStore = .empty,
        cornerRadius: CGFloat,
        contentMode: ContentMode = .fill
    ) {
        self.asset = asset
        self.thumbnailStore = thumbnailStore
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(asset.isScreenshot ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: asset.isScreenshot ? "camera.viewfinder" : "photo")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(asset.isScreenshot ? Color.accentColor : Color.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: asset.libraryIdentifier) {
            await loadThumbnailIfNeeded()
        }
        .onDisappear {
            thumbnailStore.cancelRequest(requestID)
        }
    }

    /// Starts a thumbnail request the first time the view appears for a specific asset.
    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard image == nil,
              let libraryIdentifier = asset.libraryIdentifier else {
            return
        }

        let targetSize = CGSize(width: 300, height: 300)
        requestID = thumbnailStore.requestThumbnail(
            for: libraryIdentifier,
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit
        ) { renderedImage in
            image = renderedImage
        }
    }
}

/// Full-screen preview sheet with zoom support for inspecting one photo at larger size.
private struct PhotoPreviewSheet: View {
    let asset: MediaAsset
    let thumbnailStore: PhotoLibraryThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableImageScrollView(image: image)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                Spacer()

                Text(asset.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.4), in: Capsule())
            }
            .padding(20)
        }
        .task(id: asset.libraryIdentifier) {
            await loadPreviewIfNeeded()
        }
        .onDisappear {
            thumbnailStore.cancelRequest(requestID)
        }
    }

    /// Starts a larger preview-image request once the sheet appears.
    @MainActor
    private func loadPreviewIfNeeded() async {
        guard image == nil,
              let libraryIdentifier = asset.libraryIdentifier else {
            return
        }

        let screenBounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: screenBounds.width * scale, height: screenBounds.height * scale)
        requestID = thumbnailStore.requestPreviewImage(for: libraryIdentifier, targetSize: targetSize) { renderedImage in
            image = renderedImage
        }
    }
}

/// UIKit scroll view wrapper that provides pinch-to-zoom for preview images.
private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage

    /// Builds the scroll view and embedded image view used for zooming.
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        return scrollView
    }

    /// Pushes updated image content into the existing zoomable scroll view.
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.imageView?.frame = scrollView.bounds
    }

    /// Creates the UIKit coordinator used for zoom delegation.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Delegates zoom behavior back to the embedded image view.
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        /// Returns the view that should scale while pinch-zooming.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}

/// Main editor sheet for one asset, combining overview, actions, rule editing, and tag editing.
private struct AssetEditorSheet: View {
    let asset: MediaAsset
    let tagLibrary: [TagLibraryEntry]
    let tagSuggestions: () async -> [AutoTagSuggestion]
    let onRefresh: () async -> Void
    let onToggleProtection: () async -> Void
    let onToggleScreenshotLike: () async -> Void
    let onApplyRetentionRule: (ScreenshotRetentionRule) async -> Void
    let onAddTag: (String, String) async -> Void
    let onAddTags: ([TagLibraryEntry]) async -> Void
    let onRemoveTag: (MediaTag) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quickTagName = ""
    @State private var autoSuggestions: [AutoTagSuggestion] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(asset.title)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 8) {
                            AssetBadge(
                                title: asset.kind.displayName,
                                systemImage: asset.isScreenshot ? "camera.viewfinder" : "photo"
                            )

                            if asset.isProtectedFromCleanup {
                                AssetBadge(title: L10n.text("asset.protected", fallback: "Protected"), systemImage: "bookmark.fill")
                            }
                        }

                        if let expirationDate = asset.expirationDate {
                            Text(L10n.text("asset.expires_on", fallback: "Expires %@", expirationDate.formatted(date: .abbreviated, time: .omitted)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(L10n.text("asset.overview", fallback: "Overview")) {
                    LabeledContent(L10n.text("asset.created", fallback: "Created"), value: asset.createdAt.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent(L10n.text("asset.added", fallback: "Added"), value: asset.addedAt.formatted(date: .abbreviated, time: .omitted))
                    if let rule = asset.screenshotRule {
                        LabeledContent(L10n.text("asset.cleanup_rule", fallback: "Cleanup Rule"), value: rule.displayName)
                        LabeledContent(L10n.text("asset.anchor", fallback: "Anchor"), value: rule.anchor == .creationDate ? L10n.text("asset.anchor_created_date", fallback: "Created Date") : L10n.text("asset.anchor_added_date", fallback: "Added Date"))
                    }
                }

                Section(L10n.text("asset.actions", fallback: "Actions")) {
                    if asset.isScreenshot {
                        Button(asset.isProtectedFromCleanup ? L10n.text("asset.remove_protection", fallback: "Remove Protection") : L10n.text("asset.protect_from_cleanup", fallback: "Protect from Cleanup")) {
                            Task {
                                await onToggleProtection()
                                await onRefresh()
                            }
                        }
                    }

                    if asset.kind == .photo || asset.kind == .importedScreenshotLike {
                        Button(asset.kind == .importedScreenshotLike ? L10n.text("asset.back_to_photo", fallback: "Back to Photo") : L10n.text("asset.treat_as_screenshot", fallback: "Treat as Screenshot")) {
                            Task {
                                await onToggleScreenshotLike()
                                await onRefresh()
                            }
                        }
                    }
                }

                Section(L10n.text("tags.manager_title", fallback: "Tag Manager")) {
                    QuickTagEditorSection(
                        asset: asset,
                        availableEntries: tagLibrary,
                        autoSuggestions: autoSuggestions,
                        quickTagName: $quickTagName,
                        onRefresh: onRefresh,
                        onAddTag: onAddTag,
                        onAddTags: onAddTags,
                        onRemoveTag: onRemoveTag
                    )
                }

                Section(L10n.text("asset.editors", fallback: "Editors")) {
                    if asset.isScreenshot {
                        NavigationLink {
                            AssetRuleEditorView(
                                asset: asset,
                                onRefresh: onRefresh,
                                onApplyRetentionRule: onApplyRetentionRule
                            )
                        } label: {
                            EditorRow(
                                title: L10n.text("rule.editor_title", fallback: "Rule Editor"),
                                subtitle: asset.screenshotRule?.displayName ?? L10n.text("rule.no_rule", fallback: "No rule")
                            )
                        }
                    }

                    NavigationLink {
                        AssetTagManagerView(
                            asset: asset,
                            tagLibrary: tagLibrary,
                            onRefresh: onRefresh,
                            onAddTag: onAddTag,
                            onAddTags: onAddTags,
                            onRemoveTag: onRemoveTag
                        )
                    } label: {
                        EditorRow(
                            title: L10n.text("tags.manager_title", fallback: "Tag Manager"),
                            subtitle: asset.tags.isEmpty ? L10n.text("tags.none", fallback: "No tags") : L10n.text("tags.count.plural", fallback: "%lld tags", asset.tags.count)
                        )
                    }
                }
            }
            .navigationTitle(L10n.text("asset.manage_title", fallback: "Manage Asset"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.done", fallback: "Done")) {
                        dismiss()
                    }
                }
            }
            .task(id: asset.id) {
                autoSuggestions = await tagSuggestions()
            }
        }
    }
}

/// Dedicated editor for screenshot retention rules.
private struct AssetRuleEditorView: View {
    let asset: MediaAsset
    let onRefresh: () async -> Void
    let onApplyRetentionRule: (ScreenshotRetentionRule) async -> Void

    @State private var customMinuteCount = "1"
    @State private var selectedAnchor: ScreenshotRetentionRule.Anchor = .creationDate

    var body: some View {
        Form {
            Section(L10n.text("rule.current_rule", fallback: "Current Rule")) {
                if let rule = asset.screenshotRule {
                    LabeledContent(L10n.text("rule.mode", fallback: "Mode"), value: rule.displayName)
                    LabeledContent(L10n.text("asset.anchor", fallback: "Anchor"), value: rule.anchor == .creationDate ? L10n.text("asset.anchor_created_date", fallback: "Created Date") : L10n.text("asset.anchor_added_date", fallback: "Added Date"))
                    if let expirationDate = asset.expirationDate {
                        LabeledContent(L10n.text("asset.expires", fallback: "Expires"), value: expirationDate.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    Text(L10n.text("rule.none_set", fallback: "No cleanup rule is set."))
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.text("asset.anchor", fallback: "Anchor")) {
                Picker(L10n.text("rule.start_from", fallback: "Start From"), selection: $selectedAnchor) {
                    Text(L10n.text("asset.created", fallback: "Created")).tag(ScreenshotRetentionRule.Anchor.creationDate)
                    Text(L10n.text("asset.added", fallback: "Added")).tag(ScreenshotRetentionRule.Anchor.addedDate)
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.text("rule.presets", fallback: "Presets")) {
                ForEach(ScreenshotRetentionRule.RetentionPreset.allCases) { preset in
                    Button(preset.displayName) {
                        Task {
                            await onApplyRetentionRule(
                                ScreenshotRetentionRule(mode: .preset(preset), anchor: selectedAnchor)
                            )
                            await onRefresh()
                        }
                    }
                }
            }

            Section(L10n.text("rule.custom_minutes", fallback: "Custom Minutes")) {
                HStack {
                    TextField(L10n.text("rule.minutes", fallback: "Minutes"), text: $customMinuteCount)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(L10n.text("common.apply", fallback: "Apply")) {
                        guard let minutes = Int(customMinuteCount), minutes >= 1 else {
                            return
                        }

                        Task {
                            await onApplyRetentionRule(
                                ScreenshotRetentionRule(mode: .customMinutes(minutes), anchor: selectedAnchor)
                            )
                            await onRefresh()
                        }
                    }
                }
                Text(L10n.text("rule.minimum_notice", fallback: "Minimum is 1 minute so you can verify auto-cleanup quickly during testing."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.text("rule.editor_title", fallback: "Rule Editor"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedAnchor = asset.screenshotRule?.anchor ?? .creationDate
            if case let .customMinutes(minutes)? = asset.screenshotRule?.mode {
                customMinuteCount = String(minutes)
            }
        }
    }
}

/// Full tag-management screen for one asset, including batch application from the global tag library.
private struct AssetTagManagerView: View {
    let asset: MediaAsset
    let tagLibrary: [TagLibraryEntry]
    let onRefresh: () async -> Void
    let onAddTag: (String, String) async -> Void
    let onAddTags: ([TagLibraryEntry]) async -> Void
    let onRemoveTag: (MediaTag) async -> Void

    @State private var draftTagName = ""
    @State private var selectedBatchTagIDs = Set<String>()

    var body: some View {
        Form {
            Section(L10n.text("tags.current_tags", fallback: "Current Tags")) {
                if asset.tags.isEmpty {
                    Text(L10n.text("tags.none_yet", fallback: "No tags yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(asset.tags) { tag in
                        HStack {
                            TagPill(tag: tag)
                            Spacer()
                            Button(L10n.text("common.remove", fallback: "Remove")) {
                                Task {
                                    await onRemoveTag(tag)
                                    await onRefresh()
                                }
                            }
                            .font(.footnote)
                        }
                    }
                }
            }

            Section(L10n.text("tags.global_library", fallback: "Global Tag Library")) {
                if suggestionEntries.isEmpty {
                    Text(L10n.text("tags.no_saved_suggestions", fallback: "No saved tag suggestions yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suggestionEntries) { entry in
                        Button {
                            toggleBatchSelection(entry)
                        } label: {
                            HStack {
                                TagUsageRow(
                                    name: entry.name,
                                    colorHex: entry.colorHex,
                                    usageCount: entry.usageCount
                                )
                                Spacer()
                                Image(systemName: selectedBatchTagIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedBatchTagIDs.contains(entry.id) ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button(L10n.text("tags.apply_selected", fallback: "Apply Selected Tags")) {
                        let entries = suggestionEntries.filter { selectedBatchTagIDs.contains($0.id) }
                        Task {
                            await onAddTags(entries)
                            selectedBatchTagIDs.removeAll()
                            await onRefresh()
                        }
                    }
                    .disabled(selectedBatchTagIDs.isEmpty)
                }
            }

            Section(L10n.text("tags.create_tag", fallback: "Create Tag")) {
                TextField(L10n.text("tags.new_tag", fallback: "New tag"), text: $draftTagName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TagColorPreset.allCases) { preset in
                            Button {
                                Task {
                                    await onAddTag(draftTagName, preset.hex)
                                    draftTagName = ""
                                    await onRefresh()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: preset.hex) ?? .accentColor)
                                        .frame(width: 8, height: 8)
                                    Text(preset.name)
                                        .font(.footnote)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(draftTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("tags.manager_title", fallback: "Tag Manager"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Filters out tags the asset already has so the suggestion list only shows addable entries.
    private var suggestionEntries: [TagLibraryEntry] {
        let currentNames = Set(asset.tags.map(\.normalizedName))
        return tagLibrary.filter { !currentNames.contains($0.normalizedName) }
    }

    /// Toggles whether a saved tag is included in the current batch-apply selection.
    private func toggleBatchSelection(_ entry: TagLibraryEntry) {
        if selectedBatchTagIDs.contains(entry.id) {
            selectedBatchTagIDs.remove(entry.id)
        } else {
            selectedBatchTagIDs.insert(entry.id)
        }
    }
}

/// Inline tag editor section used by the main asset editor sheet.
private struct QuickTagEditorSection: View {
    let asset: MediaAsset
    let availableEntries: [TagLibraryEntry]
    let autoSuggestions: [AutoTagSuggestion]
    @Binding var quickTagName: String
    let onRefresh: () async -> Void
    let onAddTag: (String, String) async -> Void
    let onAddTags: ([TagLibraryEntry]) async -> Void
    let onRemoveTag: (MediaTag) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !asset.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("tags.current_tags", fallback: "Current Tags"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(asset.tags) { tag in
                                Button {
                                    Task {
                                        await onRemoveTag(tag)
                                        await onRefresh()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        TagPill(tag: tag)
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !suggestedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("tags.global_library", fallback: "Global Tag Library"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedEntries) { entry in
                                Button {
                                    Task {
                                        await onAddTags([entry])
                                        await onRefresh()
                                    }
                                } label: {
                                    OrbitTagCapsule(
                                        title: entry.name,
                                        colorHex: entry.colorHex,
                                        symbolName: "tag.fill",
                                        count: 0,
                                        isSelected: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !autoSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("tags.auto_suggestions", fallback: "Suggested Tags"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(autoSuggestions) { suggestion in
                                Button {
                                    Task {
                                        await onAddTag(suggestion.name, suggestion.colorHex)
                                        await onRefresh()
                                    }
                                } label: {
                                    OrbitTagCapsule(
                                        title: suggestion.name,
                                        colorHex: suggestion.colorHex,
                                        symbolName: "sparkles",
                                        count: 0,
                                        isSelected: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(L10n.text("tags.new_tag", fallback: "New tag"), text: $quickTagName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(L10n.text("common.add", fallback: "Add")) {
                    let pending = quickTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await onAddTag(pending, TagColorPreset.ocean.hex)
                        quickTagName = ""
                        await onRefresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    /// Filters the global tag entries down to tags the asset does not already use.
    private var suggestedEntries: [TagLibraryEntry] {
        let currentNames = Set(asset.tags.map(\.normalizedName))
        return availableEntries.filter { !currentNames.contains($0.normalizedName) }
    }
}

/// Formats a localized singular or plural photo-count label.
private func photoCountLabel(for count: Int) -> String {
    if count == 1 {
        return L10n.text("photos.count.singular", fallback: "1 photo")
    }

    return L10n.text("photos.count.plural", fallback: "%lld photos", count)
}

private struct EditorRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AssetBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PhotoCountBadge: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TileBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(6)
            .background(Color.black.opacity(0.32))
            .clipShape(Circle())
    }
}

private struct TagPill: View {
    let tag: MediaTag

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .accentColor)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

private struct CompactTagPill: View {
    let tag: MediaTag

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .accentColor)
                .frame(width: 6, height: 6)
            Text(tag.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.25))
        .clipShape(Capsule())
    }
}

private struct TagUsageRow: View {
    let name: String
    let colorHex: String
    let usageCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: colorHex) ?? .accentColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(usageCount == 1 ? L10n.text("tags.used_by_one", fallback: "Used by 1 asset") : L10n.text("tags.used_by_many", fallback: "Used by %lld assets", usageCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum TagColorPreset: CaseIterable, Identifiable {
    case ember
    case moss
    case ocean
    case plum
    case sand

    var id: String { name }

    var name: String {
        switch self {
        case .ember: L10n.text("tag_color.ember", fallback: "Ember")
        case .moss: L10n.text("tag_color.moss", fallback: "Moss")
        case .ocean: L10n.text("tag_color.ocean", fallback: "Ocean")
        case .plum: L10n.text("tag_color.plum", fallback: "Plum")
        case .sand: L10n.text("tag_color.sand", fallback: "Sand")
        }
    }

    var hex: String {
        switch self {
        case .ember: "#C8553D"
        case .moss: "#5F7A61"
        case .ocean: "#3D5A80"
        case .plum: "#6D597A"
        case .sand: "#D4A373"
        }
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
