import Foundation

struct MediaAsset: Codable, Identifiable, Hashable {
    let id: UUID
    var libraryIdentifier: String?
    var title: String
    var createdAt: Date
    var addedAt: Date
    var tags: [MediaTag]
    var orbitIDs: [String]
    var kind: MediaAssetKind
    var screenshotRule: ScreenshotRetentionRule?
    var isProtectedFromCleanup: Bool

    init(
        id: UUID,
        libraryIdentifier: String?,
        title: String,
        createdAt: Date,
        addedAt: Date,
        tags: [MediaTag],
        orbitIDs: [String] = [],
        kind: MediaAssetKind,
        screenshotRule: ScreenshotRetentionRule?,
        isProtectedFromCleanup: Bool
    ) {
        self.id = id
        self.libraryIdentifier = libraryIdentifier
        self.title = title
        self.createdAt = createdAt
        self.addedAt = addedAt
        self.tags = tags
        self.orbitIDs = orbitIDs
        self.kind = kind
        self.screenshotRule = screenshotRule
        self.isProtectedFromCleanup = isProtectedFromCleanup
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case libraryIdentifier
        case title
        case createdAt
        case addedAt
        case tags
        case orbitIDs
        case kind
        case screenshotRule
        case isProtectedFromCleanup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        libraryIdentifier = try container.decodeIfPresent(String.self, forKey: .libraryIdentifier)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        tags = try container.decodeIfPresent([MediaTag].self, forKey: .tags) ?? []
        orbitIDs = try container.decodeIfPresent([String].self, forKey: .orbitIDs) ?? []
        kind = try container.decode(MediaAssetKind.self, forKey: .kind)
        screenshotRule = try container.decodeIfPresent(ScreenshotRetentionRule.self, forKey: .screenshotRule)
        isProtectedFromCleanup = try container.decodeIfPresent(Bool.self, forKey: .isProtectedFromCleanup) ?? false
    }

    var isScreenshot: Bool {
        kind == .systemScreenshot || kind == .importedScreenshotLike
    }

    var expirationDate: Date? {
        guard isScreenshot, !isProtectedFromCleanup else {
            return nil
        }

        return screenshotRule?.expirationDate(createdAt: createdAt, addedAt: addedAt)
    }

    var gridIdentifier: String {
        libraryIdentifier ?? id.uuidString
    }
}

enum MediaAssetKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case systemScreenshot
    case importedScreenshotLike
    case photo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemScreenshot:
            L10n.text("asset.kind.system_screenshot", fallback: "System Screenshot")
        case .importedScreenshotLike:
            L10n.text("asset.kind.imported_screenshot", fallback: "Imported Screenshot")
        case .photo:
            L10n.text("asset.kind.photo", fallback: "Photo")
        }
    }
}

struct MediaTag: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct ScreenshotRetentionRule: Codable, Hashable {
    var mode: Mode
    var anchor: Anchor

    enum Mode: Codable, Hashable {
        case manualOnly
        case preset(RetentionPreset)
        case customMinutes(Int)

        private enum CodingKeys: String, CodingKey {
            case kind
            case preset
            case minutes
        }

        private enum Kind: String, Codable {
            case manualOnly
            case preset
            case customMinutes
            case customDays
            case expiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKey.self)

            switch kind {
            case .manualOnly:
                self = .manualOnly
            case .preset:
                self = .preset(try container.decode(RetentionPreset.self, forKey: .preset))
            case .customMinutes:
                self = .customMinutes(try container.decode(Int.self, forKey: .minutes))
            case .customDays:
                let legacyDays = try legacyContainer.decode(Int.self, forKey: LegacyCodingKey("days"))
                self = .customMinutes(max(legacyDays * 24 * 60, 1))
            case .expiresAt:
                let legacyDate = try legacyContainer.decode(Date.self, forKey: LegacyCodingKey("date"))
                let minutes = max(Int(legacyDate.timeIntervalSinceNow / 60), 1)
                self = .customMinutes(minutes)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .manualOnly:
                try container.encode(Kind.manualOnly, forKey: .kind)
            case .preset(let preset):
                try container.encode(Kind.preset, forKey: .kind)
                try container.encode(preset, forKey: .preset)
            case .customMinutes(let minutes):
                try container.encode(Kind.customMinutes, forKey: .kind)
                try container.encode(minutes, forKey: .minutes)
            }
        }
    }

    enum Anchor: String, Codable, Hashable {
        case creationDate
        case addedDate
    }

    enum RetentionPreset: String, Codable, Hashable, CaseIterable, Identifiable {
        case oneDay
        case oneWeek
        case oneMonth

        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .oneDay:
                1
            case .oneWeek:
                7
            case .oneMonth:
                30
            }
        }

        var displayName: String {
            switch self {
            case .oneDay:
                L10n.text("rule.preset.one_day", fallback: "1 Day")
            case .oneWeek:
                L10n.text("rule.preset.one_week", fallback: "1 Week")
            case .oneMonth:
                L10n.text("rule.preset.one_month", fallback: "1 Month")
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "oneDay":
                self = .oneDay
            case "oneWeek":
                self = .oneWeek
            case "oneMonth", "thirtyDays", "threeMonths", "oneYear":
                self = .oneMonth
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported retention preset: \(rawValue)"
                )
            }
        }
    }

    func expirationDate(createdAt: Date, addedAt: Date) -> Date? {
        let baseDate: Date
        switch anchor {
        case .creationDate:
            baseDate = createdAt
        case .addedDate:
            baseDate = addedAt
        }

        switch mode {
        case .manualOnly:
            return nil
        case .preset(let preset):
            return Calendar.current.date(byAdding: .day, value: preset.dayCount, to: baseDate)
        case .customMinutes(let minutes):
            return Calendar.current.date(byAdding: .minute, value: minutes, to: baseDate)
        }
    }

    var displayName: String {
        switch mode {
        case .manualOnly:
            return L10n.text("rule.mode.manual_only", fallback: "Manual Only")
        case .preset(let preset):
            return preset.displayName
        case .customMinutes(let minutes):
            if minutes == 1 {
                return L10n.text("rule.mode.custom_minute.singular", fallback: "1 Minute")
            }

            return L10n.text(
                "rule.mode.custom_minute.plural",
                fallback: "%lld Minutes",
                minutes
            )
        }
    }
}

private struct LegacyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
