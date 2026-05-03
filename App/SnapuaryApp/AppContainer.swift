import Foundation

struct AppContainer {
    let photoLibraryService: PhotoLibraryServing
    let metadataService: MediaAssetMetadataServing
    let expirationService: ScreenshotExpirationServing
    let cleanupSchedulingService: CleanupSchedulingServing
    let watermarkInspector: WatermarkInspecting

    static let metadataService = FileBackedMediaAssetMetadataStore()
    static let cleanupSchedulingService = UserNotificationCleanupScheduler()

    static let live = AppContainer(
        photoLibraryService: MetadataMergingPhotoLibraryService(
            base: PhotoKitPhotoLibraryService(),
            metadataStore: metadataService
        ),
        metadataService: metadataService,
        expirationService: MockScreenshotExpirationService(),
        cleanupSchedulingService: cleanupSchedulingService,
        watermarkInspector: MockWatermarkInspector()
    )
}
