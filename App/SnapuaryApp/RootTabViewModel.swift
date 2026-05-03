import Foundation
import Observation

enum RootTab: Hashable {
    case library
    case privacy
}

@Observable
final class RootTabViewModel {
    var selectedTab: RootTab = .library

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func makeLibraryViewModel() -> LibraryHomeViewModel {
        LibraryHomeViewModel(
            photoLibraryService: container.photoLibraryService,
            metadataService: container.metadataService,
            expirationService: container.expirationService,
            cleanupSchedulingService: container.cleanupSchedulingService
        )
    }

    func makeWatermarkViewModel() -> WatermarkPrivacyViewModel {
        WatermarkPrivacyViewModel(watermarkInspector: container.watermarkInspector)
    }
}
