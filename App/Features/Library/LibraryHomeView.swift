import SwiftUI

struct LibraryHomeView: View {
    @State private var viewModel: LibraryHomeViewModel

    init(viewModel: LibraryHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SnapuaryCard(title: "Cleanup Overview") {
                        Text("Expiring soon: \(viewModel.cleanupSummary.expiringSoonCount)")
                        Text("Protected items: \(viewModel.cleanupSummary.protectedCount)")
                    }

                    SnapuaryCard(title: "Tagged Media") {
                        ForEach(viewModel.assets) { asset in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(asset.title)
                                    .font(.headline)
                                Text(asset.source.rawValue.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(asset.tags.map(\.name).joined(separator: ", "))
                                    .font(.footnote)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Library")
            .task {
                await viewModel.load()
            }
        }
    }
}

