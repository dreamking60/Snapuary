import Foundation

struct AppContainer {
    let settingsStore: AppSettingsStore
    let photoLibraryService: PhotoLibraryServing
    let thumbnailStore: PhotoLibraryThumbnailStore
    let assetIndexCache: MediaAssetIndexCaching
    let metadataService: MediaAssetMetadataServing
    let tagCatalogStore: TagCatalogServing
    let orbitLibraryStore: OrbitLibraryServing
    let expirationService: ScreenshotExpirationServing
    let cleanupSchedulingService: CleanupSchedulingServing
    let autoTagSuggestionService: AutoTagSuggesting
    let watermarkInspector: WatermarkInspecting

    static let metadataService = FileBackedMediaAssetMetadataStore()
    static let assetIndexCache = FileBackedMediaAssetIndexCache()
    static let tagCatalogStore = FileBackedTagCatalogStore()
    static let orbitLibraryStore = FileBackedOrbitLibraryStore()
    static let cleanupSchedulingService = UserNotificationCleanupScheduler()
    static let thumbnailStore = PhotoLibraryThumbnailStore()
    static let settingsStore = AppSettingsStore()

    static let live = AppContainer(
        settingsStore: settingsStore,
        photoLibraryService: MetadataMergingPhotoLibraryService(
            base: PhotoKitPhotoLibraryService(thumbnailStore: thumbnailStore),
            metadataStore: metadataService
        ),
        thumbnailStore: thumbnailStore,
        assetIndexCache: assetIndexCache,
        metadataService: metadataService,
        tagCatalogStore: tagCatalogStore,
        orbitLibraryStore: orbitLibraryStore,
        expirationService: MockScreenshotExpirationService(),
        cleanupSchedulingService: cleanupSchedulingService,
        autoTagSuggestionService: TemplateAutoTagSuggestionService(),
        watermarkInspector: MockWatermarkInspector()
    )
}
