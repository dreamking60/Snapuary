import SwiftUI

struct WatermarkPrivacyView: View {
    @State private var viewModel: WatermarkPrivacyViewModel

    init(viewModel: WatermarkPrivacyViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SnapuaryCard(title: L10n.text("privacy.recent_signals", fallback: "Recent Risk Signals")) {
                        ForEach(viewModel.results) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.riskLevel.rawValue.capitalized)
                                    .font(.headline)
                                Text(result.detectedSignals.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }

                    SnapuaryCard(title: L10n.text("privacy.detection_strategy", fallback: "Detection Strategy")) {
                        Text(L10n.text("privacy.strategy_body", fallback: "Start with OCR-based watermark signal detection, then add custom rules for internal identifiers."))
                            .font(.body)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("privacy.title", fallback: "Privacy"))
            .task {
                await viewModel.load()
            }
        }
    }
}
