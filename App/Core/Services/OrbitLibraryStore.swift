import Foundation

protocol OrbitLibraryServing {
    func loadLibrary() async throws -> OrbitLibrarySnapshot
    func saveLibrary(_ snapshot: OrbitLibrarySnapshot) async throws
}

struct OrbitLibrarySnapshot: Codable, Hashable {
    var collections: [OrbitCollection]
    var history: [OrbitSessionEvent]
}

actor FileBackedOrbitLibraryStore: OrbitLibraryServing {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadLibrary() async throws -> OrbitLibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return OrbitLibrarySnapshot(collections: Self.defaultCollections, history: [])
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return OrbitLibrarySnapshot(collections: Self.defaultCollections, history: [])
        }

        let snapshot = try decoder.decode(OrbitLibrarySnapshot.self, from: data)
        if snapshot.collections.isEmpty {
            return OrbitLibrarySnapshot(collections: Self.defaultCollections, history: snapshot.history)
        }
        return snapshot
    }

    func saveLibrary(_ snapshot: OrbitLibrarySnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Snapuary", isDirectory: true)
            .appendingPathComponent("orbit-library.json", isDirectory: false)
    }

    private static var defaultCollections: [OrbitCollection] {
        [
            OrbitCollection(
                id: "receipts",
                name: "Receipts",
                colorHex: "#E07A5F",
                symbolName: "receipt",
                recipe: .archiveReceipts,
                autoRule: .receipt
            ),
            OrbitCollection(
                id: "design-refs",
                name: "Design Refs",
                colorHex: "#6D597A",
                symbolName: "sparkles.rectangle.stack",
                recipe: .collectInspiration,
                autoRule: .designReference
            ),
            OrbitCollection(
                id: "travel",
                name: "Travel",
                colorHex: "#4F7CAC",
                symbolName: "airplane",
                autoRule: .travel
            ),
            OrbitCollection(
                id: "to-post",
                name: "To Post",
                colorHex: "#84A59D",
                symbolName: "square.and.arrow.up",
                autoRule: .toPost
            )
        ]
    }
}
