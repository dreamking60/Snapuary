import Foundation

struct MediaAsset: Identifiable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var tags: [MediaTag]
    var retention: RetentionPolicy
    var isFavorite: Bool
    var source: MediaSource
}

enum MediaSource: String, Hashable {
    case screenshot
    case photo
}

struct MediaTag: Identifiable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var isProtected: Bool
}

enum RetentionPolicy: Hashable {
    case keepForever
    case expiresAt(Date)
}

