import SwiftUI

@main
struct SnapuaryApp: App {
    private let container = AppContainer.live
    @State private var settings = AppContainer.live.settingsStore

    var body: some Scene {
        @Bindable var settings = settings

        WindowGroup {
            RootTabView(viewModel: RootTabViewModel(container: container))
                .environment(settings)
                .environment(\.locale, settings.locale)
        }
    }
}
