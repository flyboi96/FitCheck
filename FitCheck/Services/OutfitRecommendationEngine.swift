import Foundation

struct WeatherInput: Equatable {
    var temperatureF: Double
    var isRaining: Bool
    var windMph: Double
    var location: String

    var summary: String {
        var parts = ["\(Int(temperatureF.rounded()))F"]
        if isRaining {
            parts.append("rain")
        }
        if windMph >= 15 {
            parts.append("\(Int(windMph.rounded())) mph wind")
        }
        if !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: ", ")
    }
}

struct RecommendationRequest: Equatable {
    var weather: WeatherInput
    var occasion: String
    var activity: String
    var selectedItem: ClothingItem?
}

struct OutfitRecommendation: Identifiable {
    let id = UUID()
    var title: String
    var items: [ClothingItem]
    var score: Double
    var notes: [String]

    var combinationKey: String {
        Self.combinationKey(for: items)
    }

    static func combinationKey(for items: [ClothingItem]) -> String {
        items
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: "+")
    }
}

struct OutfitRecommendationEngine {
    func recommend(
        closet: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest,
        limit: Int = 3
    ) -> [OutfitRecommendation] {
        let activeItems = closet.filter { $0.status == .active }
        let selected = request.selectedItem

        let tops = constrainedPool(
            categories: [.shirt, .sweater],
            items: activeItems,
            selectedItem: selected
        )
        let bottoms = constrainedPool(
            categories: [.pants, .shorts],
            items: activeItems,
            selectedItem: selected
        )
        let shoes = constrainedPool(
            categories: [.shoes],
            items: activeItems,
            selectedItem: selected
        )

        guard !tops.isEmpty, !bottoms.isEmpty, !shoes.isEmpty else {
            return []
        }

        let jackets = constrainedOptionalPool(
            categories: [.jacket],
            items: activeItems,
            selectedItem: selected,
            weather: request.weather
        )
        let accessories = constrainedOptionalPool(
            categories: [.belt, .watch, .accessory, .bag],
            items: activeItems,
            selectedItem: selected,
            weather: request.weather
        )

        var recommendations: [OutfitRecommendation] = []

        for top in tops.prefix(8) {
            for bottom in bottoms.prefix(8) {
                for shoe in shoes.prefix(6) {
                    for jacket in jackets.prefix(4) {
                        for accessory in accessories.prefix(4) {
                            var outfitItems = [top, bottom, shoe]
                            if let jacket {
                                outfitItems.append(jacket)
                            }
                            if let accessory {
                                outfitItems.append(accessory)
                            }
                            if let selected, !outfitItems.contains(where: { $0.id == selected.id }) {
                                outfitItems.append(selected)
                            }

                            let scored = score(
                                items: outfitItems,
                                feedback: feedback,
                                stylePreference: stylePreference,
                                request: request
                            )
                            recommendations.append(
                                OutfitRecommendation(
                                    title: title(for: outfitItems, request: request),
                                    items: outfitItems,
                                    score: scored.value,
                                    notes: scored.notes
                                )
                            )
                        }
                    }
                }
            }
        }

        return recommendations
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private func constrainedPool(
        categories: Set<ClothingCategory>,
        items: [ClothingItem],
        selectedItem: ClothingItem?
    ) -> [ClothingItem] {
        if let selectedItem, categories.contains(selectedItem.category) {
            return [selectedItem]
        }

        return items
            .filter { categories.contains($0.category) }
            .sorted { itemSortScore($0) > itemSortScore($1) }
    }

    private func constrainedOptionalPool(
        categories: Set<ClothingCategory>,
        items: [ClothingItem],
        selectedItem: ClothingItem?,
        weather: WeatherInput
    ) -> [ClothingItem?] {
        if let selectedItem, categories.contains(selectedItem.category) {
            return [selectedItem]
        }

        let pool = items
            .filter { categories.contains($0.category) }
            .filter { item in
                if item.category == .jacket {
                    return weather.temperatureF <= 68 || weather.isRaining || item.weatherSuitability.fitcheckContainsTag("rain")
                }
                return true
            }
            .sorted { itemSortScore($0) > itemSortScore($1) }

        return [nil] + pool.map { Optional($0) }
    }

    private func score(
        items: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest
    ) -> (value: Double, notes: [String]) {
        var value = 50.0
        var notes: [String] = []

        for item in items {
            let itemValue = itemScore(item, request: request, stylePreference: stylePreference)
            value += itemValue.value
            notes.append(contentsOf: itemValue.notes)

            if let selected = request.selectedItem, item.id == selected.id {
                value += 35
                notes.append("Includes \(selected.name)")
            }
        }

        let colorValue = colorCompatibilityScore(items)
        value += colorValue.value
        notes.append(contentsOf: colorValue.notes)

        let feedbackValue = feedbackPenalty(items: items, feedback: feedback)
        value += feedbackValue.value
        notes.append(contentsOf: feedbackValue.notes)

        value -= formalitySpreadPenalty(items)

        return (value.rounded(), Array(notes.prefix(5)))
    }

    private func itemScore(
        _ item: ClothingItem,
        request: RecommendationRequest,
        stylePreference: StylePreference?
    ) -> (value: Double, notes: [String]) {
        var value = 0.0
        var notes: [String] = []

        value += weatherScore(item, weather: request.weather)
        value += tagScore(item.occasionSuitability, target: request.occasion, matchedNote: "\(item.name) fits \(request.occasion)")
        value += tagScore(item.activitySuitability, target: request.activity, matchedNote: "\(item.name) fits \(request.activity)")

        let targetFormality = targetFormality(for: request.occasion)
        let formalityDistance = abs(item.formalityLevel - targetFormality)
        value -= Double(formalityDistance * 4)
        if formalityDistance == 0 {
            notes.append("Formality matches")
        }

        if let lastWornAt = item.lastWornAt {
            let days = Calendar.current.dateComponents([.day], from: lastWornAt, to: Date()).day ?? 0
            if days <= 3 {
                value -= 30
                notes.append("\(item.name) was worn recently")
            } else if days <= 7 {
                value -= 14
            } else if days >= 21 {
                value += 6
            }
        } else {
            value += 8
        }

        if item.wearCount == 0 {
            value += 4
        }

        if let stylePreference {
            if stylePreference.preferredColors.fitcheckContainsTag(item.color) {
                value += 12
                notes.append("\(item.color) is preferred")
            }
            if stylePreference.dislikedCombinations.localizedCaseInsensitiveContains(item.name) {
                value -= 18
                notes.append("Style dislike matched")
            }
            if !stylePreference.rules.isEmpty && stylePreference.rules.localizedCaseInsensitiveContains(item.category.displayName) {
                value += 4
            }
        }

        return (value, notes)
    }

    private func weatherScore(_ item: ClothingItem, weather: WeatherInput) -> Double {
        var value = 0.0

        if weather.temperatureF <= 50 {
            value += item.weatherSuitability.fitcheckContainsTag("cold") ? 16 : -8
            if item.category == .shorts {
                value -= 24
            }
        } else if weather.temperatureF >= 82 {
            value += item.weatherSuitability.fitcheckContainsTag("hot") ? 16 : 0
            if item.category == .jacket || item.category == .sweater {
                value -= 22
            }
            if item.category == .shorts {
                value += 10
            }
        } else if item.weatherSuitability.fitcheckContainsTag("mild") {
            value += 8
        }

        if weather.isRaining {
            value += item.weatherSuitability.fitcheckContainsTag("rain") ? 18 : -8
            if item.category == .shoes && item.weatherSuitability.fitcheckContainsTag("suede") {
                value -= 28
            }
        }

        if weather.windMph >= 18 {
            value += item.weatherSuitability.fitcheckContainsTag("wind") ? 8 : 0
        }

        return value
    }

    private func tagScore(_ tags: String, target: String, matchedNote: String) -> Double {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if tags.fitcheckContainsTag(trimmed) {
            return 12
        }
        return tags.fitcheckTags.isEmpty ? 0 : -6
    }

    private func colorCompatibilityScore(_ items: [ClothingItem]) -> (value: Double, notes: [String]) {
        let colors = items.map { $0.color.lowercased() }.filter { !$0.isEmpty }
        guard colors.count > 1 else { return (0, []) }

        let neutralColors: Set<String> = ["black", "white", "gray", "grey", "navy", "denim", "cream", "tan", "brown"]
        let neutralCount = colors.filter { neutralColors.contains($0) }.count
        var value = Double(neutralCount * 4)
        var notes: [String] = []

        if Set(colors).count <= 3 {
            value += 8
            notes.append("Color palette is tight")
        }

        if colors.contains("red") && colors.contains("green") {
            value -= 14
            notes.append("Red and green may clash")
        }
        if colors.contains("orange") && colors.contains("purple") {
            value -= 12
            notes.append("Orange and purple may clash")
        }

        return (value, notes)
    }

    private func feedbackPenalty(items: [ClothingItem], feedback: [Feedback]) -> (value: Double, notes: [String]) {
        let combinationKey = OutfitRecommendation.combinationKey(for: items)
        var value = 0.0
        var notes: [String] = []

        for entry in feedback where entry.type.isNegative {
            if !entry.combinationKey.isEmpty && entry.combinationKey == combinationKey {
                value -= 45
                notes.append("Past negative combo")
            }
            if let feedbackItem = entry.item, items.contains(where: { $0.id == feedbackItem.id }) {
                value -= 8
            }
        }

        return (value, notes)
    }

    private func formalitySpreadPenalty(_ items: [ClothingItem]) -> Double {
        let levels = items.map(\.formalityLevel)
        guard let minLevel = levels.min(), let maxLevel = levels.max() else { return 0 }
        return Double(max(0, maxLevel - minLevel - 2) * 6)
    }

    private func targetFormality(for occasion: String) -> Int {
        let text = occasion.lowercased()
        if text.contains("wedding") || text.contains("formal") {
            return 5
        }
        if text.contains("date") || text.contains("dinner") || text.contains("work") {
            return 4
        }
        if text.contains("travel") || text.contains("city") {
            return 3
        }
        if text.contains("gym") || text.contains("walk") {
            return 2
        }
        return 3
    }

    private func itemSortScore(_ item: ClothingItem) -> Double {
        var score = 100.0 - Double(item.wearCount)
        if let lastWornAt = item.lastWornAt {
            let days = Calendar.current.dateComponents([.day], from: lastWornAt, to: Date()).day ?? 0
            score += Double(min(days, 30))
        } else {
            score += 30
        }
        return score
    }

    private func title(for items: [ClothingItem], request: RecommendationRequest) -> String {
        let occasion = request.occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !occasion.isEmpty {
            return "\(occasion.capitalized) Fit"
        }
        return "Daily Fit"
    }
}
