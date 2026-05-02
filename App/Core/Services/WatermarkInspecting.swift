import Foundation

protocol WatermarkInspecting {
    func recentResults() async throws -> [WatermarkScanResult]
}

struct MockWatermarkInspector: WatermarkInspecting {
    func recentResults() async throws -> [WatermarkScanResult] {
        [
            WatermarkScanResult(
                id: UUID(),
                assetID: UUID(),
                riskLevel: .high,
                detectedSignals: ["Email watermark", "Employee ID"],
                scannedAt: .now.addingTimeInterval(-3_600)
            ),
            WatermarkScanResult(
                id: UUID(),
                assetID: UUID(),
                riskLevel: .medium,
                detectedSignals: ["Account alias"],
                scannedAt: .now.addingTimeInterval(-7_200)
            )
        ]
    }
}

