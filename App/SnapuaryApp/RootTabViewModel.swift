import Foundation
import Observation

enum RootTab: Hashable {
    case library
    case tags
    case cleanup
}

@Observable
final class RootTabViewModel {
    var selectedTab: RootTab

    private let libraryViewModel: LibraryHomeViewModel

    init(container: AppContainer) {
        self.selectedTab = container.settingsStore.preferredLaunchTab
        self.libraryViewModel = LibraryHomeViewModel(
            photoLibraryService: container.photoLibraryService,
            thumbnailStore: container.thumbnailStore,
            assetIndexCache: container.assetIndexCache,
            metadataService: container.metadataService,
            expirationService: container.expirationService,
            cleanupSchedulingService: container.cleanupSchedulingService
        )
    }

    func makeLibraryViewModel() -> LibraryHomeViewModel {
        libraryViewModel
    }
}
