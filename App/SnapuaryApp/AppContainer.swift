import Foundation

struct AppContainer {
    let photoLibraryService: PhotoLibraryServing
    let expirationService: ScreenshotExpirationServing
    let watermarkInspector: WatermarkInspecting

    static let live = AppContainer(
        photoLibraryService: MockPhotoLibraryService(),
        expirationService: MockScreenshotExpirationService(),
        watermarkInspector: MockWatermarkInspector()
    )
}

