import Photos
import SwiftUI

struct LibraryHomeView: View {
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?
    @State private var isShowingProfileSheet = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
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

    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }
}

struct CleanupHomeView: View {
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?
    @State private var previewAsset: MediaAsset?
    @State private var reviewIndex = 0

    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
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
                    ScreenshotSlashView(
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
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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

    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }

    private func clampReviewIndex() {
        let count = viewModel.cleanupReviewQueue.count
        if count == 0 {
            reviewIndex = 0
        } else {
            reviewIndex = min(reviewIndex, count - 1)
        }
    }
}

struct TagHomeView: View {
    @State private var viewModel: LibraryHomeViewModel

    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
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

    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }
}

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

private struct ScreenshotSlashView: View {
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
        VStack(spacing: 18) {
            cleanupHeader

            if let asset = currentAsset {
                ScreenshotSlashCard(
                    asset: asset,
                    nextAsset: nextAsset,
                    thumbnailStore: thumbnailStore,
                    progressLabel: progressLabel,
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

    private var currentAsset: MediaAsset? {
        guard assets.indices.contains(currentIndex) else {
            return assets.first
        }

        return assets[currentIndex]
    }

    private var nextAsset: MediaAsset? {
        let nextIndex = currentIndex + 1
        guard assets.indices.contains(nextIndex) else {
            return nil
        }

        return assets[nextIndex]
    }

    private var progressLabel: String {
        guard !assets.isEmpty else {
            return L10n.text("cleanup.zero_left", fallback: "0 left")
        }

        return L10n.text(
            "cleanup.progress_left",
            fallback: "%lld / %lld left",
            currentIndex + 1,
            assets.count
        )
    }

    private var emptyStateMessage: String {
        switch reviewMode {
        case .screenshots:
            L10n.text("cleanup.empty_screenshots", fallback: "No screenshots are waiting for review.")
        case .allPhotos:
            L10n.text("cleanup.empty_photos", fallback: "No photos are waiting for review.")
        }
    }

    private var cleanupHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            cleanupModePicker

            Text(L10n.text("cleanup.preview_hint", fallback: "Tap the photo to preview the original."))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("library.refreshing", fallback: "Refreshing library"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cleanupModePicker: some View {
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
        .background(.thinMaterial, in: Capsule())
    }

    private func advanceAfterAction() {
        if assets.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, max(assets.count - 1, 0))
        }
    }
}

private struct ScreenshotSlashCard: View {
    let asset: MediaAsset
    let nextAsset: MediaAsset?
    let thumbnailStore: PhotoLibraryThumbnailStore
    let progressLabel: String
    let onPreview: () -> Void
    let onOpenDetail: () -> Void
    let onKeep: () async -> Void
    let onDelete: () async -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isActing = false

    var body: some View {
        VStack(spacing: 18) {
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
                        slashIndicator
                            .padding(.top, 64)
                            .padding(.leading, 18)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if dragOffset.width < -24 {
                        slashIndicator
                            .padding(.top, 64)
                            .padding(.trailing, 18)
                    }
                }
            }
            .offset(x: dragOffset.width, y: 0)
            .rotationEffect(.degrees(Double(dragOffset.width / 18)))
            .shadow(color: Color.black.opacity(0.14), radius: 30, y: 22)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !isActing else {
                            return
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isActing else {
                            return
                        }

                        let horizontal = value.translation.width
                        if horizontal > 120 {
                            Task { await performKeep() }
                        } else if horizontal < -120 {
                            Task { await performDelete() }
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )

            HStack(spacing: 16) {
                ActionOrbButton(
                    title: L10n.text("cleanup.queue", fallback: "Queue"),
                    systemImage: "trash.fill",
                    tint: .red,
                    material: .regularMaterial,
                    isEnabled: !isActing
                ) {
                    Task { await performDelete() }
                }

                ActionOrbButton(
                    title: L10n.text("cleanup.inspect", fallback: "Inspect"),
                    systemImage: "slider.horizontal.3",
                    tint: .primary,
                    material: .ultraThinMaterial,
                    isEnabled: !isActing,
                    action: onOpenDetail
                )

                ActionOrbButton(
                    title: L10n.text("cleanup.keep", fallback: "Keep"),
                    systemImage: "bookmark.fill",
                    tint: .green,
                    material: .regularMaterial,
                    isEnabled: !isActing
                ) {
                    Task { await performKeep() }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var slashIndicator: some View {
        if dragOffset.width > 24 {
            swipeStamp(
                title: L10n.text("cleanup.keep_upper", fallback: "KEEP"),
                systemImage: "bookmark.fill",
                tint: .green,
                rotation: -8
            )
        } else if dragOffset.width < -24 {
            swipeStamp(
                title: L10n.text("cleanup.delete_upper", fallback: "DELETE"),
                systemImage: "trash.fill",
                tint: .red,
                rotation: 8
            )
        }
    }

    private func swipeStamp(
        title: String,
        systemImage: String,
        tint: Color,
        rotation: Double
    ) -> some View {
        let emphasis = min(abs(dragOffset.width) / 140, 1)

        return Label(title, systemImage: systemImage)
            .font(.caption.weight(.black))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(tint.opacity(0.5), lineWidth: 1.5)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.16),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .shadow(color: tint.opacity(0.18), radius: 14, y: 8)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(0.92 + (0.08 * emphasis))
    }

    private func performKeep() async {
        guard !isActing else {
            return
        }

        isActing = true
        await onKeep()
        dragOffset = .zero
        isActing = false
    }

    private func performDelete() async {
        guard !isActing else {
            return
        }

        isActing = true
        await onDelete()
        dragOffset = .zero
        isActing = false
    }
}

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
                VStack(alignment: .leading, spacing: 8) {
                    Text(asset.title)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        if let expirationDate = asset.expirationDate {
                            Label(
                                L10n.text("asset.expires_on", fallback: "Expires %@", expirationDate.formatted(date: .abbreviated, time: .omitted)),
                                systemImage: "clock"
                            )
                        }
                        if !asset.tags.isEmpty {
                            Label(tagLabel, systemImage: "tag")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(22)
            }
    }
}

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

    private var statusLine: String {
        if pendingCount >= pendingLimit {
            return L10n.text("cleanup.queue_full", fallback: "Queue is full. Delete or undo before adding more screenshots.")
        }

        if let previewAsset {
            return L10n.text("cleanup.latest_queued", fallback: "Latest queued: %@", previewAsset.title)
        }

        return L10n.text("cleanup.review_or_delete_batch", fallback: "Review more screenshots or delete this batch now.")
    }

    private var queueCountLabel: String {
        if pendingCount == 1 {
            return L10n.text("cleanup.queue_count_singular", fallback: "1 %@ queued", itemLabel)
        }

        return L10n.text("cleanup.queue_count_plural", fallback: "%lld %@s queued", pendingCount, itemLabel)
    }

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
    let material: Material
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 58, height: 58)
                    .background(material, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    }

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
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

private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage

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

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.imageView?.frame = scrollView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}

private struct AssetEditorSheet: View {
    let asset: MediaAsset
    let tagLibrary: [TagLibraryEntry]
    let onRefresh: () async -> Void
    let onToggleProtection: () async -> Void
    let onToggleScreenshotLike: () async -> Void
    let onApplyRetentionRule: (ScreenshotRetentionRule) async -> Void
    let onAddTag: (String, String) async -> Void
    let onAddTags: ([TagLibraryEntry]) async -> Void
    let onRemoveTag: (MediaTag) async -> Void

    @Environment(\.dismiss) private var dismiss

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
        }
    }
}

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

    private var suggestionEntries: [TagLibraryEntry] {
        let currentNames = Set(asset.tags.map(\.normalizedName))
        return tagLibrary.filter { !currentNames.contains($0.normalizedName) }
    }

    private func toggleBatchSelection(_ entry: TagLibraryEntry) {
        if selectedBatchTagIDs.contains(entry.id) {
            selectedBatchTagIDs.remove(entry.id)
        } else {
            selectedBatchTagIDs.insert(entry.id)
        }
    }
}

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
