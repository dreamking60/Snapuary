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
            TagHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.tags", fallback: "Tags"), systemImage: "folder")
                }
                .tag(RootTab.tags)

            OrbitHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.orbit", fallback: "Orbit"), systemImage: "circle.hexagongrid.fill")
                }
                .tag(RootTab.orbit)

            CleanupHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.cleanup", fallback: "Cleanup"), systemImage: "trash")
                }
                .tag(RootTab.cleanup)

            LibraryHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label(L10n.text("tab.library", fallback: "Library"), systemImage: "photo.stack")
                }
                .tag(RootTab.library)
        }
        .task {
            viewModel.handlePendingRouteIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            viewModel.handlePendingRouteIfNeeded()
            Task {
                await viewModel.makeLibraryViewModel().handleAppDidBecomeActive()
            }
        }
    }
}
