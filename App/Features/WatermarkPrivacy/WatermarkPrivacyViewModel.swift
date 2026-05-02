import Foundation
import Observation

@Observable
final class WatermarkPrivacyViewModel {
    private let watermarkInspector: WatermarkInspecting

    private(set) var results: [WatermarkScanResult] = []
    private(set) var isLoading = false

    init(watermarkInspector: WatermarkInspecting) {
        self.watermarkInspector = watermarkInspector
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            results = try await watermarkInspector.recentResults()
        } catch {
            results = []
        }
    }
}
