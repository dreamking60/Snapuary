import Foundation
import Observation

@Observable
final class LibraryHomeViewModel {
    private let photoLibraryService: PhotoLibraryServing
    private let expirationService: ScreenshotExpirationServing

    private(set) var assets: [MediaAsset] = []
    private(set) var cleanupSummary = CleanupSummary(expiringSoonCount: 0, protectedCount: 0)
    private(set) var isLoading = false

    init(
        photoLibraryService: PhotoLibraryServing,
        expirationService: ScreenshotExpirationServing
    ) {
        self.photoLibraryService = photoLibraryService
        self.expirationService = expirationService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let assets = try await photoLibraryService.fetchAssets()
            self.assets = assets
            cleanupSummary = expirationService.upcomingCleanupSummary(for: assets)
        } catch {
            assets = []
            cleanupSummary = CleanupSummary(expiringSoonCount: 0, protectedCount: 0)
        }
    }
}
