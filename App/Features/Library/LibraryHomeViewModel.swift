import Foundation
import Observation
import Photos

enum LibraryCollection: String, CaseIterable, Hashable, Identifiable {
    case all
    case screenshots
    case photos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            L10n.text("library.collection.all", fallback: "All")
        case .screenshots:
            L10n.text("library.collection.screenshots", fallback: "Screenshots")
        case .photos:
            L10n.text("library.collection.photos", fallback: "Photos")
        }
    }
}

enum CleanupReviewMode: String, CaseIterable, Hashable, Identifiable {
    case screenshots
    case allPhotos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots:
            L10n.text("cleanup.mode.screenshots", fallback: "Screenshots")
        case .allPhotos:
            L10n.text("cleanup.mode.all_photos", fallback: "All Photos")
        }
    }
}

struct TagLibraryEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let normalizedName: String
    let colorHex: String
    let usageCount: Int
}

@MainActor
@Observable
final class LibraryHomeViewModel {
    private enum LoadScope {
        case browsing
        case complete
    }

    private let photoLibraryService: PhotoLibraryServing
    let thumbnailStore: PhotoLibraryThumbnailStore
    private let assetIndexCache: MediaAssetIndexCaching
    private let metadataService: MediaAssetMetadataServing
    private let tagCatalogStore: TagCatalogServing
    private let orbitLibraryStore: OrbitLibraryServing
    private let expirationService: ScreenshotExpirationServing
    private let cleanupSchedulingService: CleanupSchedulingServing
    private let autoTagSuggestionService: AutoTagSuggesting
    private let browsingPageSize = 120
    private let fullLoadPageSize = 240
    private let reviewDeletionBatchLimit = 50
    private let cleanupDeletionCountKey = "cleanupDeletionCount"

    private(set) var assets: [MediaAsset] = []
    private var cleanupScopedAssets: [MediaAsset] = []
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
    private(set) var totalCleanupDeletedCount: Int
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isSyncingCleanupData = false
    private(set) var cleanupReviewMessage: String?
    private(set) var pendingDeletionAssets: [MediaAsset] = []
    private(set) var orbitCollections: [OrbitCollection] = []
    private(set) var orbitHistory: [OrbitSessionEvent] = []
    private(set) var focusedOrbitID: String?
    private(set) var activeRecipe: OrbitRecipeKind?
    private(set) var loadedAssetCount = 0
    private(set) var totalAssetCount = 0
    private(set) var isRunningCleanup = false
    private(set) var isSchedulingReminder = false
    private(set) var shouldPromptForCleanup = false
    var searchText = ""
    var selectedTag: MediaTag?
    var selectedCollection: LibraryCollection = .all
    var cleanupReviewMode: CleanupReviewMode = .screenshots
    private var hasPromptedForCleanupThisSession = false
    private var hasLoadedCompleteLibrary = false
    private var hasHydratedCache = false
    private var hasHydratedTagSources = false
    private var hasHydratedOrbitLibrary = false
    private var hasSynchronizedBrowsingThisLaunch = false
    private var hasSynchronizedCompleteThisLaunch = false
    private var cachedFingerprint: PhotoLibraryFingerprint?
    private var currentOffset = 0
    private var cleanupSyncTask: Task<Void, Never>?
    private var savedTagCatalogEntries: [TagLibraryEntry] = []
    private var metadataTagEntries: [TagLibraryEntry] = []
    private let photoLibraryChangeObserver = PhotoLibraryChangeObserverProxy()

    init(
        photoLibraryService: PhotoLibraryServing,
        thumbnailStore: PhotoLibraryThumbnailStore = .empty,
        assetIndexCache: MediaAssetIndexCaching,
        metadataService: MediaAssetMetadataServing,
        tagCatalogStore: TagCatalogServing,
        orbitLibraryStore: OrbitLibraryServing,
        expirationService: ScreenshotExpirationServing,
        cleanupSchedulingService: CleanupSchedulingServing,
        autoTagSuggestionService: AutoTagSuggesting = TemplateAutoTagSuggestionService()
    ) {
        self.photoLibraryService = photoLibraryService
        self.thumbnailStore = thumbnailStore
        self.assetIndexCache = assetIndexCache
        self.metadataService = metadataService
        self.tagCatalogStore = tagCatalogStore
        self.orbitLibraryStore = orbitLibraryStore
        self.expirationService = expirationService
        self.cleanupSchedulingService = cleanupSchedulingService
        self.autoTagSuggestionService = autoTagSuggestionService
        self.authorizationStatus = photoLibraryService.authorizationStatus()
        self.totalCleanupDeletedCount = UserDefaults.standard.integer(forKey: cleanupDeletionCountKey)
        photoLibraryChangeObserver.onChange = { [weak self] in
            self?.handleObservedPhotoLibraryChange()
        }
        photoLibraryChangeObserver.register()
    }

    deinit {
        photoLibraryChangeObserver.unregister()
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
        await hydrateCacheIfNeeded()
        guard !hasSynchronizedBrowsingThisLaunch else {
            return
        }
        await load(scope: .browsing)
        hasSynchronizedBrowsingThisLaunch = true
    }

    func load() async {
        await hydrateCacheIfNeeded()
        guard !hasSynchronizedCompleteThisLaunch else {
            return
        }
        await load(scope: .complete)
        hasSynchronizedBrowsingThisLaunch = true
        hasSynchronizedCompleteThisLaunch = true
    }

    func handleAppDidBecomeActive() async {
        let scope: LoadScope = hasLoadedCompleteLibrary ? .complete : .browsing
        await refreshForExternalLibraryChange(scope: scope)
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
        await hydrateCacheIfNeeded()
        if hasLoadedCompleteLibrary && hasSynchronizedCompleteThisLaunch {
            return
        }

        if assets.isEmpty || totalAssetCount == 0 {
            await load()
            return
        }

        if !hasSynchronizedCompleteThisLaunch {
            await load()
        }
    }

    func prepareCleanupData() async {
        await hydrateCacheIfNeeded()
        authorizationStatus = photoLibraryService.authorizationStatus()
        cleanupReminderStatus = await cleanupSchedulingService.authorizationStatus()

        guard authorizationStatus.canReadAssets else {
            authorizationErrorMessage = authorizationMessage(for: authorizationStatus)
            return
        }

        if assets.isEmpty && !isLoading {
            startCleanupSyncIfNeeded()
            return
        }

        if !hasLoadedCompleteLibrary || !hasSynchronizedCompleteThisLaunch {
            startCleanupSyncIfNeeded()
        }
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
        mergeTagEntries([
            derivedTagEntries(from: assets),
            metadataTagEntries,
            savedTagCatalogEntries
        ])
    }

    var orbitAssetCounts: [String: Int] {
        Dictionary(grouping: assets.flatMap { asset in
            asset.orbitIDs.map { ($0, asset.id) }
        }, by: \.0).mapValues { entries in
            Set(entries.map(\.1)).count
        }
    }

    func autoTagSuggestions(for asset: MediaAsset) async -> [AutoTagSuggestion] {
        await autoTagSuggestionService.suggestions(for: asset, within: assets)
    }

    func orbitSuggestions(for asset: MediaAsset) -> [OrbitSuggestion] {
        orbitCollections.compactMap { orbit in
            guard let rule = orbit.autoRule else {
                return nil
            }
            guard let match = smartOrbitMatch(for: asset, rule: rule) else {
                return nil
            }

            return OrbitSuggestion(
                id: "\(orbit.id)-\(asset.id.uuidString)",
                orbitID: orbit.id,
                reason: match.reason,
                confidence: match.confidence
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    var recipeCollections: [OrbitCollection] {
        orbitCollections.filter { $0.recipe != nil }
    }

    var weeklyOrbitRecap: OrbitWeeklyRecap {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let weekEvents = orbitHistory.filter { $0.occurredAt >= weekStart }
        let assigned = weekEvents.filter { $0.action == .assigned }
        let kept = weekEvents.filter { $0.action == .kept }
        let deleted = weekEvents.filter { $0.action == .deleted }
        let orbitNames = Dictionary(grouping: assigned.compactMap(\.orbitID), by: { $0 })
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .compactMap { orbitID, _ in
                orbitCollections.first(where: { $0.id == orbitID })?.name
            }

        return OrbitWeeklyRecap(
            assignedCount: assigned.count,
            keptCount: kept.count,
            deletedCount: deleted.count,
            topOrbitNames: orbitNames,
            weekStart: weekStart
        )
    }

    var clusterReviewGroups: [OrbitReviewCluster] {
        let sortedAssets = cleanupReviewQueue.sorted { $0.createdAt > $1.createdAt }
        guard !sortedAssets.isEmpty else {
            return []
        }

        var groups: [[MediaAsset]] = []
        var currentGroup: [MediaAsset] = [sortedAssets[0]]

        for asset in sortedAssets.dropFirst() {
            guard let previous = currentGroup.last else {
                currentGroup = [asset]
                continue
            }

            let sameDay = Calendar.current.isDate(asset.createdAt, inSameDayAs: previous.createdAt)
            let closeInTime = abs(asset.createdAt.timeIntervalSince(previous.createdAt)) <= 180
            if sameDay && closeInTime {
                currentGroup.append(asset)
            } else {
                if currentGroup.count > 1 {
                    groups.append(currentGroup)
                }
                currentGroup = [asset]
            }
        }

        if currentGroup.count > 1 {
            groups.append(currentGroup)
        }

        return groups.prefix(6).enumerated().map { index, group in
            let title = group.first?.createdAt.formatted(date: .abbreviated, time: .shortened)
                ?? "Cluster \(index + 1)"
            return OrbitReviewCluster(
                id: "cluster-\(index)-\(group.map(\.gridIdentifier).joined(separator: "-"))",
                title: title,
                assetIDs: group.map(\.id),
                count: group.count
            )
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

    var cleanupReviewQueue: [MediaAsset] {
        let baseAssets: [MediaAsset]

        switch cleanupReviewMode {
        case .screenshots:
            baseAssets = cleanupScopedAssets.filter { !$0.isProtectedFromCleanup }
        case .allPhotos:
            baseAssets = assets.filter { !$0.isProtectedFromCleanup }
        }

        guard let activeRecipe else {
            return baseAssets
        }

        return baseAssets.filter { matchesRecipe($0, recipe: activeRecipe) }
    }

    var pendingDeletionCount: Int {
        pendingDeletionAssets.count
    }

    var pendingDeletionLimit: Int {
        reviewDeletionBatchLimit
    }

    var lastPendingDeletionAsset: MediaAsset? {
        pendingDeletionAssets.last
    }

    func assets(for tagEntry: TagLibraryEntry) -> [MediaAsset] {
        assets.filter { asset in
            asset.tags.contains { $0.normalizedName == tagEntry.normalizedName }
        }
    }

    func assets(in orbitID: String?) -> [MediaAsset] {
        guard let orbitID else {
            return []
        }

        return assets
            .filter { $0.orbitIDs.contains(orbitID) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func focusOrbit(_ orbitID: String?) {
        focusedOrbitID = orbitID
    }

    func activateRecipe(_ recipe: OrbitRecipeKind?) {
        activeRecipe = recipe
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

    func protectFromCleanup(_ asset: MediaAsset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        guard !assets[index].isProtectedFromCleanup else {
            return
        }

        assets[index].isProtectedFromCleanup = true
        recordOrbitEvent(
            OrbitSessionEvent(
                assetIdentifier: assets[index].gridIdentifier,
                orbitID: assets[index].orbitIDs.first,
                action: .kept
            )
        )
        await persistMetadata(for: assets[index])
        await persistOrbitLibrary()
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
        await saveTagTemplate(name: trimmedName, colorHex: colorHex)
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
        for entry in tags {
            await saveTagTemplate(name: entry.name, colorHex: entry.colorHex)
        }
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
        await renameSavedTagEntry(from: oldNormalizedName, to: trimmedName, colorHex: tagEntry.colorHex)
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
        await removeSavedTagEntry(normalizedName: normalizedName)
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
        await removeSavedTagEntry(normalizedName: source.normalizedName)
        await saveTagTemplate(name: destination.name, colorHex: destination.colorHex)
    }

    func createTagTemplate(name: String, colorHex: String = "#4F7CAC") async -> TagLibraryEntry? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        await saveTagTemplate(name: trimmedName, colorHex: colorHex)
        return tagLibrary.first(where: { $0.normalizedName == trimmedName.lowercased() })
    }

    func createOrbit(
        name: String,
        colorHex: String = "#4F7CAC",
        symbolName: String = "circle.hexagongrid.fill",
        recipe: OrbitRecipeKind? = nil,
        autoRule: SmartOrbitRule? = nil
    ) async -> OrbitCollection? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        let orbitID = trimmedName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        if orbitCollections.contains(where: { $0.id == orbitID }) {
            return orbitCollections.first(where: { $0.id == orbitID })
        }

        let orbit = OrbitCollection(
            id: orbitID,
            name: trimmedName,
            colorHex: colorHex,
            symbolName: symbolName,
            recipe: recipe,
            autoRule: autoRule
        )
        orbitCollections.append(orbit)
        focusedOrbitID = orbit.id
        await persistOrbitLibrary()
        return orbit
    }

    func assignAsset(_ asset: MediaAsset, to orbitID: String) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            return
        }

        if !assets[index].orbitIDs.contains(orbitID) {
            assets[index].orbitIDs.insert(orbitID, at: 0)
        }
        focusedOrbitID = orbitID

        if let orbitIndex = orbitCollections.firstIndex(where: { $0.id == orbitID }),
           orbitCollections[orbitIndex].coverAssetIdentifier == nil {
            orbitCollections[orbitIndex].coverAssetIdentifier = assets[index].libraryIdentifier
        }

        recordOrbitEvent(
            OrbitSessionEvent(
                assetIdentifier: assets[index].gridIdentifier,
                orbitID: orbitID,
                action: .assigned
            )
        )
        await persistMetadata(for: assets[index])
        await persistOrbitLibrary()
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
            await refreshTagSources()
            lastCleanupResult = CleanupExecutionResult(
                deletedCount: candidates.count,
                deletedAssetTitles: candidates.map(\.title)
            )
            recordCleanupDeletion(count: candidates.count)
            await reloadAfterLibraryMutation(scope: .complete)
            if cleanupReminderStatus.canSchedule {
                await scheduleNextCleanupReminder()
            }
        } catch {
            authorizationErrorMessage = L10n.text("error.cleanup_delete_failed", fallback: "Cleanup failed while deleting expired screenshots.")
        }
    }

    func deleteAssetImmediately(_ asset: MediaAsset) async -> Bool {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return false
        }

        do {
            try await photoLibraryService.deleteAssets(withLocalIdentifiers: [libraryIdentifier])
            try await metadataService.removeMetadata(for: [libraryIdentifier])
            await refreshTagSources()

            if assets.contains(where: { $0.id == asset.id }) {
                removeAssetFromLocalState(asset)
            } else {
                refreshCleanupStateFromScopedAssets()
            }

            recordOrbitEvent(
                OrbitSessionEvent(
                    assetIdentifier: asset.gridIdentifier,
                    orbitID: asset.orbitIDs.first,
                    action: .deleted
                )
            )

            lastCleanupResult = CleanupExecutionResult(
                deletedCount: 1,
                deletedAssetTitles: [asset.title]
            )
            recordCleanupDeletion(count: 1)
            cleanupReviewMessage = nil
            await persistSnapshot()
            await persistOrbitLibrary()
            return true
        } catch {
            cleanupReviewMessage = L10n.text("cleanup.delete_denied_single", fallback: "Deletion was not allowed. The screenshot was kept.")
            return false
        }
    }

    @discardableResult
    func stageAssetForDeletion(_ asset: MediaAsset) -> Bool {
        guard pendingDeletionAssets.count < reviewDeletionBatchLimit else {
            cleanupReviewMessage = L10n.text("cleanup.queue_limit", fallback: "Delete the queued screenshots before adding more than %lld.", reviewDeletionBatchLimit)
            return false
        }

        guard !pendingDeletionAssets.contains(where: { $0.id == asset.id }) else {
            return false
        }

        cleanupReviewMessage = nil
        pendingDeletionAssets.append(asset)
        removeAssetFromLocalState(asset)
        return true
    }

    @discardableResult
    func commitPendingDeletions() async -> Bool {
        guard !pendingDeletionAssets.isEmpty else {
            return false
        }

        let stagedAssets = pendingDeletionAssets
        let identifiers = stagedAssets.compactMap(\.libraryIdentifier)
        guard identifiers.count == stagedAssets.count else {
            restorePendingDeletionAssets(stagedAssets)
            cleanupReviewMessage = L10n.text("cleanup.restore_failed_batch", fallback: "Some queued screenshots could not be deleted and were restored.")
            return false
        }

        isRunningCleanup = true
        defer { isRunningCleanup = false }

        do {
            try await photoLibraryService.deleteAssets(withLocalIdentifiers: identifiers)
            try await metadataService.removeMetadata(for: identifiers)
            await refreshTagSources()

            pendingDeletionAssets.removeAll()
            for asset in stagedAssets {
                recordOrbitEvent(
                    OrbitSessionEvent(
                        assetIdentifier: asset.gridIdentifier,
                        orbitID: asset.orbitIDs.first,
                        action: .deleted
                    )
                )
            }
            lastCleanupResult = CleanupExecutionResult(
                deletedCount: stagedAssets.count,
                deletedAssetTitles: stagedAssets.map(\.title)
            )
            recordCleanupDeletion(count: stagedAssets.count)
            cleanupReviewMessage = nil
            await persistSnapshot()
            await persistOrbitLibrary()
            return true
        } catch {
            restorePendingDeletionAssets(stagedAssets)
            cleanupReviewMessage = L10n.text("cleanup.delete_denied_batch", fallback: "Deletion was not allowed. The queued screenshots were kept.")
            return false
        }
    }

    func undoLastStagedDeletion() {
        guard let pendingDeletionAsset = pendingDeletionAssets.popLast() else {
            return
        }

        insertAssetBackIntoLocalState(pendingDeletionAsset)
        cleanupReviewMessage = nil
    }

    func dismissCleanupReviewMessage() {
        cleanupReviewMessage = nil
    }

    func dismissCleanupPrompt() {
        shouldPromptForCleanup = false
        hasPromptedForCleanupThisSession = true
    }

    var cleanupPromptTitle: String {
        if cleanupCandidates.count == 1 {
            return L10n.text("cleanup.prompt_title_one", fallback: "Ready to Clean 1 Screenshot?")
        }

        return L10n.text("cleanup.prompt_title_many", fallback: "Ready to Clean %lld Screenshots?", cleanupCandidates.count)
    }

    var cleanupPromptMessage: String {
        L10n.text("cleanup.prompt_message", fallback: "Snapuary found expired screenshots in the system Photos library. Confirm to delete them now.")
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
            authorizationErrorMessage = L10n.text("error.schedule_cleanup_reminder", fallback: "Failed to schedule the next cleanup reminder.")
        }
    }

    private func authorizationMessage(for status: PhotoLibraryAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            L10n.text("photo_access.message.not_determined", fallback: "Snapuary needs access to the photo library to classify screenshots and manage cleanup rules.")
        case .denied:
            L10n.text("photo_access.message.denied", fallback: "Photo access is denied. Enable Photos access in Settings to scan screenshots.")
        case .restricted:
            L10n.text("photo_access.message.restricted", fallback: "Photo access is restricted on this device.")
        case .limited:
            L10n.text("photo_access.message.limited", fallback: "Limited photo access is active. Snapuary can only scan the photos you selected.")
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
        defer { isLoading = false }

        do {
            let fingerprint = try await photoLibraryService.libraryFingerprint()
            totalAssetCount = fingerprint.totalCount

            if let cachedFingerprint,
               cachedFingerprint == fingerprint,
               !assets.isEmpty {
                currentOffset = assets.count
                loadedAssetCount = assets.count
                hasLoadedCompleteLibrary = currentOffset >= totalAssetCount

                if scope == .complete && !hasLoadedCompleteLibrary {
                    while hasMoreAssetsToLoad {
                        await loadNextPage(pageSize: fullLoadPageSize)
                    }
                    hasLoadedCompleteLibrary = true
                }

                authorizationErrorMessage = nil
                nextCleanupReminder = nil
                await persistSnapshot()
                return
            }

            resetLibraryState()
            cachedFingerprint = fingerprint
            totalAssetCount = fingerprint.totalCount
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
            await persistSnapshot()
        } catch {
            resetLibraryState()
            authorizationErrorMessage = L10n.text("error.load_photos", fallback: "Failed to load photos from the library.")
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
                let chunkAssets = Array(page[startIndex..<endIndex])
                assets.append(contentsOf: chunkAssets)
                cleanupScopedAssets.append(contentsOf: chunkAssets.filter(\.isScreenshot))
                nextOffset += endIndex - startIndex
                loadedAssetCount = assets.count
                refreshCleanupStateFromScopedAssets()

                if endIndex < page.count {
                    await Task.yield()
                }
            }

            currentOffset = nextOffset
            hasLoadedCompleteLibrary = currentOffset >= totalAssetCount
            await persistSnapshot()
        } catch {
            authorizationErrorMessage = L10n.text("error.load_more_photos", fallback: "Failed to load more photos from the library.")
        }
    }

    private func hydrateCacheIfNeeded() async {
        guard !hasHydratedCache else {
            return
        }

        hasHydratedCache = true
        await hydrateTagSourcesIfNeeded()
        await hydrateOrbitLibraryIfNeeded()

        do {
            guard let snapshot = try await assetIndexCache.loadSnapshot() else {
                return
            }

            cachedFingerprint = snapshot.fingerprint
            assets = snapshot.assets
            cleanupScopedAssets = snapshot.assets.filter(\.isScreenshot)
            totalAssetCount = max(snapshot.fingerprint.totalCount, snapshot.assets.count)
            loadedAssetCount = snapshot.assets.count
            currentOffset = snapshot.assets.count
            hasLoadedCompleteLibrary = snapshot.isComplete && snapshot.assets.count >= snapshot.fingerprint.totalCount
            refreshCleanupStateFromScopedAssets()
        } catch {
            cachedFingerprint = nil
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
            orbitIDs: asset.orbitIDs,
            screenshotRule: asset.kind == .photo ? nil : asset.screenshotRule,
            isProtectedFromCleanup: asset.isProtectedFromCleanup
        )

        do {
            try await metadataService.saveMetadata(record, for: libraryIdentifier)
            await refreshTagSources()
            recalculateCleanupState()
            await persistSnapshot()
        } catch {
            authorizationErrorMessage = L10n.text("error.save_metadata", fallback: "Failed to save local asset metadata.")
        }
    }

    private func recalculateCleanupState() {
        loadedAssetCount = assets.count
        cleanupScopedAssets = assets.filter(\.isScreenshot)
        refreshCleanupStateFromScopedAssets()
    }

    private func updateCleanupPromptState() {
        guard !hasPromptedForCleanupThisSession else {
            shouldPromptForCleanup = false
            return
        }

        shouldPromptForCleanup = !cleanupCandidates.isEmpty
    }

    private func persistSnapshot() async {
        guard let cachedFingerprint else {
            return
        }

        do {
            try await assetIndexCache.saveSnapshot(
                MediaAssetIndexSnapshot(
                    fingerprint: cachedFingerprint,
                    assets: assets,
                    isComplete: hasLoadedCompleteLibrary,
                    updatedAt: .now
                )
            )
        } catch {
            authorizationErrorMessage = L10n.text("error.save_library_index", fallback: "Failed to save the local library index.")
        }
    }

    private func refreshCleanupStateFromScopedAssets() {
        cleanupSummary = expirationService.upcomingCleanupSummary(for: cleanupScopedAssets)
        cleanupCandidates = expirationService.cleanupCandidates(from: cleanupScopedAssets, now: .now)
        updateCleanupPromptState()
    }

    private func hydrateOrbitLibraryIfNeeded() async {
        guard !hasHydratedOrbitLibrary else {
            return
        }

        hasHydratedOrbitLibrary = true
        await refreshOrbitLibrary()
    }

    private func hydrateTagSourcesIfNeeded() async {
        guard !hasHydratedTagSources else {
            return
        }

        hasHydratedTagSources = true
        await refreshTagSources()
    }

    private func refreshTagSources() async {
        do {
            let metadata = try await metadataService.fetchAllMetadata()
            metadataTagEntries = derivedTagEntries(from: metadata.values.flatMap(\.tags))
        } catch {
            metadataTagEntries = []
        }

        do {
            savedTagCatalogEntries = try await tagCatalogStore.loadEntries()
        } catch {
            savedTagCatalogEntries = []
        }
    }

    private func refreshOrbitLibrary() async {
        do {
            let snapshot = try await orbitLibraryStore.loadLibrary()
            orbitCollections = snapshot.collections
            orbitHistory = snapshot.history
        } catch {
            orbitCollections = []
            orbitHistory = []
        }
    }

    private func persistOrbitLibrary() async {
        do {
            try await orbitLibraryStore.saveLibrary(
                OrbitLibrarySnapshot(
                    collections: orbitCollections,
                    history: orbitHistory.suffix(500).map { $0 }
                )
            )
        } catch {
            authorizationErrorMessage = L10n.text("error.save_metadata", fallback: "Failed to save local asset metadata.")
        }
    }

    private func recordOrbitEvent(_ event: OrbitSessionEvent) {
        orbitHistory.append(event)
        if orbitHistory.count > 500 {
            orbitHistory.removeFirst(orbitHistory.count - 500)
        }
    }

    private func saveTagTemplate(name: String, colorHex: String) async {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else {
            return
        }

        let entry = TagLibraryEntry(
            id: normalizedName,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedName: normalizedName,
            colorHex: colorHex,
            usageCount: 0
        )
        savedTagCatalogEntries = mergeTagEntries([savedTagCatalogEntries, [entry]]).map {
            TagLibraryEntry(
                id: $0.normalizedName,
                name: $0.name,
                normalizedName: $0.normalizedName,
                colorHex: $0.colorHex,
                usageCount: 0
            )
        }

        do {
            try await tagCatalogStore.saveEntries(savedTagCatalogEntries)
        } catch {
            authorizationErrorMessage = L10n.text("error.save_metadata", fallback: "Failed to save local asset metadata.")
        }
    }

    private func renameSavedTagEntry(from normalizedName: String, to newName: String, colorHex: String) async {
        savedTagCatalogEntries.removeAll { $0.normalizedName == normalizedName }
        await saveTagTemplate(name: newName, colorHex: colorHex)
    }

    private func removeSavedTagEntry(normalizedName: String) async {
        savedTagCatalogEntries.removeAll { $0.normalizedName == normalizedName }

        do {
            try await tagCatalogStore.saveEntries(savedTagCatalogEntries)
        } catch {
            authorizationErrorMessage = L10n.text("error.save_metadata", fallback: "Failed to save local asset metadata.")
        }
    }

    private func derivedTagEntries(from assets: [MediaAsset]) -> [TagLibraryEntry] {
        derivedTagEntries(from: assets.flatMap(\.tags))
    }

    private func derivedTagEntries(from tags: [MediaTag]) -> [TagLibraryEntry] {
        var summary: [String: (name: String, colorHex: String, usageCount: Int)] = [:]

        for tag in tags {
            if let current = summary[tag.normalizedName] {
                summary[tag.normalizedName] = (current.name, current.colorHex, current.usageCount + 1)
            } else {
                summary[tag.normalizedName] = (tag.name, tag.colorHex, 1)
            }
        }

        return summary.map { key, value in
            TagLibraryEntry(
                id: key,
                name: value.name,
                normalizedName: key,
                colorHex: value.colorHex,
                usageCount: value.usageCount
            )
        }
    }

    private func mergeTagEntries(_ groups: [[TagLibraryEntry]]) -> [TagLibraryEntry] {
        var summary: [String: (name: String, colorHex: String, usageCount: Int)] = [:]

        for entry in groups.flatMap({ $0 }) {
            if let current = summary[entry.normalizedName] {
                summary[entry.normalizedName] = (
                    current.name.count >= entry.name.count ? current.name : entry.name,
                    current.colorHex.isEmpty ? entry.colorHex : current.colorHex,
                    current.usageCount + entry.usageCount
                )
            } else {
                summary[entry.normalizedName] = (entry.name, entry.colorHex, entry.usageCount)
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

    private func removeAssetFromLocalState(_ asset: MediaAsset) {
        assets.removeAll { $0.id == asset.id }
        cleanupScopedAssets.removeAll { $0.id == asset.id }
        loadedAssetCount = assets.count
        totalAssetCount = max(totalAssetCount - 1, assets.count)
        currentOffset = min(currentOffset, assets.count)
        refreshCleanupStateFromScopedAssets()
    }

    private func insertAssetBackIntoLocalState(_ asset: MediaAsset) {
        let insertIndex = assets.firstIndex { existing in
            asset.createdAt > existing.createdAt
        } ?? assets.endIndex

        assets.insert(asset, at: insertIndex)
        if asset.isScreenshot {
            let screenshotInsertIndex = cleanupScopedAssets.firstIndex { existing in
                asset.createdAt > existing.createdAt
            } ?? cleanupScopedAssets.endIndex
            cleanupScopedAssets.insert(asset, at: screenshotInsertIndex)
        }

        loadedAssetCount = assets.count
        totalAssetCount += 1
        currentOffset = max(currentOffset, assets.count)
        refreshCleanupStateFromScopedAssets()
    }

    private func restorePendingDeletionAssets(_ stagedAssets: [MediaAsset]) {
        pendingDeletionAssets.removeAll()

        for asset in stagedAssets.sorted(by: { $0.createdAt < $1.createdAt }) {
            if !assets.contains(where: { $0.id == asset.id }) {
                insertAssetBackIntoLocalState(asset)
            }
        }
    }

    private func recordCleanupDeletion(count: Int) {
        guard count > 0 else {
            return
        }

        totalCleanupDeletedCount += count
        UserDefaults.standard.set(totalCleanupDeletedCount, forKey: cleanupDeletionCountKey)
    }

    private func startCleanupSyncIfNeeded() {
        guard cleanupSyncTask == nil else {
            return
        }

        isSyncingCleanupData = true
        cleanupSyncTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.load()
            self.isSyncingCleanupData = false
            self.cleanupSyncTask = nil
        }
    }

    private func handleObservedPhotoLibraryChange() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshForExternalLibraryChange(
                scope: self.hasLoadedCompleteLibrary ? .complete : .browsing
            )
        }
    }

    private func refreshForExternalLibraryChange(scope: LoadScope) async {
        guard hasHydratedCache || !assets.isEmpty || authorizationStatus.canReadAssets else {
            return
        }

        do {
            let fingerprint = try await photoLibraryService.libraryFingerprint()
            totalAssetCount = fingerprint.totalCount

            guard cachedFingerprint != fingerprint else {
                return
            }
        } catch {
            authorizationErrorMessage = L10n.text("error.load_photos", fallback: "Failed to load photos from the library.")
            return
        }

        if !pendingDeletionAssets.isEmpty {
            pendingDeletionAssets.removeAll()
        }

        await reloadAfterLibraryMutation(scope: scope)
    }

    private func reloadAfterLibraryMutation(scope: LoadScope) async {
        hasSynchronizedBrowsingThisLaunch = false
        hasSynchronizedCompleteThisLaunch = false
        cachedFingerprint = nil
        await load(scope: scope)
        markScopeAsSynchronized(scope)
    }

    private func markScopeAsSynchronized(_ scope: LoadScope) {
        if scope == .complete {
            hasSynchronizedBrowsingThisLaunch = true
            hasSynchronizedCompleteThisLaunch = true
        } else {
            hasSynchronizedBrowsingThisLaunch = true
        }
    }

    private func resetLibraryState() {
        assets = []
        cleanupScopedAssets = []
        loadedAssetCount = 0
        totalAssetCount = 0
        currentOffset = 0
        hasLoadedCompleteLibrary = false
        cachedFingerprint = nil
        cleanupSummary = CleanupSummary(
            totalScreenshotCount: 0,
            autoManagedCount: 0,
            expiringSoonCount: 0,
            protectedCount: 0,
            readyToCleanCount: 0
        )
        cleanupCandidates = []
    }

    private func smartOrbitMatch(
        for asset: MediaAsset,
        rule: SmartOrbitRule
    ) -> (reason: String, confidence: Int)? {
        let lowercasedTitle = asset.title.lowercased()
        let createdHour = Calendar.current.component(.hour, from: asset.createdAt)
        let weekday = Calendar.current.component(.weekday, from: asset.createdAt)

        switch rule {
        case .receipt:
            guard lowercasedTitle.contains("receipt")
                || lowercasedTitle.contains("invoice")
                || lowercasedTitle.contains("bill") else {
                return nil
            }
            return ("Title matches receipts or invoices.", 92)
        case .document:
            guard lowercasedTitle.contains("scan")
                || lowercasedTitle.contains("doc")
                || lowercasedTitle.contains("pdf") else {
                return nil
            }
            return ("Title looks like a scanned document.", 86)
        case .designReference:
            guard lowercasedTitle.contains("design")
                || lowercasedTitle.contains("figma")
                || lowercasedTitle.contains("ui") else {
                return nil
            }
            return ("Title looks like a design reference.", 90)
        case .chat:
            guard lowercasedTitle.contains("chat")
                || lowercasedTitle.contains("message")
                || lowercasedTitle.contains("whatsapp") else {
                return nil
            }
            return ("Title looks chat-related.", 78)
        case .meme:
            guard lowercasedTitle.contains("meme")
                || lowercasedTitle.contains("funny") else {
                return nil
            }
            return ("Title suggests meme content.", 75)
        case .study:
            guard lowercasedTitle.contains("note")
                || lowercasedTitle.contains("study")
                || lowercasedTitle.contains("lecture") else {
                return nil
            }
            return ("Title looks like study material.", 80)
        case .travel:
            guard lowercasedTitle.contains("trip")
                || lowercasedTitle.contains("travel")
                || lowercasedTitle.contains("flight") else {
                return nil
            }
            return ("Title suggests travel planning.", 78)
        case .toPost:
            guard asset.kind == .photo && !asset.isScreenshot else {
                return nil
            }
            return ("Photo is a strong candidate for later posting.", 62)
        case .weekend:
            guard weekday == 1 || weekday == 7 else {
                return nil
            }
            return ("Captured on a weekend.", 70)
        case .nightCapture:
            guard createdHour >= 20 || createdHour < 5 else {
                return nil
            }
            return ("Captured at night.", 74)
        }
    }

    private func matchesRecipe(_ asset: MediaAsset, recipe: OrbitRecipeKind) -> Bool {
        switch recipe {
        case .clearScreenshots:
            asset.isScreenshot
        case .archiveReceipts:
            smartOrbitMatch(for: asset, rule: .receipt) != nil
                || smartOrbitMatch(for: asset, rule: .document) != nil
        case .collectInspiration:
            smartOrbitMatch(for: asset, rule: .designReference) != nil
                || smartOrbitMatch(for: asset, rule: .meme) != nil
                || smartOrbitMatch(for: asset, rule: .toPost) != nil
        case .weekendReset:
            smartOrbitMatch(for: asset, rule: .weekend) != nil
                || smartOrbitMatch(for: asset, rule: .nightCapture) != nil
        }
    }
}

private final class PhotoLibraryChangeObserverProxy: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?
    private var isRegistered = false

    func register() {
        guard !isRegistered else {
            return
        }

        PHPhotoLibrary.shared().register(self)
        isRegistered = true
    }

    func unregister() {
        guard isRegistered else {
            return
        }

        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        isRegistered = false
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?()
    }
}
