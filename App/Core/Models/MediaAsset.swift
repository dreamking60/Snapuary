import Foundation

struct MediaAsset: Identifiable, Hashable {
    let id: UUID
    var libraryIdentifier: String?
    var title: String
    var createdAt: Date
    var addedAt: Date
    var tags: [MediaTag]
    var kind: MediaAssetKind
    var screenshotRule: ScreenshotRetentionRule?
    var isProtectedFromCleanup: Bool

    var isScreenshot: Bool {
        kind == .systemScreenshot || kind == .importedScreenshotLike
    }

    var expirationDate: Date? {
        guard isScreenshot, !isProtectedFromCleanup else {
            return nil
        }

        return screenshotRule?.expirationDate(createdAt: createdAt, addedAt: addedAt)
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
            "System Screenshot"
        case .importedScreenshotLike:
            "Imported Screenshot"
        case .photo:
            "Photo"
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
        case customDays(Int)
        case expiresAt(Date)

        private enum CodingKeys: String, CodingKey {
            case kind
            case preset
            case days
            case date
        }

        private enum Kind: String, Codable {
            case manualOnly
            case preset
            case customDays
            case expiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)

            switch kind {
            case .manualOnly:
                self = .manualOnly
            case .preset:
                self = .preset(try container.decode(RetentionPreset.self, forKey: .preset))
            case .customDays:
                self = .customDays(try container.decode(Int.self, forKey: .days))
            case .expiresAt:
                self = .expiresAt(try container.decode(Date.self, forKey: .date))
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
            case .customDays(let days):
                try container.encode(Kind.customDays, forKey: .kind)
                try container.encode(days, forKey: .days)
            case .expiresAt(let date):
                try container.encode(Kind.expiresAt, forKey: .kind)
                try container.encode(date, forKey: .date)
            }
        }
    }

    enum Anchor: String, Codable, Hashable {
        case creationDate
        case addedDate
    }

    enum RetentionPreset: String, Codable, Hashable, CaseIterable, Identifiable {
        case oneWeek
        case thirtyDays
        case threeMonths
        case oneYear

        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .oneWeek:
                7
            case .thirtyDays:
                30
            case .threeMonths:
                90
            case .oneYear:
                365
            }
        }

        var displayName: String {
            switch self {
            case .oneWeek:
                "1 Week"
            case .thirtyDays:
                "30 Days"
            case .threeMonths:
                "3 Months"
            case .oneYear:
                "1 Year"
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
        case .customDays(let days):
            return Calendar.current.date(byAdding: .day, value: days, to: baseDate)
        case .expiresAt(let date):
            return date
        }
    }

    var displayName: String {
        switch mode {
        case .manualOnly:
            "Manual Only"
        case .preset(let preset):
            preset.displayName
        case .customDays(let days):
            "\(days) Days"
        case .expiresAt:
            "Custom Date"
        }
    }
}
