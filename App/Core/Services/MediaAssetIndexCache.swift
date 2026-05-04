import Foundation

protocol MediaAssetIndexCaching {
    func loadSnapshot() async throws -> MediaAssetIndexSnapshot?
    func saveSnapshot(_ snapshot: MediaAssetIndexSnapshot) async throws
    func clearSnapshot() async throws
}

struct PhotoLibraryFingerprint: Codable, Hashable {
    var totalCount: Int
    var leadingIdentifiers: [String]
    var trailingIdentifiers: [String]
}

struct MediaAssetIndexSnapshot: Codable, Hashable {
    var fingerprint: PhotoLibraryFingerprint
    var assets: [MediaAsset]
    var isComplete: Bool
    var updatedAt: Date
}

actor FileBackedMediaAssetIndexCache: MediaAssetIndexCaching {
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

    func loadSnapshot() async throws -> MediaAssetIndexSnapshot? {
        let data = try readFileData()
        guard !data.isEmpty else {
            return nil
        }

        return try decoder.decode(MediaAssetIndexSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: MediaAssetIndexSnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func clearSnapshot() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
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
            .appendingPathComponent("media-asset-index.json", isDirectory: false)
    }
}
