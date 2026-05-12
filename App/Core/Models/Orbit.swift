import Foundation

struct OrbitCollection: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var colorHex: String
    var symbolName: String
    var recipe: OrbitRecipeKind?
    var autoRule: SmartOrbitRule?
    var coverAssetIdentifier: String?
    var createdAt: Date

    init(
        id: String,
        name: String,
        colorHex: String,
        symbolName: String,
        recipe: OrbitRecipeKind? = nil,
        autoRule: SmartOrbitRule? = nil,
        coverAssetIdentifier: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.recipe = recipe
        self.autoRule = autoRule
        self.coverAssetIdentifier = coverAssetIdentifier
        self.createdAt = createdAt
    }
}

enum OrbitRecipeKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case clearScreenshots
    case archiveReceipts
    case collectInspiration
    case weekendReset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearScreenshots:
            L10n.text("orbit.recipe.clear_screenshots", fallback: "Clear Screenshots")
        case .archiveReceipts:
            L10n.text("orbit.recipe.archive_receipts", fallback: "Archive Receipts")
        case .collectInspiration:
            L10n.text("orbit.recipe.collect_inspiration", fallback: "Collect Inspiration")
        case .weekendReset:
            L10n.text("orbit.recipe.weekend_reset", fallback: "Weekend Reset")
        }
    }

    var subtitle: String {
        switch self {
        case .clearScreenshots:
            L10n.text("orbit.recipe.clear_screenshots.subtitle", fallback: "Trim recent screenshots fast.")
        case .archiveReceipts:
            L10n.text("orbit.recipe.archive_receipts.subtitle", fallback: "Sort bills and purchase proofs.")
        case .collectInspiration:
            L10n.text("orbit.recipe.collect_inspiration.subtitle", fallback: "Save design, style, and moodboard finds.")
        case .weekendReset:
            L10n.text("orbit.recipe.weekend_reset.subtitle", fallback: "Reset your recent camera roll in one session.")
        }
    }

    var symbolName: String {
        switch self {
        case .clearScreenshots:
            "camera.viewfinder"
        case .archiveReceipts:
            "receipt"
        case .collectInspiration:
            "sparkles.rectangle.stack"
        case .weekendReset:
            "sun.max"
        }
    }
}

enum SmartOrbitRule: String, Codable, CaseIterable, Identifiable, Hashable {
    case receipt
    case document
    case designReference
    case chat
    case meme
    case study
    case travel
    case toPost
    case weekend
    case nightCapture

    var id: String { rawValue }
}

enum OrbitSessionAction: String, Codable, Hashable {
    case assigned
    case kept
    case deleted
}

struct OrbitSessionEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let assetIdentifier: String
    let orbitID: String?
    let action: OrbitSessionAction
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        assetIdentifier: String,
        orbitID: String?,
        action: OrbitSessionAction,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.orbitID = orbitID
        self.action = action
        self.occurredAt = occurredAt
    }
}

struct OrbitWeeklyRecap: Hashable {
    var assignedCount: Int
    var keptCount: Int
    var deletedCount: Int
    var topOrbitNames: [String]
    var weekStart: Date

    static let empty = OrbitWeeklyRecap(
        assignedCount: 0,
        keptCount: 0,
        deletedCount: 0,
        topOrbitNames: [],
        weekStart: .now
    )
}

struct OrbitReviewCluster: Identifiable, Hashable {
    let id: String
    let title: String
    let assetIDs: [UUID]
    let count: Int
}

struct OrbitSuggestion: Identifiable, Hashable {
    let id: String
    let orbitID: String
    let reason: String
    let confidence: Int
}
