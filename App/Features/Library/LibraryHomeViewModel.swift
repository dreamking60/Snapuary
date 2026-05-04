import Foundation
import Observation

enum LibraryCollection: String, CaseIterable, Hashable, Identifiable {
    case all
    case screenshots
    case photos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .screenshots:
            "Screenshots"
        case .photos:
            "Photos"
        }
    }
}

struct TagLibraryEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let normalizedName: String
    let colorHex: String
    let usageCount: Int
}

@Observable
final class LibraryHomeViewModel {
    private enum LoadScope {
        case browsing
        case complete
    }

    private let photoLibraryService: PhotoLibraryServing
    let thumbnailStore: PhotoLibraryThumbnailStore
    private let metadataService: MediaAssetMetadataServing
    private let expirationService: ScreenshotExpirationServing
    private let cleanupSchedulingService: CleanupSchedulingServing
    private let browsingPageSize = 120
    private let fullLoadPageSize = 240

    private(set) var assets: [MediaAsset] = []
    private(set) var cleanupSummary = CleanupSummary(
        totalScreenshotCount: 0,
        autoManagedCount: 0,
        expiringSoonCount: 0,
        protectedCount: 0,
        readyToCleanCount: 0
    )
    private(set) var cleanupCandidates: [MediaAsset] = []
    private(set) var lastCleanupResult: CleanupExecutionResult?
    private(set) var cleanupReminderStatus: CleanupNotificationAuthorizationStatus = .notDetermined
    private(set) var nextCleanupReminder: CleanupReminderSchedule?
    private(set) var authorizationStatus: PhotoLibraryAuthorizationStatus
    private(set) var authorizationErrorMessage: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var loadedAssetCount = 0
    private(set) var totalAssetCount = 0
    private(set) var isRunningCleanup = false
    private(set) var isSchedulingReminder = false
    private(set) var shouldPromptForCleanup = false
    var searchText = ""
    var selectedTag: MediaTag?
    var selectedCollection: LibraryCollection = .all
    private var hasPromptedForCleanupThisSession = false
    private var hasLoadedCompleteLibrary = false
    private var currentOffset = 0

    init(
        photoLibraryService: PhotoLibraryServing,
        thumbnailStore: PhotoLibraryThumbnailStore = .empty,
        metadataService: MediaAssetMetadataServing,
        expirationService: ScreenshotExpirationServing,
        cleanupSchedulingService: CleanupSchedulingServing
    ) {
        self.photoLibraryService = photoLibraryService
        self.thumbnailStore = thumbnailStore
        self.metadataService = metadataService
        self.expirationService = expirationService
        self.cleanupSchedulingService = cleanupSchedulingService
        self.authorizationStatus = photoLibraryService.authorizationStatus()
    }

    var loadProgress: Double {
        guard totalAssetCount > 0 else {
            return 0
        }

        return min(Double(loadedAssetCount) / Double(totalAssetCount), 1)
    }

    var hasMoreAssetsToLoad: Bool {
        loadedAssetCount < totalAssetCount
    }

    func loadForBrowsing() async {
        await load(scope: .browsing)
    }

    func load() async {
        await load(scope: .complete)
    }

    func loadMoreIfNeeded(visibleIndex _: Int) async {
        guard hasMoreAssetsToLoad,
              !isLoading,
              !isLoadingMore else {
            return
        }

        await loadNextPage(pageSize: browsingPageSize)
    }

    func ensureFullLibraryLoaded() async {
        if assets.isEmpty || totalAssetCount == 0 {
            await load()
            return
        }

        guard !hasLoadedCompleteLibrary else {
            return
        }

        while hasMoreAssetsToLoad {
            await loadNextPage(pageSize: fullLoadPageSize)
        }

        hasLoadedCompleteLibrary = true
    }

    func requestPhotoLibraryAccessForBrowsing() async {
        authorizationStatus = await photoLibraryService.requestAuthorization()
        if authorizationStatus.canReadAssets {
            await loadForBrowsing()
        } else {
            authorizationErrorMessage = authorizationMessage(for: authorizationStatus)
        }
    }

    func requestPhotoLibraryAccess() async {
        authorizationStatus = await photoLibraryService.requestAuthorization()
        if authorizationStatus.canReadAssets {
            await load()
        } else {
            authorizationErrorMessage = authorizationMessage(for: authorizationStatus)
        }
    }

    var availableTags: [MediaTag] {
        let tags = assets.flatMap(\.tags)
        var seen = Set<String>()
        return tags
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { seen.insert($0.normalizedName).inserted }
    }

    var tagLibrary: [TagLibraryEntry] {
        var summary: [String: (name: String, colorHex: String, usageCount: Int)] = [:]

        for tag in assets.flatMap(\.tags) {
            let key = tag.normalizedName
            if let current = summary[key] {
                summary[key] = (current.name, current.colorHex, current.usageCount + 1)
            } else {
                summary[key] = (tag.name, tag.colorHex, 1)
            }
        }

        return summary
            .map { key, value in
                TagLibraryEntry(
                    id: key,
                    name: value.name,
                    normalizedName: key,
                    colorHex: value.colorHex,
                    usageCount: value.usageCount
                )
            }
            .sorted {
                if $0.usageCount == $1.usageCount {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.usageCount > $1.usageCount
            }
    }

    var filteredAssets: [MediaAsset] {
        assets
            .filter { matchesSelectedTag(asset: $0) }
            .filter { matchesSearchText(asset: $0) }
    }

    var screenshotAssets: [MediaAsset] {
        filteredAssets.filter(\.isScreenshot)
    }

    var nonScreenshotAssets: [MediaAsset] {
        filteredAssets.filter { !$0.isScreenshot }
    }

    var visibleAssets: [MediaAsset] {
        switch selectedCollection {
        case .all:
            filteredAssets
        case .screenshots:
            screenshotAssets
        case .photos:
            nonScreenshotAssets
        }
    }

    var untaggedScreenshotAssets: [MediaAsset] {
        screenshotAssets.filter { $0.tags.isEmpty && !$0.isProtectedFromCleanup }
    }

    var taggedScreenshotAssets: [MediaAsset] {
        screenshotAssets.filter { !$0.tags.isEmpty }
    }

    func assets(for tagEntry: TagLibraryEntry) -> [MediaAsset] {
        assets.filter { asset in
            asset.tags.contains { $0.normalizedName == tagEntry.normalizedName }
        }
    }

    func toggleTag(_ tag: MediaTag) {
        if selectedTag?.normalizedName == tag.normalizedName {
            selectedTag = nil
        } else {
            selectedTag = tag
        }
    }

    func clearFilters() {
        searchText = ""
        selectedTag = nil
    }

    func toggleProtection(for asset: MediaAsset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        assets[index].isProtectedFromCleanup.toggle()
        await persistMetadata(for: assets[index])
        recalculateCleanupState()
    }

    func toggleImportedScreenshotLike(for asset: MediaAsset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        if assets[index].kind == .photo {
            assets[index].kind = .importedScreenshotLike
            assets[index].screenshotRule = ScreenshotRetentionRule(
                mode: .preset(.oneMonth),
                anchor: .addedDate
            )
        } else if assets[index].kind == .importedScreenshotLike {
            assets[index].kind = .photo
            assets[index].screenshotRule = nil
            assets[index].isProtectedFromCleanup = false
        }

        await persistMetadata(for: assets[index])
        recalculateCleanupState()
    }

    func applyRetentionRule(_ rule: ScreenshotRetentionRule, to asset: MediaAsset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        assets[index].screenshotRule = rule
        await persistMetadata(for: assets[index])
        recalculateCleanupState()
    }

    func addTag(name: String, colorHex: String, to asset: MediaAsset) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        let normalizedName = trimmedName.lowercased()
        if assets[index].tags.contains(where: { $0.normalizedName == normalizedName }) {
            return
        }

        assets[index].tags.append(
            MediaTag(id: UUID(), name: trimmedName, colorHex: colorHex)
        )
        await persistMetadata(for: assets[index])
    }

    func addTags(_ tags: [TagLibraryEntry], to asset: MediaAsset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        let existingNames = Set(assets[index].tags.map(\.normalizedName))
        let newTags = tags
            .filter { !existingNames.contains($0.normalizedName) }
            .map { entry in
                MediaTag(id: UUID(), name: entry.name, colorHex: entry.colorHex)
            }

        guard !newTags.isEmpty else {
            return
        }

        assets[index].tags.append(contentsOf: newTags)
        await persistMetadata(for: assets[index])
    }

    func removeTag(_ tag: MediaTag, from asset: MediaAsset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        assets[index].tags.removeAll { $0.normalizedName == tag.normalizedName }
        if selectedTag?.normalizedName == tag.normalizedName {
            selectedTag = nil
        }
        await persistMetadata(for: assets[index])
    }

    func renameTag(_ tagEntry: TagLibraryEntry, to newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let newNormalizedName = trimmedName.lowercased()
        let oldNormalizedName = tagEntry.normalizedName
        guard newNormalizedName != oldNormalizedName else {
            return
        }

        var updatedIndexes: [Int] = []

        for index in assets.indices {
            guard assets[index].tags.contains(where: { $0.normalizedName == oldNormalizedName }) else {
                continue
            }

            let alreadyHasRenamedTag = assets[index].tags.contains(where: { $0.normalizedName == newNormalizedName })
            var rewrittenTags: [MediaTag] = []
            rewrittenTags.reserveCapacity(assets[index].tags.count)

            for tag in assets[index].tags {
                guard tag.normalizedName == oldNormalizedName else {
                    rewrittenTags.append(tag)
                    continue
                }

                if alreadyHasRenamedTag {
                    continue
                }

                rewrittenTags.append(
                    MediaTag(
                        id: tag.id,
                        name: trimmedName,
                        colorHex: tag.colorHex
                    )
                )
            }

            assets[index].tags = rewrittenTags
            updatedIndexes.append(index)
        }

        if selectedTag?.normalizedName == oldNormalizedName {
            selectedTag = assets
                .flatMap(\.tags)
                .first(where: { $0.normalizedName == newNormalizedName })
        }

        for index in updatedIndexes {
            await persistMetadata(for: assets[index])
        }
    }

    func deleteTag(_ tagEntry: TagLibraryEntry) async {
        let normalizedName = tagEntry.normalizedName
        var updatedIndexes: [Int] = []

        for index in assets.indices {
            let originalCount = assets[index].tags.count
            assets[index].tags.removeAll { $0.normalizedName == normalizedName }
            if assets[index].tags.count != originalCount {
                updatedIndexes.append(index)
            }
        }

        if selectedTag?.normalizedName == normalizedName {
            selectedTag = nil
        }

        for index in updatedIndexes {
            await persistMetadata(for: assets[index])
        }
    }

    func mergeTag(_ source: TagLibraryEntry, into destination: TagLibraryEntry) async {
        guard source.normalizedName != destination.normalizedName else {
            return
        }

        var updatedIndexes: [Int] = []

        for index in assets.indices {
            let hasSource = assets[index].tags.contains(where: { $0.normalizedName == source.normalizedName })
            guard hasSource else {
                continue
            }

            let hasDestination = assets[index].tags.contains(where: { $0.normalizedName == destination.normalizedName })
            var rewrittenTags: [MediaTag] = []
            rewrittenTags.reserveCapacity(assets[index].tags.count)

            for tag in assets[index].tags {
                if tag.normalizedName == source.normalizedName {
                    if !hasDestination {
                        rewrittenTags.append(
                            MediaTag(
                                id: tag.id,
                                name: destination.name,
                                colorHex: destination.colorHex
                            )
                        )
                    }
                } else {
                    rewrittenTags.append(tag)
                }
            }

            assets[index].tags = rewrittenTags
            updatedIndexes.append(index)
        }

        if selectedTag?.normalizedName == source.normalizedName {
            selectedTag = assets
                .flatMap(\.tags)
                .first(where: { $0.normalizedName == destination.normalizedName })
        }

        for index in updatedIndexes {
            await persistMetadata(for: assets[index])
        }
    }

    func runCleanupNow() async {
        guard !isRunningCleanup else {
            return
        }

        shouldPromptForCleanup = false

        let candidates = expirationService.cleanupCandidates(from: assets, now: .now)
        guard !candidates.isEmpty else {
            lastCleanupResult = CleanupExecutionResult(deletedCount: 0, deletedAssetTitles: [])
            return
        }

        let identifiers = candidates.compactMap(\.libraryIdentifier)
        guard !identifiers.isEmpty else {
            return
        }

        isRunningCleanup = true
        defer { isRunningCleanup = false }

        do {
            try await photoLibraryService.deleteAssets(withLocalIdentifiers: identifiers)
            try await metadataService.removeMetadata(for: identifiers)
            lastCleanupResult = CleanupExecutionResult(
                deletedCount: candidates.count,
                deletedAssetTitles: candidates.map(\.title)
            )
            await load()
            if cleanupReminderStatus.canSchedule {
                await scheduleNextCleanupReminder()
            }
        } catch {
            authorizationErrorMessage = "Cleanup failed while deleting expired screenshots."
        }
    }

    func dismissCleanupPrompt() {
        shouldPromptForCleanup = false
        hasPromptedForCleanupThisSession = true
    }

    var cleanupPromptTitle: String {
        "Ready to Clean \(cleanupCandidates.count) Screenshot\(cleanupCandidates.count == 1 ? "" : "s")?"
    }

    var cleanupPromptMessage: String {
        "Snapuary found expired screenshots in the system Photos library. Confirm to delete them now."
    }

    func requestCleanupReminderPermission() async {
        cleanupReminderStatus = await cleanupSchedulingService.requestAuthorization()
        if cleanupReminderStatus.canSchedule {
            await scheduleNextCleanupReminder()
        }
    }

    func scheduleNextCleanupReminder() async {
        guard !isSchedulingReminder else {
            return
        }

        isSchedulingReminder = true
        defer { isSchedulingReminder = false }

        do {
            nextCleanupReminder = try await cleanupSchedulingService.scheduleNextCleanupReminder(
                for: assets,
                now: .now
            )
        } catch {
            authorizationErrorMessage = "Failed to schedule the next cleanup reminder."
        }
    }

    private func authorizationMessage(for status: PhotoLibraryAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            "Snapuary needs access to the photo library to classify screenshots and manage cleanup rules."
        case .denied:
            "Photo access is denied. Enable Photos access in Settings to scan screenshots."
        case .restricted:
            "Photo access is restricted on this device."
        case .limited:
            "Limited photo access is active. Snapuary can only scan the photos you selected."
        case .authorized:
            ""
        }
    }

    private func load(scope: LoadScope) async {
        authorizationStatus = photoLibraryService.authorizationStatus()
        cleanupReminderStatus = await cleanupSchedulingService.authorizationStatus()
        guard authorizationStatus.canReadAssets else {
            resetLibraryState()
            authorizationErrorMessage = authorizationMessage(for: authorizationStatus)
            nextCleanupReminder = nil
            return
        }

        isLoading = true
        resetLibraryState()
        defer { isLoading = false }

        do {
            totalAssetCount = try await photoLibraryService.refreshAssetIndex()
            let initialPageSize = scope == .browsing ? browsingPageSize : fullLoadPageSize
            await loadNextPage(pageSize: initialPageSize)

            if scope == .complete {
                while hasMoreAssetsToLoad {
                    await loadNextPage(pageSize: fullLoadPageSize)
                }
                hasLoadedCompleteLibrary = true
            }

            authorizationErrorMessage = nil
            nextCleanupReminder = nil
        } catch {
            resetLibraryState()
            authorizationErrorMessage = "Failed to load photos from the library."
            nextCleanupReminder = nil
            shouldPromptForCleanup = false
        }
    }

    private func loadNextPage(pageSize: Int) async {
        guard totalAssetCount > 0,
              currentOffset < totalAssetCount else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await photoLibraryService.fetchAssetPage(
                offset: currentOffset,
                limit: pageSize
            )

            guard !page.isEmpty else {
                currentOffset = totalAssetCount
                return
            }

            let chunkSize = min(40, page.count)
            var nextOffset = currentOffset

            for startIndex in stride(from: 0, to: page.count, by: chunkSize) {
                let endIndex = min(startIndex + chunkSize, page.count)
                assets.append(contentsOf: page[startIndex..<endIndex])
                nextOffset += endIndex - startIndex
                loadedAssetCount = assets.count
                cleanupSummary = expirationService.upcomingCleanupSummary(for: assets)
                cleanupCandidates = expirationService.cleanupCandidates(from: assets, now: .now)
                updateCleanupPromptState()

                if endIndex < page.count {
                    await Task.yield()
                }
            }

            currentOffset = nextOffset
            hasLoadedCompleteLibrary = currentOffset >= totalAssetCount
        } catch {
            authorizationErrorMessage = "Failed to load more photos from the library."
        }
    }

    private func matchesSelectedTag(asset: MediaAsset) -> Bool {
        guard let selectedTag else {
            return true
        }

        return asset.tags.contains { $0.normalizedName == selectedTag.normalizedName }
    }

    private func matchesSearchText(asset: MediaAsset) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        return asset.title.localizedCaseInsensitiveContains(query)
            || asset.tags.contains { $0.name.localizedCaseInsensitiveContains(query) }
            || asset.kind.displayName.localizedCaseInsensitiveContains(query)
    }

    private func persistMetadata(for asset: MediaAsset) async {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return
        }

        let record = MediaAssetMetadataRecord(
            isImportedScreenshotLike: asset.kind == .importedScreenshotLike,
            tags: asset.tags,
            screenshotRule: asset.kind == .photo ? nil : asset.screenshotRule,
            isProtectedFromCleanup: asset.isProtectedFromCleanup
        )

        do {
            try await metadataService.saveMetadata(record, for: libraryIdentifier)
            recalculateCleanupState()
        } catch {
            authorizationErrorMessage = "Failed to save local asset metadata."
        }
    }

    private func recalculateCleanupState() {
        loadedAssetCount = assets.count
        cleanupSummary = expirationService.upcomingCleanupSummary(for: assets)
        cleanupCandidates = expirationService.cleanupCandidates(from: assets, now: .now)
        updateCleanupPromptState()
    }

    private func updateCleanupPromptState() {
        guard !hasPromptedForCleanupThisSession else {
            shouldPromptForCleanup = false
            return
        }

        shouldPromptForCleanup = !cleanupCandidates.isEmpty
    }

    private func resetLibraryState() {
        assets = []
        loadedAssetCount = 0
        totalAssetCount = 0
        currentOffset = 0
        hasLoadedCompleteLibrary = false
        cleanupSummary = CleanupSummary(
            totalScreenshotCount: 0,
            autoManagedCount: 0,
            expiringSoonCount: 0,
            protectedCount: 0,
            readyToCleanCount: 0
        )
        cleanupCandidates = []
    }
}
