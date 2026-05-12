import Foundation

protocol AutoTagSuggesting {
    func suggestions(for asset: MediaAsset, within library: [MediaAsset]) async -> [AutoTagSuggestion]
}

struct AutoTagSuggestion: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String
    let reason: String
}

struct TemplateAutoTagSuggestionService: AutoTagSuggesting {
    func suggestions(for asset: MediaAsset, within library: [MediaAsset]) async -> [AutoTagSuggestion] {
        var suggestions: [AutoTagSuggestion] = []
        let lowercasedTitle = asset.title.lowercased()
        let existingNames = Set(asset.tags.map(\.normalizedName))

        func appendSuggestion(name: String, colorHex: String, reason: String) {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty,
                  !existingNames.contains(normalized),
                  !suggestions.contains(where: { $0.id == normalized }) else {
                return
            }

            suggestions.append(
                AutoTagSuggestion(
                    id: normalized,
                    name: name,
                    colorHex: colorHex,
                    reason: reason
                )
            )
        }

        if asset.isScreenshot {
            appendSuggestion(name: "Screenshot", colorHex: "#4F7CAC", reason: "Detected from screenshot media type.")
        }

        if lowercasedTitle.contains("receipt") || lowercasedTitle.contains("invoice") || lowercasedTitle.contains("bill") {
            appendSuggestion(name: "Receipt", colorHex: "#E07A5F", reason: "Title suggests a bill or receipt.")
            appendSuggestion(name: "Finance", colorHex: "#81B29A", reason: "Payment-related title keyword.")
        }

        if lowercasedTitle.contains("design") || lowercasedTitle.contains("figma") || lowercasedTitle.contains("ui") {
            appendSuggestion(name: "Design", colorHex: "#F2CC8F", reason: "Design-related title keyword.")
            appendSuggestion(name: "Reference", colorHex: "#6D597A", reason: "Likely visual reference material.")
        }

        if lowercasedTitle.contains("family") || lowercasedTitle.contains("mom") || lowercasedTitle.contains("dad") || lowercasedTitle.contains("baby") {
            appendSuggestion(name: "Family", colorHex: "#C8553D", reason: "Family-related title keyword.")
        }

        let hour = Calendar.current.component(.hour, from: asset.createdAt)
        switch hour {
        case 5..<12:
            appendSuggestion(name: "Morning", colorHex: "#F4A261", reason: "Capture time is in the morning.")
        case 12..<17:
            appendSuggestion(name: "Afternoon", colorHex: "#E9C46A", reason: "Capture time is in the afternoon.")
        case 17..<21:
            appendSuggestion(name: "Evening", colorHex: "#B56576", reason: "Capture time is in the evening.")
        default:
            appendSuggestion(name: "Night", colorHex: "#355070", reason: "Capture time is at night.")
        }

        let weekday = Calendar.current.component(.weekday, from: asset.createdAt)
        if weekday == 1 || weekday == 7 {
            appendSuggestion(name: "Weekend", colorHex: "#84A59D", reason: "Captured on a weekend.")
        } else {
            appendSuggestion(name: "Weekday", colorHex: "#52796F", reason: "Captured on a workday.")
        }

        let frequentLibraryTags = Dictionary(grouping: library.flatMap(\.tags), by: \.normalizedName)
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
        for entry in frequentLibraryTags {
            if let tag = entry.value.first, !existingNames.contains(tag.normalizedName) {
                appendSuggestion(name: tag.name, colorHex: tag.colorHex, reason: "Frequently used in your library.")
            }
        }

        return suggestions
    }
}
