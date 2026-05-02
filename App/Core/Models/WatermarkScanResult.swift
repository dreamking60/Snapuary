import Foundation

struct WatermarkScanResult: Identifiable, Hashable {
    let id: UUID
    let assetID: UUID
    let riskLevel: PrivacyRiskLevel
    let detectedSignals: [String]
    let scannedAt: Date
}

enum PrivacyRiskLevel: String, Hashable {
    case low
    case medium
    case high
}

