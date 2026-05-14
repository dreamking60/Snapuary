import Foundation
import Observation

enum RootTab: Hashable {
    case library
    case tags
    case orbit
    case cleanup
}

@MainActor
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
            tagCatalogStore: container.tagCatalogStore,
            orbitLibraryStore: container.orbitLibraryStore,
            expirationService: container.expirationService,
            cleanupSchedulingService: container.cleanupSchedulingService,
            autoTagSuggestionService: container.autoTagSuggestionService
        )
    }

    func makeLibraryViewModel() -> LibraryHomeViewModel {
        libraryViewModel
    }

    func handlePendingRouteIfNeeded() {
        guard let route = AppRouteStore.shared.consumePendingRoute() else {
            return
        }

        switch route {
        case let .orbit(orbitID):
            selectedTab = .orbit
            libraryViewModel.focusOrbit(orbitID)
            libraryViewModel.activateRecipe(nil)
        case let .recipe(recipeID):
            selectedTab = .orbit
            guard let recipe = OrbitRecipeKind(rawValue: recipeID) else {
                return
            }
            libraryViewModel.activateRecipe(recipe)
            if let orbitID = libraryViewModel.recipeCollections.first(where: { $0.recipe == recipe })?.id {
                libraryViewModel.focusOrbit(orbitID)
            }
            libraryViewModel.cleanupReviewMode = recipe == .clearScreenshots ? .screenshots : .allPhotos
        case .latestScreenshots:
            selectedTab = .cleanup
            libraryViewModel.cleanupReviewMode = .screenshots
            libraryViewModel.activateRecipe(nil)
        }
    }
}
