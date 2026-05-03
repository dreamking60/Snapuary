import Foundation
import Photos

protocol PhotoLibraryServing {
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus
    func fetchAssets() async throws -> [MediaAsset]
    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws
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
            "Not Determined"
        case .authorized:
            "Authorized"
        case .limited:
            "Limited Access"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }
}

enum PhotoLibraryError: Error {
    case unauthorized(PhotoLibraryAuthorizationStatus)
    case deletionFailed
}

struct MockPhotoLibraryService: PhotoLibraryServing {
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        .authorized
    }

    func fetchAssets() async throws -> [MediaAsset] {
        [
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
                    mode: .preset(.oneWeek),
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
                    mode: .preset(.threeMonths),
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
                    mode: .customDays(30),
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
    }

    func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws {
    }
}

struct PhotoKitPhotoLibraryService: PhotoLibraryServing {
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

    func fetchAssets() async throws -> [MediaAsset] {
        let status = authorizationStatus()
        guard status.canReadAssets else {
            throw PhotoLibraryError.unauthorized(status)
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [MediaAsset] = []
        assets.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(Self.map(asset: asset))
        }

        return assets
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

    static func map(asset: PHAsset) -> MediaAsset {
        let descriptor = PhotoLibraryAssetDescriptor(
            localIdentifier: asset.localIdentifier,
            mediaSubtypesRawValue: asset.mediaSubtypes.rawValue,
            creationDate: asset.creationDate,
            addedDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
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
                ? ScreenshotRetentionRule(mode: .preset(.thirtyDays), anchor: .creationDate)
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

    func fetchAssets() async throws -> [MediaAsset] {
        async let assetsTask = base.fetchAssets()
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
        mergedAsset.isProtectedFromCleanup = metadata.isProtectedFromCleanup

        if mergedAsset.isScreenshot {
            mergedAsset.screenshotRule = metadata.screenshotRule ?? asset.screenshotRule
        } else {
            mergedAsset.screenshotRule = nil
        }

        return mergedAsset
    }
}

struct PhotoLibraryAssetDescriptor: Hashable {
    let localIdentifier: String
    let mediaSubtypesRawValue: UInt
    let creationDate: Date?
    let addedDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int

    var isSystemScreenshot: Bool {
        let screenshotRawValue = PHAssetMediaSubtype.photoScreenshot.rawValue
        return (mediaSubtypesRawValue & screenshotRawValue) != 0
    }

    func defaultTitle(for kind: MediaAssetKind) -> String {
        let date = creationDate ?? addedDate
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let dateSuffix = date.map { formatter.string(from: $0) } ?? "Unknown Date"
        let size = pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth)x\(pixelHeight)" : nil

        switch kind {
        case .systemScreenshot:
            if let size {
                return "Screenshot \(dateSuffix) · \(size)"
            }
            return "Screenshot \(dateSuffix)"
        case .importedScreenshotLike:
            return "Imported Screenshot \(dateSuffix)"
        case .photo:
            if let size {
                return "Photo \(dateSuffix) · \(size)"
            }
            return "Photo \(dateSuffix)"
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
