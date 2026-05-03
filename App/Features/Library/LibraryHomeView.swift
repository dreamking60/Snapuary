import Photos
import SwiftUI

struct LibraryHomeView: View {
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                if let message = viewModel.authorizationErrorMessage {
                    LibraryAuthorizationView(
                        message: message,
                        authorizationStatus: viewModel.authorizationStatus,
                        onRequestAccess: {
                            await viewModel.requestPhotoLibraryAccess()
                        }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            LibraryHeader(viewModel: viewModel)
                            LibraryFilterStrip(viewModel: viewModel)
                            LibraryGrid(
                                assets: viewModel.visibleAssets,
                                columns: gridColumns,
                                onSelect: { selectedAsset = $0 }
                            )
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search title or tag")
            .task {
                if viewModel.authorizationStatus == .notDetermined {
                    await viewModel.requestPhotoLibraryAccess()
                } else {
                    await viewModel.load()
                }
            }
            .alert(
                viewModel.cleanupPromptTitle,
                isPresented: Binding(
                    get: { viewModel.shouldPromptForCleanup },
                    set: { newValue in
                        if !newValue {
                            viewModel.dismissCleanupPrompt()
                        }
                    }
                )
            ) {
                Button("Later", role: .cancel) {
                    viewModel.dismissCleanupPrompt()
                }
                Button("Clean Now", role: .destructive) {
                    Task {
                        await viewModel.runCleanupNow()
                    }
                }
            } message: {
                Text(viewModel.cleanupPromptMessage)
            }
            .sheet(item: $selectedAsset) { asset in
                AssetEditorSheet(
                    asset: asset,
                    tagLibrary: viewModel.tagLibrary,
                    onRefresh: {
                        await viewModel.load()
                        selectedAsset = refreshedAsset(from: asset, in: viewModel.assets)
                    },
                    onToggleProtection: { await viewModel.toggleProtection(for: asset) },
                    onToggleScreenshotLike: { await viewModel.toggleImportedScreenshotLike(for: asset) },
                    onApplyRetentionRule: { rule in
                        await viewModel.applyRetentionRule(rule, to: asset)
                    },
                    onAddTag: { name, colorHex in
                        await viewModel.addTag(name: name, colorHex: colorHex, to: asset)
                    },
                    onAddTags: { entries in
                        await viewModel.addTags(entries, to: asset)
                    },
                    onRemoveTag: { tag in
                        await viewModel.removeTag(tag, from: asset)
                    }
                )
                .presentationDetents([.large])
            }
        }
    }

    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }
}

struct CleanupHomeView: View {
    @State private var viewModel: LibraryHomeViewModel
    @State private var selectedAsset: MediaAsset?

    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let message = viewModel.authorizationErrorMessage {
                        SnapuaryCard(title: "Photo Access") {
                            Text(message)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SnapshotOverviewCard(viewModel: viewModel)
                    CleanupReminderCard(viewModel: viewModel)
                    DefaultCleanupPoolCard(
                        title: "Default Cleanup Area",
                        subtitle: "Untagged screenshots automatically collect here until you classify or protect them.",
                        assets: viewModel.untaggedScreenshotAssets,
                        emptyText: "Every screenshot is either tagged, protected, or no screenshots have been found yet.",
                        onSelect: { selectedAsset = $0 }
                    )
                    DefaultCleanupPoolCard(
                        title: "Tagged Screenshots",
                        subtitle: "Tagged screenshots stay visible here for review, but are not in the default catch-all bucket.",
                        assets: viewModel.taggedScreenshotAssets,
                        emptyText: "No tagged screenshots yet.",
                        onSelect: { selectedAsset = $0 }
                    )
                    CleanupQueueCard(viewModel: viewModel, onSelect: { selectedAsset = $0 })
                }
                .padding()
            }
            .navigationTitle("Cleanup")
            .task {
                if viewModel.authorizationStatus == .notDetermined {
                    await viewModel.requestPhotoLibraryAccess()
                } else {
                    await viewModel.load()
                }
            }
            .alert(
                viewModel.cleanupPromptTitle,
                isPresented: Binding(
                    get: { viewModel.shouldPromptForCleanup },
                    set: { newValue in
                        if !newValue {
                            viewModel.dismissCleanupPrompt()
                        }
                    }
                )
            ) {
                Button("Later", role: .cancel) {
                    viewModel.dismissCleanupPrompt()
                }
                Button("Clean Now", role: .destructive) {
                    Task {
                        await viewModel.runCleanupNow()
                    }
                }
            } message: {
                Text(viewModel.cleanupPromptMessage)
            }
            .sheet(item: $selectedAsset) { asset in
                AssetEditorSheet(
                    asset: asset,
                    tagLibrary: viewModel.tagLibrary,
                    onRefresh: {
                        await viewModel.load()
                        selectedAsset = refreshedAsset(from: asset, in: viewModel.assets)
                    },
                    onToggleProtection: { await viewModel.toggleProtection(for: asset) },
                    onToggleScreenshotLike: { await viewModel.toggleImportedScreenshotLike(for: asset) },
                    onApplyRetentionRule: { rule in
                        await viewModel.applyRetentionRule(rule, to: asset)
                    },
                    onAddTag: { name, colorHex in
                        await viewModel.addTag(name: name, colorHex: colorHex, to: asset)
                    },
                    onAddTags: { entries in
                        await viewModel.addTags(entries, to: asset)
                    },
                    onRemoveTag: { tag in
                        await viewModel.removeTag(tag, from: asset)
                    }
                )
                .presentationDetents([.large])
            }
        }
    }

    private func refreshedAsset(from asset: MediaAsset, in assets: [MediaAsset]) -> MediaAsset? {
        guard let libraryIdentifier = asset.libraryIdentifier else {
            return assets.first(where: { $0.id == asset.id })
        }

        return assets.first(where: { $0.libraryIdentifier == libraryIdentifier })
    }
}

private struct LibraryAuthorizationView: View {
    let message: String
    let authorizationStatus: PhotoLibraryAuthorizationStatus
    let onRequestAccess: () async -> Void

    var body: some View {
        ScrollView {
            SnapuaryCard(title: "Photo Access") {
                Text(message)
                    .foregroundStyle(.secondary)

                if authorizationStatus == .notDetermined {
                    Button("Allow Photo Access") {
                        Task {
                            await onRequestAccess()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}

private struct LibraryHeader: View {
    let viewModel: LibraryHomeViewModel

    var body: some View {
        SnapuaryCard(title: "Browse") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap any photo to tag it, mark it as a screenshot, protect it, or set cleanup rules.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    PhotoCountBadge(title: "All", count: viewModel.filteredAssets.count)
                    PhotoCountBadge(title: "Screenshots", count: viewModel.screenshotAssets.count)
                    PhotoCountBadge(title: "Photos", count: viewModel.nonScreenshotAssets.count)
                }
            }
        }
    }
}

private struct LibraryFilterStrip: View {
    @Bindable var viewModel: LibraryHomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Collection", selection: $viewModel.selectedCollection) {
                ForEach(LibraryCollection.allCases) { collection in
                    Text(collection.title).tag(collection)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All Tags",
                        isSelected: viewModel.selectedTag == nil
                    ) {
                        viewModel.selectedTag = nil
                    }

                    ForEach(viewModel.availableTags) { tag in
                        FilterChip(
                            title: tag.name,
                            isSelected: viewModel.selectedTag?.normalizedName == tag.normalizedName
                        ) {
                            viewModel.toggleTag(tag)
                        }
                    }
                }
            }

            if !viewModel.searchText.isEmpty || viewModel.selectedTag != nil {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .font(.footnote)
            }
        }
    }
}

private struct LibraryGrid: View {
    let assets: [MediaAsset]
    let columns: [GridItem]
    let onSelect: (MediaAsset) -> Void

    var body: some View {
        if assets.isEmpty {
            SnapuaryCard(title: "No Results") {
                Text("No photos match the current collection, search, or tag filter.")
                    .foregroundStyle(.secondary)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets) { asset in
                    AssetGridTile(asset: asset) {
                        onSelect(asset)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct SnapshotOverviewCard: View {
    let viewModel: LibraryHomeViewModel

    var body: some View {
        SnapuaryCard(title: "Cleanup Overview") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(label: "Screenshots", value: "\(viewModel.cleanupSummary.totalScreenshotCount)")
                StatTile(label: "Auto-managed", value: "\(viewModel.cleanupSummary.autoManagedCount)")
                StatTile(label: "Expiring Soon", value: "\(viewModel.cleanupSummary.expiringSoonCount)")
                StatTile(label: "Protected", value: "\(viewModel.cleanupSummary.protectedCount)")
                StatTile(label: "Ready to Clean", value: "\(viewModel.cleanupSummary.readyToCleanCount)")
            }
        }
    }
}

private struct CleanupReminderCard: View {
    let viewModel: LibraryHomeViewModel

    var body: some View {
        SnapuaryCard(title: "Cleanup Reminder") {
            Text(statusLine)
                .foregroundStyle(.secondary)

            if let reminder = viewModel.nextCleanupReminder {
                Text("Next reminder: \(reminder.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                Text("Assets due that day: \(reminder.candidateCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.cleanupReminderStatus == .notDetermined || viewModel.cleanupReminderStatus == .denied {
                Button("Enable Cleanup Reminders") {
                    Task {
                        await viewModel.requestCleanupReminderPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(viewModel.isSchedulingReminder ? "Scheduling..." : "Schedule Next Reminder") {
                    Task {
                        await viewModel.scheduleNextCleanupReminder()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSchedulingReminder)
            }
        }
    }

    private var statusLine: String {
        switch viewModel.cleanupReminderStatus {
        case .notDetermined:
            return "Notifications are not configured yet."
        case .denied:
            return "Notifications are disabled. Enable them in Settings to get cleanup reminders."
        case .authorized:
            return "Cleanup reminders are enabled."
        case .provisional:
            return "Cleanup reminders are provisionally authorized."
        case .ephemeral:
            return "Cleanup reminders are temporarily authorized."
        }
    }
}

private struct CleanupQueueCard: View {
    let viewModel: LibraryHomeViewModel
    let onSelect: (MediaAsset) -> Void

    var body: some View {
        SnapuaryCard(title: "Cleanup Queue") {
            if let result = viewModel.lastCleanupResult {
                Text("Last cleanup deleted \(result.deletedCount) screenshot(s).")
                    .foregroundStyle(.secondary)
            }

            if viewModel.cleanupCandidates.isEmpty {
                Text("No expired screenshots are waiting for cleanup.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.cleanupCandidates) { asset in
                    Button {
                        onSelect(asset)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(asset.title)
                                    .font(.subheadline.weight(.medium))
                                if let expirationDate = asset.expirationDate {
                                    Text("Expired \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(asset.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                Button(viewModel.isRunningCleanup ? "Cleaning..." : "Run Cleanup Now") {
                    Task {
                        await viewModel.runCleanupNow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunningCleanup)
            }
        }
    }
}

private struct DefaultCleanupPoolCard: View {
    let title: String
    let subtitle: String
    let assets: [MediaAsset]
    let emptyText: String
    let onSelect: (MediaAsset) -> Void

    var body: some View {
        SnapuaryCard(title: title) {
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if assets.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets) { asset in
                    AssetRow(asset: asset) {
                        onSelect(asset)
                    }
                }
            }
        }
    }
}

private struct AssetRow: View {
    let asset: MediaAsset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                PhotoThumbnailView(asset: asset, cornerRadius: 12)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(asset.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if asset.isProtectedFromCleanup {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(asset.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let expirationDate = asset.expirationDate {
                        Text("Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !asset.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(asset.tags) { tag in
                                    TagPill(tag: tag)
                                }
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct AssetGridTile: View {
    let asset: MediaAsset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(tileBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        PhotoThumbnailView(asset: asset, cornerRadius: 0, contentMode: .fill)
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            if asset.isScreenshot {
                                TileBadge(systemImage: "camera.viewfinder")
                            }
                            if asset.isProtectedFromCleanup {
                                TileBadge(systemImage: "bookmark.fill")
                            }
                        }
                        .padding(8)
                    }

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.58)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)

                    if !asset.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(asset.tags.prefix(2)) { tag in
                                    CompactTagPill(tag: tag)
                                }
                                if asset.tags.count > 2 {
                                    Text("+\(asset.tags.count - 2)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.white.opacity(0.9))
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .buttonStyle(.plain)
    }

    private var tileBackground: LinearGradient {
        if asset.isScreenshot {
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PhotoThumbnailView: View {
    let asset: MediaAsset
    let cornerRadius: CGFloat
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(asset.isScreenshot ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: asset.isScreenshot ? "camera.viewfinder" : "photo")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(asset.isScreenshot ? Color.accentColor : Color.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: asset.libraryIdentifier) {
            await loadThumbnailIfNeeded()
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard image == nil,
              let libraryIdentifier = asset.libraryIdentifier else {
            return
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [libraryIdentifier], options: nil)
        guard let photoAsset = result.firstObject else {
            return
        }

        let targetSize = CGSize(width: 300, height: 300)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHCachingImageManager.default().requestImage(
            for: photoAsset,
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: options
        ) { renderedImage, _ in
            image = renderedImage
        }
    }
}

private struct AssetEditorSheet: View {
    let asset: MediaAsset
    let tagLibrary: [TagLibraryEntry]
    let onRefresh: () async -> Void
    let onToggleProtection: () async -> Void
    let onToggleScreenshotLike: () async -> Void
    let onApplyRetentionRule: (ScreenshotRetentionRule) async -> Void
    let onAddTag: (String, String) async -> Void
    let onAddTags: ([TagLibraryEntry]) async -> Void
    let onRemoveTag: (MediaTag) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(asset.title)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 8) {
                            AssetBadge(
                                title: asset.kind.displayName,
                                systemImage: asset.isScreenshot ? "camera.viewfinder" : "photo"
                            )

                            if asset.isProtectedFromCleanup {
                                AssetBadge(title: "Protected", systemImage: "bookmark.fill")
                            }
                        }

                        if let expirationDate = asset.expirationDate {
                            Text("Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Overview") {
                    LabeledContent("Created", value: asset.createdAt.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Added", value: asset.addedAt.formatted(date: .abbreviated, time: .omitted))
                    if let rule = asset.screenshotRule {
                        LabeledContent("Cleanup Rule", value: rule.displayName)
                        LabeledContent("Anchor", value: rule.anchor == .creationDate ? "Created Date" : "Added Date")
                    }
                }

                Section("Actions") {
                    if asset.isScreenshot {
                        Button(asset.isProtectedFromCleanup ? "Remove Protection" : "Protect from Cleanup") {
                            Task {
                                await onToggleProtection()
                                await onRefresh()
                            }
                        }
                    }

                    if asset.kind == .photo || asset.kind == .importedScreenshotLike {
                        Button(asset.kind == .importedScreenshotLike ? "Back to Photo" : "Treat as Screenshot") {
                            Task {
                                await onToggleScreenshotLike()
                                await onRefresh()
                            }
                        }
                    }
                }

                Section("Editors") {
                    if asset.isScreenshot {
                        NavigationLink {
                            AssetRuleEditorView(
                                asset: asset,
                                onRefresh: onRefresh,
                                onApplyRetentionRule: onApplyRetentionRule
                            )
                        } label: {
                            EditorRow(
                                title: "Rule Editor",
                                subtitle: asset.screenshotRule?.displayName ?? "No rule"
                            )
                        }
                    }

                    NavigationLink {
                        AssetTagManagerView(
                            asset: asset,
                            tagLibrary: tagLibrary,
                            onRefresh: onRefresh,
                            onAddTag: onAddTag,
                            onAddTags: onAddTags,
                            onRemoveTag: onRemoveTag
                        )
                    } label: {
                        EditorRow(
                            title: "Tag Manager",
                            subtitle: asset.tags.isEmpty ? "No tags" : "\(asset.tags.count) tags"
                        )
                    }
                }
            }
            .navigationTitle("Manage Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AssetRuleEditorView: View {
    let asset: MediaAsset
    let onRefresh: () async -> Void
    let onApplyRetentionRule: (ScreenshotRetentionRule) async -> Void

    @State private var customMinuteCount = "1"
    @State private var selectedAnchor: ScreenshotRetentionRule.Anchor = .creationDate

    var body: some View {
        Form {
            Section("Current Rule") {
                if let rule = asset.screenshotRule {
                    LabeledContent("Mode", value: rule.displayName)
                    LabeledContent("Anchor", value: rule.anchor == .creationDate ? "Created Date" : "Added Date")
                    if let expirationDate = asset.expirationDate {
                        LabeledContent("Expires", value: expirationDate.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    Text("No cleanup rule is set.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Anchor") {
                Picker("Start From", selection: $selectedAnchor) {
                    Text("Created").tag(ScreenshotRetentionRule.Anchor.creationDate)
                    Text("Added").tag(ScreenshotRetentionRule.Anchor.addedDate)
                }
                .pickerStyle(.segmented)
            }

            Section("Presets") {
                ForEach(ScreenshotRetentionRule.RetentionPreset.allCases) { preset in
                    Button(preset.displayName) {
                        Task {
                            await onApplyRetentionRule(
                                ScreenshotRetentionRule(mode: .preset(preset), anchor: selectedAnchor)
                            )
                            await onRefresh()
                        }
                    }
                }
            }

            Section("Custom Minutes") {
                HStack {
                    TextField("Minutes", text: $customMinuteCount)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Apply") {
                        guard let minutes = Int(customMinuteCount), minutes >= 1 else {
                            return
                        }

                        Task {
                            await onApplyRetentionRule(
                                ScreenshotRetentionRule(mode: .customMinutes(minutes), anchor: selectedAnchor)
                            )
                            await onRefresh()
                        }
                    }
                }
                Text("Minimum is 1 minute so you can verify auto-cleanup quickly during testing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Rule Editor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedAnchor = asset.screenshotRule?.anchor ?? .creationDate
            if case let .customMinutes(minutes)? = asset.screenshotRule?.mode {
                customMinuteCount = String(minutes)
            }
        }
    }
}

private struct AssetTagManagerView: View {
    let asset: MediaAsset
    let tagLibrary: [TagLibraryEntry]
    let onRefresh: () async -> Void
    let onAddTag: (String, String) async -> Void
    let onAddTags: ([TagLibraryEntry]) async -> Void
    let onRemoveTag: (MediaTag) async -> Void

    @State private var draftTagName = ""
    @State private var selectedBatchTagIDs = Set<String>()

    var body: some View {
        Form {
            Section("Current Tags") {
                if asset.tags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(asset.tags) { tag in
                        HStack {
                            TagPill(tag: tag)
                            Spacer()
                            Button("Remove") {
                                Task {
                                    await onRemoveTag(tag)
                                    await onRefresh()
                                }
                            }
                            .font(.footnote)
                        }
                    }
                }
            }

            Section("Global Tag Library") {
                if suggestionEntries.isEmpty {
                    Text("No saved tag suggestions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suggestionEntries) { entry in
                        Button {
                            toggleBatchSelection(entry)
                        } label: {
                            HStack {
                                TagUsageRow(
                                    name: entry.name,
                                    colorHex: entry.colorHex,
                                    usageCount: entry.usageCount
                                )
                                Spacer()
                                Image(systemName: selectedBatchTagIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedBatchTagIDs.contains(entry.id) ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Apply Selected Tags") {
                        let entries = suggestionEntries.filter { selectedBatchTagIDs.contains($0.id) }
                        Task {
                            await onAddTags(entries)
                            selectedBatchTagIDs.removeAll()
                            await onRefresh()
                        }
                    }
                    .disabled(selectedBatchTagIDs.isEmpty)
                }
            }

            Section("Create Tag") {
                TextField("New tag", text: $draftTagName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TagColorPreset.allCases) { preset in
                            Button {
                                Task {
                                    await onAddTag(draftTagName, preset.hex)
                                    draftTagName = ""
                                    await onRefresh()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: preset.hex) ?? .accentColor)
                                        .frame(width: 8, height: 8)
                                    Text(preset.name)
                                        .font(.footnote)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(draftTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .navigationTitle("Tag Manager")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var suggestionEntries: [TagLibraryEntry] {
        let currentNames = Set(asset.tags.map(\.normalizedName))
        return tagLibrary.filter { !currentNames.contains($0.normalizedName) }
    }

    private func toggleBatchSelection(_ entry: TagLibraryEntry) {
        if selectedBatchTagIDs.contains(entry.id) {
            selectedBatchTagIDs.remove(entry.id)
        } else {
            selectedBatchTagIDs.insert(entry.id)
        }
    }
}

private struct EditorRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AssetBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PhotoCountBadge: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TileBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(6)
            .background(Color.black.opacity(0.32))
            .clipShape(Circle())
    }
}

private struct TagPill: View {
    let tag: MediaTag

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .accentColor)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

private struct CompactTagPill: View {
    let tag: MediaTag

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .accentColor)
                .frame(width: 6, height: 6)
            Text(tag.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.25))
        .clipShape(Capsule())
    }
}

private struct TagUsageRow: View {
    let name: String
    let colorHex: String
    let usageCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: colorHex) ?? .accentColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text("Used by \(usageCount) asset\(usageCount == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum TagColorPreset: CaseIterable, Identifiable {
    case ember
    case moss
    case ocean
    case plum
    case sand

    var id: String { name }

    var name: String {
        switch self {
        case .ember: "Ember"
        case .moss: "Moss"
        case .ocean: "Ocean"
        case .plum: "Plum"
        case .sand: "Sand"
        }
    }

    var hex: String {
        switch self {
        case .ember: "#C8553D"
        case .moss: "#5F7A61"
        case .ocean: "#3D5A80"
        case .plum: "#6D597A"
        case .sand: "#D4A373"
        }
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
