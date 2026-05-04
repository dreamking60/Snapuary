import Foundation
import Observation

enum RootTab: Hashable {
    case library
    case tags
    case cleanup
}

@Observable
final class RootTabViewModel {
    var selectedTab: RootTab = .library

    private let libraryViewModel: LibraryHomeViewModel

    init(container: AppContainer) {
        self.libraryViewModel = LibraryHomeViewModel(
            photoLibraryService: container.photoLibraryService,
            thumbnailStore: container.thumbnailStore,
            metadataService: container.metadataService,
            expirationService: container.expirationService,
            cleanupSchedulingService: container.cleanupSchedulingService
        )
    }

    func makeLibraryViewModel() -> LibraryHomeViewModel {
        libraryViewModel
    }
}
