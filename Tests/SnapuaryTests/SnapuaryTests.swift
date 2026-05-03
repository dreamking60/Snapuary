import Photos
import XCTest
@testable import Snapuary

final class SnapuaryTests: XCTestCase {
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
        XCTAssertEqual(summary.protectedCount, 1)
        XCTAssertEqual(summary.totalScreenshotCount, 1)
    }

    func importedScreenshotLikeCanExpireFromAddedDate() throws {
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

        let expirationDate = try XCTUnwrap(asset.expirationDate)
        let expectedDate = Calendar.current.date(byAdding: .day, value: 30, to: asset.addedAt)
        XCTAssertTrue(Calendar.current.isDate(expirationDate, equalTo: expectedDate ?? expirationDate, toGranularity: .day))
    }

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

        let expirationDate = try XCTUnwrap(asset.expirationDate)
        XCTAssertTrue(Calendar.current.isDate(expirationDate, equalTo: fixedDate, toGranularity: .day))
    }

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
        XCTAssertEqual(asset.kind, .systemScreenshot)
        XCTAssertEqual(asset.screenshotRule?.displayName, "30 Days")
    }

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
        XCTAssertEqual(asset.kind, .photo)
        XCTAssertNil(asset.screenshotRule)
    }

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
        let asset = try XCTUnwrap(assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))

        XCTAssertEqual(asset.kind, .importedScreenshotLike)
        XCTAssertEqual(asset.tags.map(\.name), ["Imported"])
        XCTAssertEqual(asset.screenshotRule?.displayName, "30 Days")
    }

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

        XCTAssertEqual(records["asset-3"], record)
    }

    func libraryHomeViewModelCanAddAndRemoveTag() async throws {
        let metadataStore = InMemoryMediaAssetMetadataStore()
        let viewModel = LibraryHomeViewModel(
            photoLibraryService: MockPhotoLibraryService(),
            metadataService: metadataStore,
            expirationService: MockScreenshotExpirationService(),
            cleanupSchedulingService: InMemoryCleanupSchedulingService()
        )

        await viewModel.load()
        let asset = try XCTUnwrap(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))

        await viewModel.addTag(name: "Travel", colorHex: "#00AAFF", to: asset)
        let taggedAsset = try XCTUnwrap(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))
        let newTag = try XCTUnwrap(taggedAsset.tags.first(where: { $0.name == "Travel" }))
        XCTAssertTrue(taggedAsset.tags.contains(where: { $0.name == "Travel" }))

        await viewModel.removeTag(newTag, from: taggedAsset)
        let cleanedAsset = try XCTUnwrap(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))
        XCTAssertFalse(cleanedAsset.tags.contains(where: { $0.name == "Travel" }))
    }

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

        XCTAssertEqual(library.first?.name, "Finance")
        XCTAssertEqual(library.first?.usageCount, 2)
    }

    func libraryHomeViewModelCanBatchApplyGlobalTags() async throws {
        let metadataStore = InMemoryMediaAssetMetadataStore()
        let viewModel = LibraryHomeViewModel(
            photoLibraryService: MockPhotoLibraryService(),
            metadataService: metadataStore,
            expirationService: MockScreenshotExpirationService(),
            cleanupSchedulingService: InMemoryCleanupSchedulingService()
        )

        await viewModel.load()
        let asset = try XCTUnwrap(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))
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
        let updatedAsset = try XCTUnwrap(viewModel.assets.first(where: { $0.libraryIdentifier == "mock-photo-1" }))

        XCTAssertTrue(updatedAsset.tags.contains(where: { $0.name == "Finance" }))
        XCTAssertTrue(updatedAsset.tags.contains(where: { $0.name == "Reference" }))
    }

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
        XCTAssertEqual(candidates.compactMap(\.libraryIdentifier), ["expired-shot"])
    }

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
        XCTAssertEqual(viewModel.cleanupCandidates.count, 1)

        await viewModel.runCleanupNow()

        XCTAssertTrue(viewModel.assets.isEmpty)
        let records = try await metadataStore.fetchAllMetadata()
        XCTAssertNil(records["cleanup-1"])
        XCTAssertEqual(viewModel.lastCleanupResult?.deletedCount, 1)
    }

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

        XCTAssertEqual(reminder?.candidateCount, 1)
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

final class InMemoryPhotoLibraryService: PhotoLibraryServing {
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
