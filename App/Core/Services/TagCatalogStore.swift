import Foundation

protocol TagCatalogServing {
    func loadEntries() async throws -> [TagLibraryEntry]
    func saveEntries(_ entries: [TagLibraryEntry]) async throws
}

actor FileBackedTagCatalogStore: TagCatalogServing {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadEntries() async throws -> [TagLibraryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try decoder.decode([TagLibraryEntry].self, from: data)
    }

    func saveEntries(_ entries: [TagLibraryEntry]) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Snapuary", isDirectory: true)
            .appendingPathComponent("tag-catalog.json", isDirectory: false)
    }
}
