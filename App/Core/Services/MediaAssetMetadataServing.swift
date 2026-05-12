import Foundation

protocol MediaAssetMetadataServing {
    func fetchAllMetadata() async throws -> [String: MediaAssetMetadataRecord]
    func saveMetadata(_ metadata: MediaAssetMetadataRecord, for libraryIdentifier: String) async throws
    func removeMetadata(for libraryIdentifiers: [String]) async throws
}

struct MediaAssetMetadataRecord: Codable, Hashable {
    var isImportedScreenshotLike: Bool
    var tags: [MediaTag]
    var orbitIDs: [String]
    var screenshotRule: ScreenshotRetentionRule?
    var isProtectedFromCleanup: Bool

    init(
        isImportedScreenshotLike: Bool,
        tags: [MediaTag],
        orbitIDs: [String] = [],
        screenshotRule: ScreenshotRetentionRule?,
        isProtectedFromCleanup: Bool
    ) {
        self.isImportedScreenshotLike = isImportedScreenshotLike
        self.tags = tags
        self.orbitIDs = orbitIDs
        self.screenshotRule = screenshotRule
        self.isProtectedFromCleanup = isProtectedFromCleanup
    }

    private enum CodingKeys: String, CodingKey {
        case isImportedScreenshotLike
        case tags
        case orbitIDs
        case screenshotRule
        case isProtectedFromCleanup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isImportedScreenshotLike = try container.decodeIfPresent(Bool.self, forKey: .isImportedScreenshotLike) ?? false
        tags = try container.decodeIfPresent([MediaTag].self, forKey: .tags) ?? []
        orbitIDs = try container.decodeIfPresent([String].self, forKey: .orbitIDs) ?? []
        screenshotRule = try container.decodeIfPresent(ScreenshotRetentionRule.self, forKey: .screenshotRule)
        isProtectedFromCleanup = try container.decodeIfPresent(Bool.self, forKey: .isProtectedFromCleanup) ?? false
    }

    static let empty = MediaAssetMetadataRecord(
        isImportedScreenshotLike: false,
        tags: [],
        orbitIDs: [],
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
