import AppIntents
import Foundation

enum OrbitRecipeAppEnum: String, AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Review Recipe")

    static let caseDisplayRepresentations: [OrbitRecipeAppEnum: DisplayRepresentation] = [
        .clearScreenshots: DisplayRepresentation(title: "Clear Screenshots"),
        .archiveReceipts: DisplayRepresentation(title: "Archive Receipts"),
        .collectInspiration: DisplayRepresentation(title: "Collect Inspiration"),
        .weekendReset: DisplayRepresentation(title: "Weekend Reset")
    ]

    case clearScreenshots
    case archiveReceipts
    case collectInspiration
    case weekendReset

    var recipeKind: OrbitRecipeKind {
        switch self {
        case .clearScreenshots:
            .clearScreenshots
        case .archiveReceipts:
            .archiveReceipts
        case .collectInspiration:
            .collectInspiration
        case .weekendReset:
            .weekendReset
        }
    }
}

struct OrbitEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Orbit")
    static let defaultQuery = OrbitEntityQuery()

    let id: String
    let name: String
    let symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: "Snapuary Orbit",
            image: .init(systemName: symbolName)
        )
    }
}

struct OrbitEntityQuery: EntityQuery {
    func entities(for identifiers: [OrbitEntity.ID]) async throws -> [OrbitEntity] {
        try await loadOrbits().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [OrbitEntity] {
        try await loadOrbits()
    }

    private func loadOrbits() async throws -> [OrbitEntity] {
        let snapshot = try await FileBackedOrbitLibraryStore().loadLibrary()
        return snapshot.collections.map { orbit in
            OrbitEntity(id: orbit.id, name: orbit.name, symbolName: orbit.symbolName)
        }
    }
}

struct OpenOrbitIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Orbit"
    static let description = IntentDescription("Open one of your Orbit lanes in Snapuary.")
    static var openAppWhenRun = true

    @Parameter(title: "Orbit")
    var orbit: OrbitEntity

    func perform() async throws -> some IntentResult {
        AppRouteStore.shared.setPendingRoute(.orbit(orbit.id))
        return .result()
    }
}

struct StartReviewRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Review Recipe"
    static let description = IntentDescription("Jump into a themed Orbit review flow.")
    static var openAppWhenRun = true

    @Parameter(title: "Recipe")
    var recipe: OrbitRecipeAppEnum

    func perform() async throws -> some IntentResult {
        AppRouteStore.shared.setPendingRoute(.recipe(recipe.recipeKind.rawValue))
        return .result()
    }
}

struct ReviewLatestScreenshotsIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Latest Screenshots"
    static let description = IntentDescription("Open Snapuary straight into the screenshot review flow.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppRouteStore.shared.setPendingRoute(.latestScreenshots)
        return .result()
    }
}

struct SnapuaryShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReviewLatestScreenshotsIntent(),
            phrases: [
                "Review latest screenshots in \(.applicationName)",
                "Open screenshot review in \(.applicationName)"
            ],
            shortTitle: "Review Screenshots",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: StartReviewRecipeIntent(),
            phrases: [
                "Start a review recipe in \(.applicationName)",
                "Open Orbit recipe in \(.applicationName)"
            ],
            shortTitle: "Start Recipe",
            systemImageName: "sparkles.rectangle.stack"
        )
        AppShortcut(
            intent: OpenOrbitIntent(),
            phrases: [
                "Open an Orbit in \(.applicationName)",
                "Show Orbit lane in \(.applicationName)"
            ],
            shortTitle: "Open Orbit",
            systemImageName: "circle.hexagongrid.fill"
        )
    }
}
