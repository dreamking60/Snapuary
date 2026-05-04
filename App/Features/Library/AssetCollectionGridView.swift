import Photos
import SwiftUI
import UIKit

struct AssetCollectionGridView: UIViewRepresentable {
    let assets: [MediaAsset]
    let thumbnailStore: PhotoLibraryThumbnailStore
    let onSelect: (MediaAsset) -> Void
    let onApproachingEnd: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            thumbnailStore: thumbnailStore,
            onSelect: onSelect,
            onApproachingEnd: onApproachingEnd
        )
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 3
        layout.minimumLineSpacing = 3

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(AssetGridCell.self, forCellWithReuseIdentifier: AssetGridCell.reuseIdentifier)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onApproachingEnd = onApproachingEnd
        context.coordinator.updateAssets(assets, in: collectionView)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
        private let thumbnailStore: PhotoLibraryThumbnailStore
        fileprivate var onSelect: (MediaAsset) -> Void
        fileprivate var onApproachingEnd: (Int) -> Void
        private var assets: [MediaAsset] = []
        private var assetIdentifiers: [String] = []
        private var lastTriggeredIndex = -1

        init(
            thumbnailStore: PhotoLibraryThumbnailStore,
            onSelect: @escaping (MediaAsset) -> Void,
            onApproachingEnd: @escaping (Int) -> Void
        ) {
            self.thumbnailStore = thumbnailStore
            self.onSelect = onSelect
            self.onApproachingEnd = onApproachingEnd
        }

        func updateAssets(_ newAssets: [MediaAsset], in collectionView: UICollectionView) {
            let newIdentifiers = newAssets.map(\.gridIdentifier)
            guard newIdentifiers != assetIdentifiers else {
                return
            }

            assets = newAssets
            assetIdentifiers = newIdentifiers
            if assets.count > lastTriggeredIndex {
                lastTriggeredIndex = max(-1, assets.count - 45)
            }
            collectionView.reloadData()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            assets.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AssetGridCell.reuseIdentifier,
                for: indexPath
            ) as? AssetGridCell else {
                return UICollectionViewCell()
            }

            cell.configure(asset: assets[indexPath.item], thumbnailStore: thumbnailStore)
            triggerLoadMoreIfNeeded(for: indexPath.item)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard assets.indices.contains(indexPath.item) else {
                return
            }

            onSelect(assets[indexPath.item])
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let totalSpacing: CGFloat = 6
            let width = floor((collectionView.bounds.width - totalSpacing) / 3)
            return CGSize(width: width, height: width)
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            if let maxIndex = indexPaths.map(\.item).max() {
                triggerLoadMoreIfNeeded(for: maxIndex)
            }

            let targetSize = preheatTargetSize(for: collectionView)
            let identifiers = indexPaths.compactMap { indexPath in
                assets.indices.contains(indexPath.item) ? assets[indexPath.item].libraryIdentifier : nil
            }

            guard !identifiers.isEmpty else {
                return
            }

            Task { @MainActor in
                thumbnailStore.startCaching(
                    localIdentifiers: identifiers,
                    targetSize: targetSize,
                    contentMode: .aspectFill
                )
            }
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let targetSize = preheatTargetSize(for: collectionView)
            let identifiers = indexPaths.compactMap { indexPath in
                assets.indices.contains(indexPath.item) ? assets[indexPath.item].libraryIdentifier : nil
            }

            guard !identifiers.isEmpty else {
                return
            }

            Task { @MainActor in
                thumbnailStore.stopCaching(
                    localIdentifiers: identifiers,
                    targetSize: targetSize,
                    contentMode: .aspectFill
                )
            }
        }

        private func preheatTargetSize(for collectionView: UICollectionView) -> CGSize {
            let scale = UIScreen.main.scale
            let totalSpacing: CGFloat = 6
            let width = floor((collectionView.bounds.width - totalSpacing) / 3) * scale
            return CGSize(width: width, height: width)
        }

        private func triggerLoadMoreIfNeeded(for index: Int) {
            guard !assets.isEmpty else {
                return
            }

            let triggerIndex = max(assets.count - 30, 0)
            guard index >= triggerIndex,
                  index > lastTriggeredIndex else {
                return
            }

            lastTriggeredIndex = index
            onApproachingEnd(index)
        }
    }
}

private final class AssetGridCell: UICollectionViewCell {
    static let reuseIdentifier = "AssetGridCell"

    private let imageView = UIImageView()
    private let gradientView = GradientView()
    private let titleLabel = UILabel()
    private let badgeStack = UIStackView()
    private weak var thumbnailStore: PhotoLibraryThumbnailStore?
    private var requestID: PHImageRequestID?
    private var representedIdentifier: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailStore?.cancelRequest(requestID)
        requestID = nil
        imageView.image = nil
        titleLabel.text = nil
        badgeStack.arrangedSubviews.forEach { view in
            badgeStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        representedIdentifier = nil
    }

    func configure(asset: MediaAsset, thumbnailStore: PhotoLibraryThumbnailStore) {
        self.thumbnailStore = thumbnailStore
        representedIdentifier = asset.libraryIdentifier
        contentView.backgroundColor = tileBackgroundColor(for: asset)
        titleLabel.text = asset.title

        if asset.isScreenshot {
            badgeStack.addArrangedSubview(makeBadge(systemName: "camera.viewfinder"))
        }

        if asset.isProtectedFromCleanup {
            badgeStack.addArrangedSubview(makeBadge(systemName: "bookmark.fill"))
        }

        guard let libraryIdentifier = asset.libraryIdentifier else {
            imageView.image = nil
            return
        }

        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        requestID = thumbnailStore.requestThumbnail(
            for: libraryIdentifier,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) { [weak self] image in
            guard let self, self.representedIdentifier == libraryIdentifier else {
                return
            }

            self.imageView.image = image
        }
    }

    private func setUpViews() {
        clipsToBounds = true
        contentView.clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        gradientView.translatesAutoresizingMaskIntoConstraints = false

        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        badgeStack.axis = .horizontal
        badgeStack.spacing = 6

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .caption1).bold()
        titleLabel.numberOfLines = 2

        contentView.addSubview(imageView)
        contentView.addSubview(gradientView)
        contentView.addSubview(badgeStack)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            gradientView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.5),

            badgeStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            badgeStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    private func makeBadge(systemName: String) -> UIView {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blurView.layer.cornerRadius = 10
        blurView.clipsToBounds = true

        let iconView = UIImageView(image: UIImage(systemName: systemName))
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 6),
            iconView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -6),
            iconView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 4),
            iconView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -4)
        ])

        return blurView
    }

    private func tileBackgroundColor(for asset: MediaAsset) -> UIColor {
        asset.isScreenshot ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.tertiarySystemBackground
    }
}

private final class GradientView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradientLayer = layer as? CAGradientLayer
        gradientLayer?.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.58).cgColor
        ]
        gradientLayer?.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer?.endPoint = CGPoint(x: 0.5, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else {
            return self
        }

        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
