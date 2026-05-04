import Foundation

struct AppContainer {
    let photoLibraryService: PhotoLibraryServing
    let thumbnailStore: PhotoLibraryThumbnailStore
    let assetIndexCache: MediaAssetIndexCaching
    let metadataService: MediaAssetMetadataServing
    let expirationService: ScreenshotExpirationServing
    let cleanupSchedulingService: CleanupSchedulingServing
    let watermarkInspector: WatermarkInspecting

    static let metadataService = FileBackedMediaAssetMetadataStore()
    static let assetIndexCache = FileBackedMediaAssetIndexCache()
    static let cleanupSchedulingService = UserNotificationCleanupScheduler()
    static let thumbnailStore = PhotoLibraryThumbnailStore()

    static let live = AppContainer(
        photoLibraryService: MetadataMergingPhotoLibraryService(
            base: PhotoKitPhotoLibraryService(thumbnailStore: thumbnailStore),
            metadataStore: metadataService
        ),
        thumbnailStore: thumbnailStore,
        assetIndexCache: assetIndexCache,
        metadataService: metadataService,
        expirationService: MockScreenshotExpirationService(),
        cleanupSchedulingService: cleanupSchedulingService,
        watermarkInspector: MockWatermarkInspector()
    )
}
