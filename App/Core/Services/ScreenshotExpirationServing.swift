import Foundation

protocol ScreenshotExpirationServing {
    func upcomingCleanupSummary(for assets: [MediaAsset]) -> CleanupSummary
    func cleanupCandidates(from assets: [MediaAsset], now: Date) -> [MediaAsset]
}

struct CleanupSummary: Hashable {
    let totalScreenshotCount: Int
    let autoManagedCount: Int
    let expiringSoonCount: Int
    let protectedCount: Int
    let readyToCleanCount: Int
}

struct CleanupExecutionResult: Hashable {
    let deletedCount: Int
    let deletedAssetTitles: [String]
}

struct MockScreenshotExpirationService: ScreenshotExpirationServing {
    func upcomingCleanupSummary(for assets: [MediaAsset]) -> CleanupSummary {
        let screenshots = assets.filter(\.isScreenshot)
        let autoManagedCount = screenshots.filter { $0.expirationDate != nil }.count
        let cleanupCandidates = cleanupCandidates(from: assets, now: .now)
        let expiringSoonCount = screenshots.filter {
            guard let expirationDate = $0.expirationDate else {
                return false
            }
            return expirationDate >= .now && expirationDate < .now.addingTimeInterval(86_400 * 3)
        }.count
        let protectedCount = screenshots.filter(\.isProtectedFromCleanup).count

        return CleanupSummary(
            totalScreenshotCount: screenshots.count,
            autoManagedCount: autoManagedCount,
            expiringSoonCount: expiringSoonCount,
            protectedCount: protectedCount,
            readyToCleanCount: cleanupCandidates.count
        )
    }

    func cleanupCandidates(from assets: [MediaAsset], now: Date = .now) -> [MediaAsset] {
        assets.filter { asset in
            guard asset.isScreenshot,
                  !asset.isProtectedFromCleanup,
                  let expirationDate = asset.expirationDate else {
                return false
            }

            return expirationDate <= now
        }
    }
}
