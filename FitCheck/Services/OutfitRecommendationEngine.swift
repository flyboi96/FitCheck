import Foundation

enum OccasionOption: String, CaseIterable, Identifiable {
    case casual
    case dateNight = "date night"
    case work
    case travelDay = "travel day"
    case dinner
    case gym
    case walkingAroundCity = "walking around city"
    case wedding

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .casual: "Casual"
        case .dateNight: "Date Night"
        case .work: "Work"
        case .travelDay: "Travel Day"
        case .dinner: "Dinner"
        case .gym: "Gym"
        case .walkingAroundCity: "Walking Around City"
        case .wedding: "Wedding"
        }
    }
}

enum ActivityOption: String, CaseIterable, Identifiable {
    case walkingAroundCity = "walking around city"
    case office
    case dinner
    case gym
    case travel
    case errands
    case outdoors
    case formalEvent = "formal event"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walkingAroundCity: "Walking Around City"
        case .office: "Office"
        case .dinner: "Dinner"
        case .gym: "Gym"
        case .travel: "Travel"
        case .errands: "Errands"
        case .outdoors: "Outdoors"
        case .formalEvent: "Formal Event"
        }
    }
}

struct ClothingInference {
    struct Metadata {
        var color: String
        var pattern: String
        var formalityLevel: Int
        var weatherSuitability: String
        var occasionSuitability: String
        var activitySuitability: String
    }

    static func metadata(name: String, category: ClothingCategory) -> Metadata {
        Metadata(
            color: color(from: name),
            pattern: pattern(from: name),
            formalityLevel: formalityLevel(name: name, category: category),
            weatherSuitability: weatherTags(name: name, category: category).joined(separator: ", "),
            occasionSuitability: occasionTags(name: name, category: category).joined(separator: ", "),
            activitySuitability: activityTags(name: name, category: category).joined(separator: ", ")
        )
    }

    static func color(for item: ClothingItem) -> String {
        let inferred = color(from: item.name)
        return inferred.isEmpty ? item.color.lowercased() : inferred
    }

    static func pattern(for item: ClothingItem) -> String {
        let inferred = pattern(from: item.name)
        return inferred.isEmpty ? item.pattern.lowercased() : inferred
    }

    static func weatherTags(for item: ClothingItem) -> [String] {
        mergedTags(item.weatherSuitability, inferred: weatherTags(name: item.name, category: item.category))
    }

    static func occasionTags(for item: ClothingItem) -> [String] {
        mergedTags(item.occasionSuitability, inferred: occasionTags(name: item.name, category: item.category))
    }

    static func activityTags(for item: ClothingItem) -> [String] {
        mergedTags(item.activitySuitability, inferred: activityTags(name: item.name, category: item.category))
    }

    static func formalityLevel(for item: ClothingItem) -> Int {
        formalityLevel(name: item.name, category: item.category)
    }

    private static func color(from name: String) -> String {
        let text = normalized(name)
        let colors = [
            "black", "white", "gray", "grey", "navy", "blue", "denim", "green", "olive", "red",
            "burgundy", "pink", "purple", "orange", "yellow", "cream", "beige", "tan", "brown",
            "khaki", "charcoal", "silver", "gold"
        ]
        return colors.first { text.contains($0) } ?? ""
    }

    private static func pattern(from name: String) -> String {
        let text = normalized(name)
        let patterns = ["striped", "stripe", "plaid", "checked", "check", "floral", "solid", "herringbone", "graphic"]
        return patterns.first { text.contains($0) } ?? ""
    }

    private static func weatherTags(name: String, category: ClothingCategory) -> [String] {
        let text = normalized(name)
        var tags = Set(["mild"])

        if text.containsAny(["linen", "seersucker", "short sleeve", "t-shirt", "tee", "shorts", "lightweight"]) {
            tags.insert("hot")
        }
        if text.containsAny(["wool", "merino", "cashmere", "fleece", "flannel", "puffer", "coat", "sweater", "hoodie"]) {
            tags.insert("cold")
        }
        if text.containsAny(["rain", "waterproof", "shell", "gore-tex", "boots"]) {
            tags.insert("rain")
            tags.insert("wind")
        }
        if text.contains("suede") {
            tags.insert("suede")
        }
        if category == .jacket {
            tags.insert("cold")
            tags.insert("wind")
        }
        if category == .shorts {
            tags.insert("hot")
        }

        return tags.sorted()
    }

    private static func occasionTags(name: String, category: ClothingCategory) -> [String] {
        let text = normalized(name)
        var tags = Set(["casual"])

        if text.containsAny(["button-down", "button down", "oxford", "chino", "loafer", "blazer", "dress", "merino"]) {
            tags.formUnion(["dinner", "date night", "work"])
        }
        if text.containsAny(["suit", "tie", "formal"]) {
            tags.formUnion(["wedding", "formal event"])
        }
        if text.containsAny(["tee", "t-shirt", "hoodie", "sneaker", "shorts", "jeans"]) {
            tags.formUnion(["travel day", "walking around city"])
        }
        if text.containsAny(["gym", "running", "trainer", "athletic", "performance"]) {
            tags.insert("gym")
        }
        if category == .bag || category == .shoes {
            tags.insert("travel day")
        }

        return tags.sorted()
    }

    private static func activityTags(name: String, category: ClothingCategory) -> [String] {
        let text = normalized(name)
        var tags = Set(["errands", "walking around city"])

        if text.containsAny(["button-down", "button down", "oxford", "blazer", "chino", "dress"]) {
            tags.formUnion(["office", "dinner"])
        }
        if text.containsAny(["gym", "running", "trainer", "athletic", "performance"]) {
            tags.insert("gym")
        }
        if text.containsAny(["boots", "shell", "waterproof", "jacket", "bag"]) {
            tags.formUnion(["travel", "outdoors"])
        }
        if category == .bag {
            tags.insert("travel")
        }

        return tags.sorted()
    }

    private static func formalityLevel(name: String, category: ClothingCategory) -> Int {
        let text = normalized(name)
        if text.containsAny(["suit", "tie", "tux", "formal"]) {
            return 5
        }
        if text.containsAny(["blazer", "dress", "loafer", "oxford", "button-down", "button down"]) {
            return 4
        }
        if text.containsAny(["merino", "chino", "polo", "boot"]) {
            return 3
        }
        if text.containsAny(["gym", "running", "athletic", "hoodie", "shorts", "sneaker"]) {
            return 2
        }
        switch category {
        case .watch, .belt:
            return 3
        case .jacket, .sweater:
            return 3
        default:
            return 2
        }
    }

    private static func mergedTags(_ stored: String, inferred: [String]) -> [String] {
        Set(stored.fitcheckTags + inferred).sorted()
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

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
                    return weather.temperatureF <= 68 || weather.isRaining || ClothingInference.weatherTags(for: item).contains("rain")
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
        value += tagScore(ClothingInference.occasionTags(for: item), target: request.occasion, matchedNote: "\(item.name) fits \(request.occasion)")
        value += tagScore(ClothingInference.activityTags(for: item), target: request.activity, matchedNote: "\(item.name) fits \(request.activity)")

        let targetFormality = targetFormality(for: request.occasion)
        let formalityDistance = abs(ClothingInference.formalityLevel(for: item) - targetFormality)
        value -= Double(formalityDistance * 4)
        if formalityDistance == 0 {
            notes.append("Inferred dressiness matches")
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
            let inferredColor = ClothingInference.color(for: item)
            if stylePreference.preferredColors.fitcheckContainsTag(inferredColor) {
                value += 12
                notes.append("\(inferredColor) is preferred")
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
        let weatherTags = ClothingInference.weatherTags(for: item)

        if weather.temperatureF <= 50 {
            value += weatherTags.contains("cold") ? 16 : -8
            if item.category == .shorts {
                value -= 24
            }
        } else if weather.temperatureF >= 82 {
            value += weatherTags.contains("hot") ? 16 : 0
            if item.category == .jacket || item.category == .sweater {
                value -= 22
            }
            if item.category == .shorts {
                value += 10
            }
        } else if weatherTags.contains("mild") {
            value += 8
        }

        if weather.isRaining {
            value += weatherTags.contains("rain") ? 18 : -8
            if item.category == .shoes && weatherTags.contains("suede") {
                value -= 28
            }
        }

        if weather.windMph >= 18 {
            value += weatherTags.contains("wind") ? 8 : 0
        }

        return value
    }

    private func tagScore(_ tags: [String], target: String, matchedNote: String) -> Double {
        let storedTags = tags.joined(separator: ", ")
        return tagScore(storedTags, target: target, matchedNote: matchedNote)
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
        let profiles = items.compactMap { WardrobeColorProfile(colorName: ClothingInference.color(for: $0)) }
        guard profiles.count > 1 else { return (0, []) }

        let nonNeutrals = profiles.filter { !$0.isNeutral }
        let neutralCount = profiles.count - nonNeutrals.count
        var value = Double(neutralCount * 3)
        var notes: [String] = []

        if nonNeutrals.isEmpty {
            value += 14
            notes.append("Neutral palette")
        } else if nonNeutrals.count == 1 {
            value += neutralCount > 0 ? 16 : 8
            notes.append("\(nonNeutrals[0].displayName.capitalized) works as the accent")
        } else if nonNeutrals.count == 2 {
            let relationship = ColorHarmony.relationship(between: nonNeutrals[0], and: nonNeutrals[1])
            value += relationship.score(neutralCount: neutralCount)
            if let note = relationship.note {
                notes.append(note)
            }
        } else {
            let saturatedAccentCount = nonNeutrals.filter { $0.saturation == .high }.count
            if saturatedAccentCount >= 3 {
                value -= 18
                notes.append("Too many strong accent colors")
            } else {
                value -= 8
                notes.append("Palette may be busy")
            }
        }

        let uniqueColors = Set(profiles.map(\.displayName))
        if uniqueColors.count <= 3 {
            value += 8
            notes.append("Color palette is focused")
        }

        if hasClassicMenswearPair(in: profiles) {
            value += 10
            notes.append("Classic menswear color pairing")
        }

        if hasHolidayRedGreenClash(in: profiles) {
            value -= 16
            notes.append("Red and green can read seasonal")
        }

        value += patternCompatibilityScore(items, notes: &notes)

        return (value, Array(notes.prefix(3)))
    }

    private func hasClassicMenswearPair(in profiles: [WardrobeColorProfile]) -> Bool {
        let families = Set(profiles.map(\.family))
        let colors = Set(profiles.map(\.displayName))

        if families.contains(.blue) && (families.contains(.brown) || families.contains(.olive)) {
            return true
        }
        if colors.contains("navy") && (colors.contains("cream") || colors.contains("white") || colors.contains("tan")) {
            return true
        }
        if colors.contains("denim") && (colors.contains("white") || colors.contains("gray") || colors.contains("grey")) {
            return true
        }
        return false
    }

    private func hasHolidayRedGreenClash(in profiles: [WardrobeColorProfile]) -> Bool {
        let colors = Set(profiles.map(\.displayName))
        guard colors.contains("red"), colors.contains("green") else { return false }
        return !colors.contains("burgundy") && !colors.contains("olive")
    }

    private func patternCompatibilityScore(_ items: [ClothingItem], notes: inout [String]) -> Double {
        let patterns = Set(items.map { ClothingInference.pattern(for: $0) }.filter { !$0.isEmpty && $0 != "solid" })
        guard !patterns.isEmpty else { return 0 }

        if patterns.count == 1 {
            notes.append("Pattern has room to stand out")
            return 4
        }

        notes.append("Multiple patterns may compete")
        return -12
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
        let levels = items.map { ClothingInference.formalityLevel(for: $0) }
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

private struct WardrobeColorProfile {
    var displayName: String
    var family: ColorFamily
    var hue: Double?
    var saturation: ColorSaturation

    var isNeutral: Bool {
        family == .neutral || family == .brown
    }

    private init(displayName: String, family: ColorFamily, hue: Double?, saturation: ColorSaturation) {
        self.displayName = displayName
        self.family = family
        self.hue = hue
        self.saturation = saturation
    }

    init?(colorName: String) {
        let normalized = colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "black":
            self.init(displayName: "black", family: .neutral, hue: nil, saturation: .low)
        case "white", "cream", "ivory":
            self.init(displayName: normalized, family: .neutral, hue: nil, saturation: .low)
        case "gray", "grey", "charcoal", "silver":
            self.init(displayName: normalized, family: .neutral, hue: nil, saturation: .low)
        case "navy", "denim":
            self.init(displayName: normalized, family: .blue, hue: 220, saturation: .low)
        case "blue":
            self.init(displayName: "blue", family: .blue, hue: 220, saturation: .medium)
        case "green":
            self.init(displayName: "green", family: .green, hue: 130, saturation: .high)
        case "olive":
            self.init(displayName: "olive", family: .olive, hue: 95, saturation: .low)
        case "red":
            self.init(displayName: "red", family: .red, hue: 0, saturation: .high)
        case "burgundy":
            self.init(displayName: "burgundy", family: .red, hue: 350, saturation: .medium)
        case "pink":
            self.init(displayName: "pink", family: .red, hue: 340, saturation: .medium)
        case "purple":
            self.init(displayName: "purple", family: .purple, hue: 275, saturation: .high)
        case "orange":
            self.init(displayName: "orange", family: .orange, hue: 30, saturation: .high)
        case "yellow", "gold":
            self.init(displayName: normalized, family: .yellow, hue: 55, saturation: .high)
        case "tan", "beige", "khaki", "brown", "taupe":
            self.init(displayName: normalized, family: .brown, hue: 35, saturation: .low)
        default:
            return nil
        }
    }
}

private enum ColorFamily: Hashable {
    case neutral
    case blue
    case green
    case olive
    case red
    case purple
    case orange
    case yellow
    case brown
}

private enum ColorSaturation: Equatable {
    case low
    case medium
    case high
}

private enum ColorHarmony {
    case sameFamily(String)
    case analogous
    case complementary
    case splitComplementary
    case clash

    var note: String? {
        switch self {
        case .sameFamily(let family):
            "\(family.capitalized) tones work together"
        case .analogous:
            "Adjacent colors work together"
        case .complementary:
            "Complementary colors need a neutral base"
        case .splitComplementary:
            "Contrast is balanced"
        case .clash:
            "Strong color contrast may clash"
        }
    }

    func score(neutralCount: Int) -> Double {
        switch self {
        case .sameFamily:
            14
        case .analogous:
            12
        case .complementary:
            neutralCount > 0 ? 8 : -6
        case .splitComplementary:
            neutralCount > 0 ? 6 : -4
        case .clash:
            -14
        }
    }

    static func relationship(between first: WardrobeColorProfile, and second: WardrobeColorProfile) -> ColorHarmony {
        if first.family == second.family {
            return .sameFamily(first.displayName)
        }

        guard let firstHue = first.hue, let secondHue = second.hue else {
            return .analogous
        }

        let distance = hueDistance(firstHue, secondHue)
        if distance <= 45 {
            return .analogous
        }
        if (150...210).contains(distance) {
            return .complementary
        }
        if (105...150).contains(distance) || (210...255).contains(distance) {
            return .splitComplementary
        }
        return first.saturation == .high && second.saturation == .high ? .clash : .splitComplementary
    }

    private static func hueDistance(_ first: Double, _ second: Double) -> Double {
        let rawDistance = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(rawDistance, 360 - rawDistance)
    }
}

private extension String {
    func containsAny(_ values: [String]) -> Bool {
        values.contains { contains($0) }
    }
}
