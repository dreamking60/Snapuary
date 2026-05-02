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
                    Label("Library", systemImage: "photo.on.rectangle.angled")
                }
                .tag(RootTab.library)

            WatermarkPrivacyView(viewModel: viewModel.makeWatermarkViewModel())
                .tabItem {
                    Label("Privacy", systemImage: "shield.lefthalf.filled")
                }
                .tag(RootTab.privacy)
        }
    }
}

