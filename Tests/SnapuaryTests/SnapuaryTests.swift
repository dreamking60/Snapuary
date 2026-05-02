import Testing
@testable import Snapuary

struct SnapuaryTests {
    @Test
    func cleanupSummaryCountsProtectedItems() {
        let service = MockScreenshotExpirationService()
        let assets = [
            MediaAsset(
                id: UUID(),
                title: "Protected screenshot",
                createdAt: .now,
                tags: [MediaTag(id: UUID(), name: "Favorite", colorHex: "#000000", isProtected: true)],
                retention: .keepForever,
                isFavorite: false,
                source: .screenshot
            )
        ]

        let summary = service.upcomingCleanupSummary(for: assets)
        #expect(summary.protectedCount == 1)
    }
}
