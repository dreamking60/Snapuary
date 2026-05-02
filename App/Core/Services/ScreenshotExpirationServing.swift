import Foundation

protocol ScreenshotExpirationServing {
    func upcomingCleanupSummary(for assets: [MediaAsset]) -> CleanupSummary
}

struct CleanupSummary: Hashable {
    let expiringSoonCount: Int
    let protectedCount: Int
}

struct MockScreenshotExpirationService: ScreenshotExpirationServing {
    func upcomingCleanupSummary(for assets: [MediaAsset]) -> CleanupSummary {
        let expiringSoonCount = assets.filter {
            if case .expiresAt(let date) = $0.retention {
                return date < .now.addingTimeInterval(86_400 * 3)
            }
            return false
        }.count

        let protectedCount = assets.filter { $0.isFavorite || $0.tags.contains(where: \.isProtected) }.count

        return CleanupSummary(expiringSoonCount: expiringSoonCount, protectedCount: protectedCount)
    }
}

