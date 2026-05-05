import SwiftUI

struct RootTabView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: RootTabViewModel

    init(viewModel: RootTabViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let _ = settings.preferredLanguage

        TabView(selection: $viewModel.selectedTab) {
            LibraryHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.library", fallback: "Library"), systemImage: "photo.stack")
                }
                .tag(RootTab.library)

            TagHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.tags", fallback: "Tags"), systemImage: "folder")
                }
                .tag(RootTab.tags)

            CleanupHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.cleanup", fallback: "Cleanup"), systemImage: "trash")
                }
                .tag(RootTab.cleanup)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await viewModel.makeLibraryViewModel().handleAppDidBecomeActive()
            }
        }
    }
}
