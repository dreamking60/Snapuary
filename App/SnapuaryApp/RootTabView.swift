import SwiftUI

struct RootTabView: View {
    @State private var viewModel: RootTabViewModel

    init(viewModel: RootTabViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
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
    }
}
