import Foundation
import Photos

protocol PhotoLibraryServing {
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus
    func libraryFingerprint() async throws -> PhotoLibraryFingerprint
    func refreshAssetIndex() async throws -> Int
    func fetchAssetPage(offset: Int, limit: Int) async throws -> [MediaAsset]
    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws
}

extension PhotoLibraryServing {
    func fetchAssets() async throws -> [MediaAsset] {
        let totalCount = try await refreshAssetIndex()
        guard totalCount > 0 else {
            return []
        }

        return try await fetchAssetPage(offset: 0, limit: totalCount)
    }
}

enum PhotoLibraryAuthorizationStatus: String, Hashable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    var canReadAssets: Bool {
        self == .authorized || self == .limited
    }

    var displayName: String {
        switch self {
        case .notDetermined:
            L10n.text("photo_access.not_determined", fallback: "Not Determined")
        case .authorized:
            L10n.text("photo_access.authorized", fallback: "Authorized")
        case .limited:
            L10n.text("photo_access.limited", fallback: "Limited Access")
        case .denied:
            L10n.text("photo_access.denied", fallback: "Denied")
        case .restricted:
            L10n.text("photo_access.restricted", fallback: "Restricted")
        }
    }
}

enum PhotoLibraryError: Error {
    case unauthorized(PhotoLibraryAuthorizationStatus)
    case deletionFailed
}

struct MockPhotoLibraryService: PhotoLibraryServing {
    private let mockAssets: [MediaAsset] = [
        MediaAsset(
            id: UUID(),
            libraryIdentifier: "mock-screenshot-1",
            title: "Order receipt screenshot",
            createdAt: .now.addingTimeInterval(-86_400),
            addedAt: .now.addingTimeInterval(-86_400),
            tags: [
                MediaTag(id: UUID(), name: "Finance", colorHex: "#E07A5F"),
                MediaTag(id: UUID(), name: "Receipt", colorHex: "#81B29A")
            ],
            kind: .systemScreenshot,
            screenshotRule: ScreenshotRetentionRule(
                mode: .preset(.oneMonth),
                anchor: .creationDate
            ),
            isProtectedFromCleanup: false
        ),
        MediaAsset(
            id: UUID(),
            libraryIdentifier: "mock-screenshot-2",
            title: "Favorite UI capture",
            createdAt: .now.addingTimeInterval(-86_400 * 3),
            addedAt: .now.addingTimeInterval(-86_400 * 3),
            tags: [
                MediaTag(id: UUID(), name: "Collection", colorHex: "#3D405B"),
                MediaTag(id: UUID(), name: "Design", colorHex: "#F2CC8F")
            ],
            kind: .systemScreenshot,
            screenshotRule: ScreenshotRetentionRule(
                mode: .preset(.oneMonth),
                anchor: .creationDate
            ),
            isProtectedFromCleanup: true
        ),
        MediaAsset(
            id: UUID(),
            libraryIdentifier: "mock-imported-1",
            title: "Imported chat capture",
            createdAt: .now.addingTimeInterval(-86_400 * 14),
            addedAt: .now.addingTimeInterval(-86_400 * 2),
            tags: [
                MediaTag(id: UUID(), name: "Reference", colorHex: "#6D597A")
            ],
            kind: .importedScreenshotLike,
            screenshotRule: ScreenshotRetentionRule(
                mode: .preset(.oneMonth),
                anchor: .addedDate
            ),
            isProtectedFromCleanup: false
        ),
        MediaAsset(
            id: UUID(),
            libraryIdentifier: "mock-photo-1",
            title: "Family dinner",
            createdAt: .now.addingTimeInterval(-86_400 * 10),
            addedAt: .now.addingTimeInterval(-86_400 * 10),
            tags: [
                MediaTag(id: UUID(), name: "Family", colorHex: "#C8553D")
            ],
            kind: .photo,
            screenshotRule: nil,
            isProtectedFromCleanup: false
        )
    ]

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        .authorized
    }

    func libraryFingerprint() async throws -> PhotoLibraryFingerprint {
        PhotoLibraryFingerprint(
            totalCount: mockAssets.count,
            leadingIdentifiers: mockAssets.prefix(8).compactMap(\.libraryIdentifier),
            trailingIdentifiers: mockAssets.suffix(8).compactMap(\.libraryIdentifier)
        )
    }

    func refreshAssetIndex() async throws -> Int {
        mockAssets.count
    }

    func fetchAssetPage(offset: Int, limit: Int) async throws -> [MediaAsset] {
        guard limit > 0, offset < mockAssets.count else {
            return []
        }

        let endIndex = min(offset + limit, mockAssets.count)
        return Array(mockAssets[offset..<endIndex])
    }

    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws {
    }
}

struct PhotoKitPhotoLibraryService: PhotoLibraryServing {
    private let thumbnailStore: PhotoLibraryThumbnailStore
    private let assetSource = PhotoLibraryAssetSource()

    init(thumbnailStore: PhotoLibraryThumbnailStore = .empty) {
        self.thumbnailStore = thumbnailStore
    }

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite).snapuaryStatus
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }

        return status.snapuaryStatus
    }

    func libraryFingerprint() async throws -> PhotoLibraryFingerprint {
        let status = authorizationStatus()
        guard status.canReadAssets else {
            throw PhotoLibraryError.unauthorized(status)
        }

        return await assetSource.refreshSnapshot(thumbnailStore: thumbnailStore).fingerprint
    }

    func refreshAssetIndex() async throws -> Int {
        let status = authorizationStatus()
        guard status.canReadAssets else {
            throw PhotoLibraryError.unauthorized(status)
        }

        return await assetSource.refreshSnapshot(thumbnailStore: thumbnailStore).fingerprint.totalCount
    }

    func fetchAssetPage(offset: Int, limit: Int) async throws -> [MediaAsset] {
        let status = authorizationStatus()
        guard status.canReadAssets else {
            throw PhotoLibraryError.unauthorized(status)
        }

        guard limit > 0 else {
            return []
        }

        return await assetSource.page(
            offset: offset,
            limit: limit,
            thumbnailStore: thumbnailStore
        )
    }

    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws {
        guard !identifiers.isEmpty else {
            return
        }

        let status = authorizationStatus()
        guard status.canReadAssets else {
            throw PhotoLibraryError.unauthorized(status)
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibraryError.deletionFailed)
                }
            }
        }
    }

    static func map(asset: PHAsset, screenshotIdentifiers: Set<String> = []) -> MediaAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let descriptor = PhotoLibraryAssetDescriptor(
            localIdentifier: asset.localIdentifier,
            mediaSubtypesRawValue: asset.mediaSubtypes.rawValue,
            creationDate: asset.creationDate,
            addedDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            originalFilename: resources.first?.originalFilename,
            isInSystemScreenshotAlbum: screenshotIdentifiers.contains(asset.localIdentifier)
        )

        return map(descriptor: descriptor)
    }

    static func map(descriptor: PhotoLibraryAssetDescriptor) -> MediaAsset {
        let createdAt = descriptor.creationDate ?? descriptor.addedDate ?? .now
        let addedAt = descriptor.addedDate ?? descriptor.creationDate ?? .now
        let kind: MediaAssetKind = descriptor.isSystemScreenshot ? .systemScreenshot : .photo
        let title = descriptor.defaultTitle(for: kind)

        return MediaAsset(
            id: UUID(),
            libraryIdentifier: descriptor.localIdentifier,
            title: title,
            createdAt: createdAt,
            addedAt: addedAt,
            tags: [],
            kind: kind,
            screenshotRule: descriptor.isSystemScreenshot
                ? ScreenshotRetentionRule(mode: .preset(.oneMonth), anchor: .creationDate)
                : nil,
            isProtectedFromCleanup: false
        )
    }
}

struct MetadataMergingPhotoLibraryService: PhotoLibraryServing {
    let base: PhotoLibraryServing
    let metadataStore: MediaAssetMetadataServing

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        base.authorizationStatus()
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        await base.requestAuthorization()
    }

    func libraryFingerprint() async throws -> PhotoLibraryFingerprint {
        try await base.libraryFingerprint()
    }

    func refreshAssetIndex() async throws -> Int {
        try await base.refreshAssetIndex()
    }

    func fetchAssetPage(offset: Int, limit: Int) async throws -> [MediaAsset] {
        async let assetsTask = base.fetchAssetPage(offset: offset, limit: limit)
        async let metadataTask = metadataStore.fetchAllMetadata()

        let (assets, metadataByIdentifier) = try await (assetsTask, metadataTask)
        return assets.map { asset in
            guard let libraryIdentifier = asset.libraryIdentifier,
                  let metadata = metadataByIdentifier[libraryIdentifier] else {
                return asset
            }

            return merge(asset: asset, metadata: metadata)
        }
    }

    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws {
        try await base.deleteAssets(withLocalIdentifiers: identifiers)
    }

    private func merge(asset: MediaAsset, metadata: MediaAssetMetadataRecord) -> MediaAsset {
        var mergedAsset = asset

        if metadata.isImportedScreenshotLike && asset.kind == .photo {
            mergedAsset.kind = .importedScreenshotLike
        }

        mergedAsset.tags = metadata.tags
        mergedAsset.orbitIDs = metadata.orbitIDs
        mergedAsset.isProtectedFromCleanup = metadata.isProtectedFromCleanup

        if mergedAsset.isScreenshot {
            mergedAsset.screenshotRule = metadata.screenshotRule ?? asset.screenshotRule
        } else {
            mergedAsset.screenshotRule = nil
        }

        return mergedAsset
    }
}

private actor PhotoLibraryAssetSource {
    private var fetchResult: PHFetchResult<PHAsset>?

    struct Snapshot {
        let fingerprint: PhotoLibraryFingerprint
    }

    func refreshSnapshot(thumbnailStore: PhotoLibraryThumbnailStore) -> Snapshot {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        self.fetchResult = fetchResult

        let initialWarmupCount = min(fetchResult.count, 180)
        if initialWarmupCount > 0 {
            var warmupAssets: [PHAsset] = []
            warmupAssets.reserveCapacity(initialWarmupCount)
            for index in 0..<initialWarmupCount {
                warmupAssets.append(fetchResult.object(at: index))
            }
            thumbnailStore.register(assets: warmupAssets)
        }

        let fingerprint = PhotoLibraryFingerprint(
            totalCount: fetchResult.count,
            leadingIdentifiers: identifiers(in: fetchResult, range: 0..<min(fetchResult.count, 8)),
            trailingIdentifiers: identifiers(
                in: fetchResult,
                range: max(fetchResult.count - 8, 0)..<fetchResult.count
            )
        )

        return Snapshot(fingerprint: fingerprint)
    }

    func page(
        offset: Int,
        limit: Int,
        thumbnailStore: PhotoLibraryThumbnailStore
    ) -> [MediaAsset] {
        guard let fetchResult,
              offset < fetchResult.count else {
            return []
        }

        let endIndex = min(offset + limit, fetchResult.count)
        var pageAssets: [MediaAsset] = []
        pageAssets.reserveCapacity(endIndex - offset)
        var photoAssets: [PHAsset] = []
        photoAssets.reserveCapacity(endIndex - offset)

        for index in offset..<endIndex {
            let asset = fetchResult.object(at: index)
            photoAssets.append(asset)
            pageAssets.append(PhotoKitPhotoLibraryService.map(asset: asset))
        }

        thumbnailStore.register(assets: photoAssets)
        return pageAssets
    }

    private func identifiers(in fetchResult: PHFetchResult<PHAsset>, range: Range<Int>) -> [String] {
        guard !range.isEmpty else {
            return []
        }

        var identifiers: [String] = []
        identifiers.reserveCapacity(range.count)

        for index in range {
            identifiers.append(fetchResult.object(at: index).localIdentifier)
        }

        return identifiers
    }
}

struct PhotoLibraryAssetDescriptor: Hashable {
    let localIdentifier: String
    let mediaSubtypesRawValue: UInt
    let creationDate: Date?
    let addedDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let originalFilename: String?
    let isInSystemScreenshotAlbum: Bool

    var isSystemScreenshot: Bool {
        let screenshotRawValue = PHAssetMediaSubtype.photoScreenshot.rawValue
        return isInSystemScreenshotAlbum || (mediaSubtypesRawValue & screenshotRawValue) != 0
    }

    func defaultTitle(for kind: MediaAssetKind) -> String {
        let date = creationDate ?? addedDate
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let dateSuffix = date.map { formatter.string(from: $0) } ?? L10n.text("asset.unknown_date", fallback: "Unknown Date")
        let size = pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth)x\(pixelHeight)" : nil

        switch kind {
        case .systemScreenshot:
            if let size {
                return L10n.text("asset.generated_title.screenshot_size", fallback: "Screenshot %@ · %@", dateSuffix, size)
            }
            return L10n.text("asset.generated_title.screenshot", fallback: "Screenshot %@", dateSuffix)
        case .importedScreenshotLike:
            return L10n.text("asset.generated_title.imported_screenshot", fallback: "Imported Screenshot %@", dateSuffix)
        case .photo:
            if let size {
                return L10n.text("asset.generated_title.photo_size", fallback: "Photo %@ · %@", dateSuffix, size)
            }
            return L10n.text("asset.generated_title.photo", fallback: "Photo %@", dateSuffix)
        }
    }
}

private extension PHAuthorizationStatus {
    var snapuaryStatus: PhotoLibraryAuthorizationStatus {
        switch self {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .limited:
            .limited
        @unknown default:
            .restricted
        }
    }
}
