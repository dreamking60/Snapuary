import Foundation

struct AppContainer {
    let photoLibraryService: PhotoLibraryServing
    let thumbnailStore: PhotoLibraryThumbnailStore
    let metadataService: MediaAssetMetadataServing
    let expirationService: ScreenshotExpirationServing
    let cleanupSchedulingService: CleanupSchedulingServing
    let watermarkInspector: WatermarkInspecting

    static let metadataService = FileBackedMediaAssetMetadataStore()
    static let cleanupSchedulingService = UserNotificationCleanupScheduler()
    static let thumbnailStore = PhotoLibraryThumbnailStore()

    static let live = AppContainer(
        photoLibraryService: MetadataMergingPhotoLibraryService(
            base: PhotoKitPhotoLibraryService(thumbnailStore: thumbnailStore),
            metadataStore: metadataService
        ),
        thumbnailStore: thumbnailStore,
        metadataService: metadataService,
        expirationService: MockScreenshotExpirationService(),
        cleanupSchedulingService: cleanupSchedulingService,
        watermarkInspector: MockWatermarkInspector()
    )
}
