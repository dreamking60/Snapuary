import Photos
import Testing
@testable import Snapuary

struct SnapuaryTests {
    @Test
    func cleanupSummaryCountsProtectedItems() {
        let service = MockScreenshotExpirationService()
        let assets = [
            MediaAsset(
                id: UUID(),
                libraryIdentifier: nil,
                title: "Protected screenshot",
                createdAt: .now,
                addedAt: .now,
                tags: [MediaTag(id: UUID(), name: "Favorite", colorHex: "#000000")],
                kind: .systemScreenshot,
                screenshotRule: ScreenshotRetentionRule(
                    mode: .preset(.oneWeek),
                    anchor: .creationDate
                ),
                isProtectedFromCleanup: true
            )
        ]

        let summary = service.upcomingCleanupSummary(for: assets)
        #expect(summary.protectedCount == 1)
        #expect(summary.totalScreenshotCount == 1)
    }

    @Test
    func importedScreenshotLikeCanExpireFromAddedDate() {
        let asset = MediaAsset(
            id: UUID(),
            libraryIdentifier: nil,
            title: "Imported screenshot",
            createdAt: .now.addingTimeInterval(-86_400 * 20),
            addedAt: .now.addingTimeInterval(-86_400 * 2),
            tags: [],
            kind: .importedScreenshotLike,
            screenshotRule: ScreenshotRetentionRule(
                mode: .customDays(30),
                anchor: .addedDate
            ),
            isProtectedFromCleanup: false
        )

        let expirationDate = try #require(asset.expirationDate)
        let expectedDate = Calendar.current.date(byAdding: .day, value: 30, to: asset.addedAt)
        #expect(Calendar.current.isDate(expirationDate, equalTo: expectedDate ?? expirationDate, toGranularity: .day))
    }

    @Test
    func fixedDateRetentionRuleReturnsExplicitDate() throws {
        let fixedDate = Date.now.addingTimeInterval(86_400 * 45)
        let asset = MediaAsset(
            id: UUID(),
            libraryIdentifier: nil,
            title: "Fixed-date screenshot",
            createdAt: .now,
            addedAt: .now,
            tags: [],
            kind: .systemScreenshot,
            screenshotRule: ScreenshotRetentionRule(mode: .expiresAt(fixedDate), anchor: .creationDate),
            isProtectedFromCleanup: false
        )

        let expirationDate = try #require(asset.expirationDate)
        #expect(Calendar.current.isDate(expirationDate, equalTo: fixedDate, toGranularity: .day))
    }

    @Test
    func photoKitDescriptorMapsScreenshotSubtypeToSystemScreenshot() {
        let descriptor = PhotoLibraryAssetDescriptor(
            localIdentifier: "asset-1",
            mediaSubtypesRawValue: PHAssetMediaSubtype.photoScreenshot.rawValue,
            creationDate: .now.addingTimeInterval(-3_600),
            addedDate: .now.addingTimeInterval(-1_800),
            pixelWidth: 1179,
            pixelHeight: 2556
        )

        let asset = PhotoKitPhotoLibraryService.map(descriptor: descriptor)
        #expect(asset.kind == .systemScreenshot)
        #expect(asset.screenshotRule?.displayName == "30 Days")
    }

    @Test
    func photoKitDescriptorMapsRegularImageToPhoto() {
        let descriptor = PhotoLibraryAssetDescriptor(
            localIdentifier: "asset-2",
            mediaSubtypesRawValue: 0,
            creationDate: .now,
            addedDate: .now,
            pixelWidth: 4032,
            pixelHeight: 3024
        )

        let asset = PhotoKitPhotoLibraryService.map(descriptor: descriptor)
        #expect(asset.kind == .photo)
        #expect(asset.screenshotRule == nil)
    }

    @Test
    func metadataMergeCanPromotePhotoToImportedScreenshotLike() async throws {
        let base = MockPhotoLibraryService()
        let metadataStore = InMemoryMediaAssetMetadataStore(records: [
            "mock-photo-1": MediaAssetMetadataRecord(
                isImportedScreenshotLike: true,
                tags: [MediaTag(id: UUID(), name: "Imported", colorHex: "#123456")],
                screenshotRule: ScreenshotRetentionRule(
                    mode: .preset(.thirtyDays),
                    anchor: .addedDate
                ),
                isProtectedFromCleanup: false
            )
        ])

        let service = MetadataMergingPhotoLibraryService(base: base, metadataStore: metadataStore)
        let assets = try await service.fetchAssets()
        let asset = try #require(assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))

        #expect(asset.kind == .importedScreenshotLike)
        #expect(asset.tags.map(\.name) == ["Imported"])
        #expect(asset.screenshotRule?.displayName == "30 Days")
    }

    @Test
    func fileBackedMetadataStoreRoundTripsRecords() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("metadata.json", isDirectory: false)
        let store = FileBackedMediaAssetMetadataStore(fileURL: fileURL)
        let record = MediaAssetMetadataRecord(
            isImportedScreenshotLike: true,
            tags: [MediaTag(id: UUID(), name: "Finance", colorHex: "#AAAAAA")],
            screenshotRule: ScreenshotRetentionRule(mode: .customDays(45), anchor: .addedDate),
            isProtectedFromCleanup: true
        )

        try await store.saveMetadata(record, for: "asset-3")
        let records = try await store.fetchAllMetadata()

        #expect(records["asset-3"] == record)
    }

    @Test
    func libraryHomeViewModelCanAddAndRemoveTag() async throws {
        let metadataStore = InMemoryMediaAssetMetadataStore()
        let viewModel = LibraryHomeViewModel(
            photoLibraryService: MockPhotoLibraryService(),
            metadataService: metadataStore,
            expirationService: MockScreenshotExpirationService(),
            cleanupSchedulingService: InMemoryCleanupSchedulingService()
        )

        await viewModel.load()
        let asset = try #require(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))

        await viewModel.addTag(name: "Travel", colorHex: "#00AAFF", to: asset)
        let taggedAsset = try #require(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))
        let newTag = try #require(taggedAsset.tags.first(where: { $0.name == "Travel" }))
        #expect(taggedAsset.tags.contains(where: { $0.name == "Travel" }))

        await viewModel.removeTag(newTag, from: taggedAsset)
        let cleanedAsset = try #require(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))
        #expect(!cleanedAsset.tags.contains(where: { $0.name == "Travel" }))
    }

    @Test
    func tagLibraryOrdersByUsageCount() async throws {
        let photoLibraryService = InMemoryPhotoLibraryService(assets: [
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "tag-1",
                title: "A",
                createdAt: .now,
                addedAt: .now,
                tags: [
                    MediaTag(id: UUID(), name: "Finance", colorHex: "#E07A5F"),
                    MediaTag(id: UUID(), name: "Travel", colorHex: "#00AAFF")
                ],
                kind: .photo,
                screenshotRule: nil,
                isProtectedFromCleanup: false
            ),
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "tag-2",
                title: "B",
                createdAt: .now,
                addedAt: .now,
                tags: [
                    MediaTag(id: UUID(), name: "Finance", colorHex: "#E07A5F")
                ],
                kind: .photo,
                screenshotRule: nil,
                isProtectedFromCleanup: false
            )
        ])
        let viewModel = LibraryHomeViewModel(
            photoLibraryService: photoLibraryService,
            metadataService: InMemoryMediaAssetMetadataStore(),
            expirationService: MockScreenshotExpirationService(),
            cleanupSchedulingService: InMemoryCleanupSchedulingService()
        )

        await viewModel.load()
        let library = viewModel.tagLibrary

        #expect(library.first?.name == "Finance")
        #expect(library.first?.usageCount == 2)
    }

    @Test
    func libraryHomeViewModelCanBatchApplyGlobalTags() async throws {
        let metadataStore = InMemoryMediaAssetMetadataStore()
        let viewModel = LibraryHomeViewModel(
            photoLibraryService: MockPhotoLibraryService(),
            metadataService: metadataStore,
            expirationService: MockScreenshotExpirationService(),
            cleanupSchedulingService: InMemoryCleanupSchedulingService()
        )

        await viewModel.load()
        let asset = try #require(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))
        let tags = [
            TagLibraryEntry(
                id: "finance",
                name: "Finance",
                normalizedName: "finance",
                colorHex: "#E07A5F",
                usageCount: 2
            ),
            TagLibraryEntry(
                id: "reference",
                name: "Reference",
                normalizedName: "reference",
                colorHex: "#6D597A",
                usageCount: 1
            )
        ]

        await viewModel.addTags(tags, to: asset)
        let updatedAsset = try #require(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))

        #expect(updatedAsset.tags.contains(where: { $0.name == "Finance" }))
        #expect(updatedAsset.tags.contains(where: { $0.name == "Reference" }))
    }

    @Test
    func expirationServiceReturnsOnlyExpiredUnprotectedScreenshots() {
        let service = MockScreenshotExpirationService()
        let assets = [
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "expired-shot",
                title: "Expired screenshot",
                createdAt: .now.addingTimeInterval(-86_400 * 10),
                addedAt: .now.addingTimeInterval(-86_400 * 10),
                tags: [],
                kind: .systemScreenshot,
                screenshotRule: ScreenshotRetentionRule(mode: .preset(.oneWeek), anchor: .creationDate),
                isProtectedFromCleanup: false
            ),
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "protected-shot",
                title: "Protected screenshot",
                createdAt: .now.addingTimeInterval(-86_400 * 10),
                addedAt: .now.addingTimeInterval(-86_400 * 10),
                tags: [],
                kind: .systemScreenshot,
                screenshotRule: ScreenshotRetentionRule(mode: .preset(.oneWeek), anchor: .creationDate),
                isProtectedFromCleanup: true
            ),
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "future-shot",
                title: "Future screenshot",
                createdAt: .now,
                addedAt: .now,
                tags: [],
                kind: .systemScreenshot,
                screenshotRule: ScreenshotRetentionRule(mode: .preset(.oneWeek), anchor: .creationDate),
                isProtectedFromCleanup: false
            )
        ]

        let candidates = service.cleanupCandidates(from: assets, now: .now)
        #expect(candidates.compactMap(\.libraryIdentifier) == ["expired-shot"])
    }

    @Test
    func libraryHomeViewModelCleanupRemovesExpiredAssetsAndMetadata() async throws {
        let photoLibraryService = InMemoryPhotoLibraryService(assets: [
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "cleanup-1",
                title: "Cleanup candidate",
                createdAt: .now.addingTimeInterval(-86_400 * 10),
                addedAt: .now.addingTimeInterval(-86_400 * 10),
                tags: [],
                kind: .systemScreenshot,
                screenshotRule: ScreenshotRetentionRule(mode: .preset(.oneWeek), anchor: .creationDate),
                isProtectedFromCleanup: false
            )
        ])
        let metadataStore = InMemoryMediaAssetMetadataStore(records: [
            "cleanup-1": MediaAssetMetadataRecord(
                isImportedScreenshotLike: false,
                tags: [MediaTag(id: UUID(), name: "Old", colorHex: "#111111")],
                screenshotRule: ScreenshotRetentionRule(mode: .preset(.oneWeek), anchor: .creationDate),
                isProtectedFromCleanup: false
            )
        ])
        let viewModel = LibraryHomeViewModel(
            photoLibraryService: photoLibraryService,
            metadataService: metadataStore,
            expirationService: MockScreenshotExpirationService(),
            cleanupSchedulingService: InMemoryCleanupSchedulingService()
        )

        await viewModel.load()
        #expect(viewModel.cleanupCandidates.count == 1)

        await viewModel.runCleanupNow()

        #expect(viewModel.assets.isEmpty)
        let records = try await metadataStore.fetchAllMetadata()
        #expect(records["cleanup-1"] == nil)
        #expect(viewModel.lastCleanupResult?.deletedCount == 1)
    }

    @Test
    func cleanupSchedulerSchedulesNearestFutureExpiration() async throws {
        let scheduler = InMemoryCleanupSchedulingService()
        let assets = [
            MediaAsset(
                id: UUID(),
                libraryIdentifier: "future-1",
                title: "Soon due",
                createdAt: .now,
                addedAt: .now,
                tags: [],
                kind: .systemScreenshot,
                screenshotRule: ScreenshotRetentionRule(mode: .customDays(1), anchor: .creationDate),
                isProtectedFromCleanup: false
            )
        ]

        let reminder = try await scheduler.scheduleNextCleanupReminder(
            for: assets,
            now: .now.addingTimeInterval(-60)
        )

        #expect(reminder?.candidateCount == 1)
    }
}

actor InMemoryMediaAssetMetadataStore: MediaAssetMetadataServing {
    private var records: [String: MediaAssetMetadataRecord]

    init(records: [String: MediaAssetMetadataRecord] = [:]) {
        self.records = records
    }

    func fetchAllMetadata() async throws -> [String: MediaAssetMetadataRecord] {
        records
    }

    func saveMetadata(_ metadata: MediaAssetMetadataRecord, for libraryIdentifier: String) async throws {
        records[libraryIdentifier] = metadata
    }

    func removeMetadata(for libraryIdentifiers: [String]) async throws {
        for libraryIdentifier in libraryIdentifiers {
            records.removeValue(forKey: libraryIdentifier)
        }
    }
}

actor InMemoryPhotoLibraryService: PhotoLibraryServing {
    private var assets: [MediaAsset]

    init(assets: [MediaAsset]) {
        self.assets = assets
    }

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        .authorized
    }

    func fetchAssets() async throws -> [MediaAsset] {
        assets
    }

    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws {
        assets.removeAll { asset in
            guard let libraryIdentifier = asset.libraryIdentifier else {
                return false
            }
            return identifiers.contains(libraryIdentifier)
        }
    }
}

actor InMemoryCleanupSchedulingService: CleanupSchedulingServing {
    private(set) var status: CleanupNotificationAuthorizationStatus = .authorized
    private(set) var lastSchedule: CleanupReminderSchedule?

    func authorizationStatus() async -> CleanupNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> CleanupNotificationAuthorizationStatus {
        status
    }

    func scheduleNextCleanupReminder(for assets: [MediaAsset], now: Date) async throws -> CleanupReminderSchedule? {
        let next = assets
            .filter(\.isScreenshot)
            .filter { !$0.isProtectedFromCleanup }
            .compactMap { asset -> (MediaAsset, Date)? in
                guard let expirationDate = asset.expirationDate, expirationDate > now else {
                    return nil
                }
                return (asset, expirationDate)
            }
            .sorted { $0.1 < $1.1 }
            .first

        guard let next else {
            lastSchedule = nil
            return nil
        }

        let schedule = CleanupReminderSchedule(
            title: "Screenshot Cleanup Due",
            scheduledAt: next.1,
            candidateCount: 1
        )
        lastSchedule = schedule
        return schedule
    }
}
