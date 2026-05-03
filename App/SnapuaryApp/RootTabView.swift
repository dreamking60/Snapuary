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

            CleanupHomeView(viewModel: viewModel.makeLibraryViewModel())
                .tabItem {
                    Label("Cleanup", systemImage: "trash")
                }
                .tag(RootTab.cleanup)
        }
    }
}
