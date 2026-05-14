import SwiftUI

struct AppProfileSheet: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private let photoAuthorizationStatus: PhotoLibraryAuthorizationStatus

    init(photoAuthorizationStatus: PhotoLibraryAuthorizationStatus) {
        self.photoAuthorizationStatus = photoAuthorizationStatus
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text("settings.profile.default_user", fallback: "Default User"))
                                    .font(.headline)
                                Text(L10n.text("settings.profile.subtitle", fallback: "Private on-device photo review"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        Text(L10n.text("settings.profile.description", fallback: "Snapuary currently uses a single local profile. Language and review preferences stay on this device."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.text("settings.section.language", fallback: "Language")) {
                    Picker(
                        L10n.text("settings.language.label", fallback: "App Language"),
                        selection: $settings.preferredLanguage
                    ) {
                        ForEach(AppLanguageOption.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }

                    Text(L10n.text("settings.language.footer", fallback: "By default Snapuary follows the system language."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.text("settings.section.preferences", fallback: "Preferences")) {
                    Picker(
                        L10n.text("settings.launch_tab.label", fallback: "Launch Tab"),
                        selection: $settings.preferredLaunchTab
                    ) {
                        Text(L10n.text("tab.tags", fallback: "Tags")).tag(RootTab.tags)
                        Text(L10n.text("tab.orbit", fallback: "Orbit")).tag(RootTab.orbit)
                        Text(L10n.text("tab.cleanup", fallback: "Cleanup")).tag(RootTab.cleanup)
                        Text(L10n.text("tab.library", fallback: "Library")).tag(RootTab.library)
                    }

                    Picker(
                        L10n.text("settings.cleanup_mode.label", fallback: "Default Cleanup Mode"),
                        selection: $settings.preferredCleanupReviewMode
                    ) {
                        ForEach(CleanupReviewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section(L10n.text("settings.section.status", fallback: "Status")) {
                    LabeledContent(
                        L10n.text("settings.status.photo_access", fallback: "Photo Access"),
                        value: photoAuthorizationStatus.displayName
                    )

                    LabeledContent(
                        L10n.text("settings.status.version", fallback: "Version"),
                        value: appVersionLabel
                    )
                }
            }
            .navigationTitle(L10n.text("settings.title", fallback: "Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.done", fallback: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}
