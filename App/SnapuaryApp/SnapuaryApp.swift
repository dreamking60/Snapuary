import SwiftUI

@main
struct SnapuaryApp: App {
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            RootTabView(viewModel: RootTabViewModel(container: container))
        }
    }
}

