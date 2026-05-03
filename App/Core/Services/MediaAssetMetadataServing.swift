import Foundation

protocol MediaAssetMetadataServing {
    func fetchAllMetadata() async throws -> [String: MediaAssetMetadataRecord]
    func saveMetadata(_ metadata: MediaAssetMetadataRecord, for libraryIdentifier: String) async throws
    func removeMetadata(for libraryIdentifiers: [String]) async throws
}

struct MediaAssetMetadataRecord: Codable, Hashable {
    var isImportedScreenshotLike: Bool
    var tags: [MediaTag]
    var screenshotRule: ScreenshotRetentionRule?
    var isProtectedFromCleanup: Bool

    static let empty = MediaAssetMetadataRecord(
        isImportedScreenshotLike: false,
        tags: [],
        screenshotRule: nil,
        isProtectedFromCleanup: false
    )
}

actor FileBackedMediaAssetMetadataStore: MediaAssetMetadataServing {
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

    func fetchAllMetadata() async throws -> [String: MediaAssetMetadataRecord] {
        let data = try readFileData()
        guard !data.isEmpty else {
            return [:]
        }

        let file = try decoder.decode(MediaAssetMetadataFile.self, from: data)
        return file.records
    }

    func saveMetadata(_ metadata: MediaAssetMetadataRecord, for libraryIdentifier: String) async throws {
        var records = try await fetchAllMetadata()
        records[libraryIdentifier] = metadata
        try write(records: records)
    }

    func removeMetadata(for libraryIdentifiers: [String]) async throws {
        var records = try await fetchAllMetadata()
        for libraryIdentifier in libraryIdentifiers {
            records.removeValue(forKey: libraryIdentifier)
        }
        try write(records: records)
    }

    private func write(records: [String: MediaAssetMetadataRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let file = MediaAssetMetadataFile(records: records)
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }

    private func readFileData() throws -> Data {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Data()
        }

        return try Data(contentsOf: fileURL)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Snapuary", isDirectory: true)
            .appendingPathComponent("media-asset-metadata.json", isDirectory: false)
    }
}

private struct MediaAssetMetadataFile: Codable, Hashable {
    var records: [String: MediaAssetMetadataRecord]
}
