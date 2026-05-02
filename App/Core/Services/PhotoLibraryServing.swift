import Foundation

protocol PhotoLibraryServing {
    func fetchAssets() async throws -> [MediaAsset]
}

struct MockPhotoLibraryService: PhotoLibraryServing {
    func fetchAssets() async throws -> [MediaAsset] {
        [
            MediaAsset(
                id: UUID(),
                title: "Order receipt screenshot",
                createdAt: .now.addingTimeInterval(-86_400),
                tags: [
                    MediaTag(id: UUID(), name: "Finance", colorHex: "#E07A5F", isProtected: false)
                ],
                retention: .expiresAt(.now.addingTimeInterval(86_400 * 7)),
                isFavorite: false,
                source: .screenshot
            ),
            MediaAsset(
                id: UUID(),
                title: "Saved inspiration",
                createdAt: .now.addingTimeInterval(-86_400 * 3),
                tags: [
                    MediaTag(id: UUID(), name: "Favorite", colorHex: "#3D405B", isProtected: true)
                ],
                retention: .keepForever,
                isFavorite: true,
                source: .photo
            )
        ]
    }
}

