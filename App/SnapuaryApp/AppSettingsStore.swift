import Foundation
import Observation

enum AppLanguageOption: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    static let userDefaultsKey = "appPreferredLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        case .traditionalChinese:
            Locale(identifier: "zh-Hant")
        case .japanese:
            Locale(identifier: "ja")
        case .korean:
            Locale(identifier: "ko")
        }
    }

    var displayName: String {
        switch self {
        case .system:
            L10n.text("settings.language.system", fallback: "System Default")
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁體中文"
        case .japanese:
            "日本語"
        case .korean:
            "한국어"
        }
    }
}

@Observable
final class AppSettingsStore {
    private enum Keys {
        static let preferredLaunchTab = "preferredLaunchTab"
        static let preferredCleanupReviewMode = "preferredCleanupReviewMode"
    }

    var preferredLanguage: AppLanguageOption {
        didSet {
            userDefaults.set(preferredLanguage.rawValue, forKey: AppLanguageOption.userDefaultsKey)
        }
    }

    var preferredLaunchTab: RootTab {
        didSet {
            userDefaults.set(preferredLaunchTab.storageValue, forKey: Keys.preferredLaunchTab)
        }
    }

    var preferredCleanupReviewMode: CleanupReviewMode {
        didSet {
            userDefaults.set(preferredCleanupReviewMode.rawValue, forKey: Keys.preferredCleanupReviewMode)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.preferredLanguage = AppLanguageOption(rawValue: userDefaults.string(forKey: AppLanguageOption.userDefaultsKey) ?? "") ?? .system
        self.preferredLaunchTab = RootTab(storageValue: userDefaults.string(forKey: Keys.preferredLaunchTab)) ?? .cleanup
        self.preferredCleanupReviewMode = CleanupReviewMode(rawValue: userDefaults.string(forKey: Keys.preferredCleanupReviewMode) ?? "") ?? .screenshots
    }

    var locale: Locale {
        preferredLanguage.locale
    }
}

enum L10n {
    static func text(_ key: String, fallback: String) -> String {
        bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func text(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: text(key, fallback: fallback), locale: locale, arguments: arguments)
    }

    static var locale: Locale {
        selectedLanguage.locale
    }

    private static var selectedLanguage: AppLanguageOption {
        AppLanguageOption(rawValue: UserDefaults.standard.string(forKey: AppLanguageOption.userDefaultsKey) ?? "") ?? .system
    }

    private static var bundle: Bundle {
        guard selectedLanguage != .system else {
            return .main
        }

        guard let path = Bundle.main.path(forResource: selectedLanguage.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return .main
        }

        return localizedBundle
    }
}

extension RootTab {
    var storageValue: String {
        switch self {
        case .library:
            "library"
        case .tags:
            "tags"
        case .cleanup:
            "cleanup"
        }
    }

    init?(storageValue: String?) {
        switch storageValue {
        case "library":
            self = .library
        case "tags":
            self = .tags
        case "cleanup":
            self = .cleanup
        default:
            return nil
        }
    }
}
