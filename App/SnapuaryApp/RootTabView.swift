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
                    Label("Library", systemImage: "photo.stack")
                }
                .tag(RootTab.library)

            TagHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label("Tags", systemImage: "folder")
                }
                .tag(RootTab.tags)

            CleanupHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label("Cleanup", systemImage: "trash")
                }
                .tag(RootTab.cleanup)
        }
    }
}
