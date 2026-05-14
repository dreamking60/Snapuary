import Foundation
import Photos
import UIKit

/// Shared thumbnail and preview image cache backed by `PHCachingImageManager`.
final class PhotoLibraryThumbnailStore {
    static let empty = PhotoLibraryThumbnailStore()

    private let imageManager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    private let assetLock = NSLock()
    private var assetsByIdentifier: [String: PHAsset] = [:]

    /// Registers one `PHAsset` so future image requests can avoid another PhotoKit fetch.
    func register(asset: PHAsset) {
        assetLock.lock()
        assetsByIdentifier[asset.localIdentifier] = asset
        assetLock.unlock()
    }

    /// Registers a batch of `PHAsset` values, typically after paging from PhotoKit.
    func register(assets: [PHAsset]) {
        for asset in assets {
            register(asset: asset)
        }
    }

    /// Returns a cached or asynchronously requested thumbnail for a library asset.
    @discardableResult
    func requestThumbnail(
        for localIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID? {
        let cacheKey = thumbnailCacheKey(for: localIdentifier, targetSize: targetSize, contentMode: contentMode)
        if let cachedImage = cache.object(forKey: cacheKey as NSString) {
            completion(cachedImage)
            return nil
        }

        guard let asset = asset(for: localIdentifier) else {
            completion(nil)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, _ in
            if let image {
                self?.cache.setObject(image, forKey: cacheKey as NSString)
            }
            completion(image)
        }
    }

    /// Requests a larger preview image suitable for full-screen inspection.
    @discardableResult
    func requestPreviewImage(
        for localIdentifier: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID? {
        guard let asset = asset(for: localIdentifier) else {
            completion(nil)
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// Cancels an in-flight PhotoKit image request.
    func cancelRequest(_ requestID: PHImageRequestID?) {
        guard let requestID else {
            return
        }

        imageManager.cancelImageRequest(requestID)
    }

    /// Starts preheating thumbnails for assets that are about to scroll onscreen.
    func startCaching(
        localIdentifiers: [String],
        targetSize: CGSize,
        contentMode: PHImageContentMode
    ) {
        let assets = localIdentifiers.compactMap { asset(for: $0) }
        guard !assets.isEmpty else {
            return
        }

        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: nil
        )
    }

    /// Stops preheating thumbnails for assets that moved away from the scroll window.
    func stopCaching(
        localIdentifiers: [String],
        targetSize: CGSize,
        contentMode: PHImageContentMode
    ) {
        let assets = localIdentifiers.compactMap { asset(for: $0) }
        guard !assets.isEmpty else {
            return
        }

        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: nil
        )
    }

    /// Returns a cached `PHAsset` or lazily fetches it from PhotoKit by identifier.
    private func asset(for localIdentifier: String) -> PHAsset? {
        assetLock.lock()
        if let asset = assetsByIdentifier[localIdentifier] {
            assetLock.unlock()
            return asset
        }
        assetLock.unlock()

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            return nil
        }

        assetLock.lock()
        assetsByIdentifier[localIdentifier] = asset
        assetLock.unlock()
        return asset
    }

    /// Builds a stable cache key that separates identifiers by target size and content mode.
    private func thumbnailCacheKey(
        for localIdentifier: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode
    ) -> String {
        let roundedWidth = Int(targetSize.width.rounded())
        let roundedHeight = Int(targetSize.height.rounded())
        return "\(localIdentifier)#\(roundedWidth)x\(roundedHeight)#\(contentMode.rawValue)"
    }
}
