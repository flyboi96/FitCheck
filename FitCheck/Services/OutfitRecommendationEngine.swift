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

enum OutfitContextOption: String, CaseIterable, Identifiable {
    case casualDay = "casual day"
    case dateNight = "date night"
    case workDay = "work day"
    case travelDay = "travel day"
    case dinner
    case gym
    case walkingAroundCity = "walking around city"
    case outdoors
    case errands
    case wedding

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .casualDay: "Casual Day"
        case .dateNight: "Date Night"
        case .workDay: "Work / Office"
        case .travelDay: "Travel Day"
        case .dinner: "Dinner"
        case .gym: "Gym"
        case .walkingAroundCity: "Walking Around City"
        case .outdoors: "Outdoors"
        case .errands: "Errands"
        case .wedding: "Wedding / Formal"
        }
    }

    var occasion: String {
        switch self {
        case .casualDay, .errands, .outdoors:
            OccasionOption.casual.rawValue
        case .dateNight:
            OccasionOption.dateNight.rawValue
        case .workDay:
            OccasionOption.work.rawValue
        case .travelDay:
            OccasionOption.travelDay.rawValue
        case .dinner:
            OccasionOption.dinner.rawValue
        case .gym:
            OccasionOption.gym.rawValue
        case .walkingAroundCity:
            OccasionOption.walkingAroundCity.rawValue
        case .wedding:
            OccasionOption.wedding.rawValue
        }
    }

    var activity: String {
        switch self {
        case .casualDay:
            ActivityOption.walkingAroundCity.rawValue
        case .dateNight, .dinner:
            ActivityOption.dinner.rawValue
        case .workDay:
            ActivityOption.office.rawValue
        case .travelDay:
            ActivityOption.travel.rawValue
        case .gym:
            ActivityOption.gym.rawValue
        case .walkingAroundCity:
            ActivityOption.walkingAroundCity.rawValue
        case .outdoors:
            ActivityOption.outdoors.rawValue
        case .errands:
            ActivityOption.errands.rawValue
        case .wedding:
            ActivityOption.formalEvent.rawValue
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

        if text.containsAny(["linen", "seersucker", "short sleeve", "t-shirt", "tee", "shorts", "skirt", "sundress", "lightweight"]) {
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
        if category == .activewear {
            tags.insert("hot")
        }
        if category == .shorts || category == .skirt {
            tags.insert("hot")
        }

        return tags.sorted()
    }

    private static func occasionTags(name: String, category: ClothingCategory) -> [String] {
        let text = normalized(name)
        var tags = Set(["casual"])

        if text.containsAny(["button-down", "button down", "oxford", "chino", "loafer", "blazer", "dress", "blouse", "heel", "flat", "merino"]) {
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
        if category == .activewear {
            tags.formUnion(["gym", "travel day"])
        }
        if category == .dress || category == .blouse || category == .skirt || category == .heels || category == .flats {
            tags.formUnion(["dinner", "date night", "work"])
        }
        if category == .underwear || category == .socks {
            tags.formUnion(["casual", "travel day", "gym"])
        }
        if category == .bag || category == .purse || category == .shoes || category == .flats {
            tags.insert("travel day")
        }

        return tags.sorted()
    }

    private static func activityTags(name: String, category: ClothingCategory) -> [String] {
        let text = normalized(name)
        var tags = Set(["errands", "walking around city"])

        if text.containsAny(["button-down", "button down", "oxford", "blazer", "chino", "dress", "blouse", "heel", "flat"]) {
            tags.formUnion(["office", "dinner"])
        }
        if text.containsAny(["gym", "running", "trainer", "athletic", "performance"]) {
            tags.insert("gym")
        }
        if category == .activewear {
            tags.formUnion(["gym", "travel"])
        }
        if category == .underwear || category == .socks {
            tags.formUnion(["gym", "travel"])
        }
        if text.containsAny(["boots", "shell", "waterproof", "jacket", "bag"]) {
            tags.formUnion(["travel", "outdoors"])
        }
        if category == .dress || category == .blouse || category == .skirt || category == .heels || category == .flats {
            tags.formUnion(["office", "dinner"])
        }
        if category == .bag || category == .purse {
            tags.insert("travel")
        }

        return tags.sorted()
    }

    private static func formalityLevel(name: String, category: ClothingCategory) -> Int {
        let text = normalized(name)
        if text.containsAny(["suit", "tie", "tux", "formal"]) {
            return 5
        }
        if text.containsAny(["blazer", "dress", "loafer", "heel", "oxford", "button-down", "button down", "blouse"]) {
            return 4
        }
        if text.containsAny(["merino", "chino", "polo", "boot"]) {
            return 3
        }
        if text.containsAny(["gym", "running", "athletic", "hoodie", "shorts", "sneaker"]) {
            return 2
        }
        switch category {
        case .activewear, .underwear, .socks:
            return 1
        case .watch, .belt, .jewelry:
            return 3
        case .jacket, .sweater:
            return 3
        case .dress, .blouse, .skirt, .heels, .flats:
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
    var humidityPercent: Double? = nil

    var summary: String {
        var parts = ["\(Int(temperatureF.rounded()))F"]
        if isRaining {
            parts.append("rain")
        }
        if windMph >= 15 {
            parts.append("\(Int(windMph.rounded())) mph wind")
        }
        if let humidityPercent {
            parts.append("\(Int(humidityPercent.rounded()))% humidity")
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
    var id = UUID()
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
    func scoreExistingOutfit(
        items: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest,
        title: String
    ) -> OutfitRecommendation {
        let scored = score(
            items: items,
            feedback: feedback,
            stylePreference: stylePreference,
            request: request
        )

        return OutfitRecommendation(
            title: title,
            items: items,
            score: scored.value,
            notes: scored.notes
        )
    }

    func isCompleteOutfit(_ items: [ClothingItem], request: RecommendationRequest? = nil) -> Bool {
        completenessIssues(for: items, request: request).isEmpty
    }

    func isAcceptableOutfit(_ items: [ClothingItem], request: RecommendationRequest, stylePreference: StylePreference? = nil) -> Bool {
        isCompleteOutfit(items, request: request) && !violatesHardFashionRules(items, request: request, stylePreference: stylePreference)
    }

    func recommend(
        closet: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest,
        limit: Int = 3
    ) -> [OutfitRecommendation] {
        let activeItems = closet.filter { $0.status == .active }
        let selected = request.selectedItem
        let needsExerciseClothing = isExerciseContext(request)
        let topCategories: Set<ClothingCategory> = needsExerciseClothing
            ? [.shirt, .blouse, .sweater, .dress, .activewear]
            : [.shirt, .blouse, .sweater, .dress]
        let bottomCategories: Set<ClothingCategory> = needsExerciseClothing
            ? [.pants, .shorts, .skirt, .activewear]
            : [.pants, .shorts, .skirt]
        let shoeCategories: Set<ClothingCategory> = needsExerciseClothing
            ? [.shoes, .heels, .flats, .activewear]
            : [.shoes, .heels, .flats]
        let selectedTop = selected.flatMap { isTopItem($0, request: request) ? $0 : nil }
        let selectedBottom = selected.flatMap { isBottomItem($0, request: request) ? $0 : nil }
        let selectedShoe = selected.flatMap { isFootwearItem($0, request: request) ? $0 : nil }

        let tops = constrainedPool(
            categories: topCategories,
            items: activeItems,
            selectedItem: selectedTop
        )
        .filter { isTopItem($0, request: request) && !isFootwearItem($0, request: request) }
        .filter { !needsExerciseClothing || isExerciseItem($0) }
        let bottomPool = constrainedBottomPool(
            categories: bottomCategories,
            items: activeItems,
            selectedItem: selectedBottom
        )
        .filter { item in
            guard let item else { return true }
            return isBottomItem(item, request: request) && !isFootwearItem(item, request: request)
        }
        .filter { item in
            guard let item else { return true }
            return !needsExerciseClothing || isExerciseItem(item)
        }
        let adjustedBottomPool = bottomPool
        let canUseOnePieceTop = tops.contains { $0.category == .dress || (needsExerciseClothing && isBottomItem($0, request: request)) }
        let bottoms = adjustedBottomPool.isEmpty && canUseOnePieceTop ? [nil] : adjustedBottomPool
        let shoes = constrainedPool(
            categories: shoeCategories,
            items: activeItems,
            selectedItem: selectedShoe
        )
        .filter { isFootwearItem($0, request: request) }
        .filter { !needsExerciseClothing || isExerciseItem($0) }

        guard !tops.isEmpty, !bottoms.isEmpty, !shoes.isEmpty else {
            return []
        }

        let jackets = constrainedOptionalPool(
            categories: [.jacket],
            items: activeItems,
            selectedItem: selected,
            weather: request.weather,
            stylePreference: stylePreference
        )
        let accessories = constrainedOptionalPool(
            categories: [.belt, .watch, .jewelry, .accessory, .bag, .purse],
            items: activeItems,
            selectedItem: selected,
            weather: request.weather,
            stylePreference: stylePreference
        )

        var recommendations: [OutfitRecommendation] = []

        for top in tops.prefix(8) {
            let availableBottoms = bottoms.filter { $0?.id != top.id }
            let bottomOptions = top.category == .dress || (needsExerciseClothing && availableBottoms.isEmpty && isBottomItem(top, request: request))
                ? [nil]
                : Array(availableBottoms.prefix(8))
            for bottom in bottomOptions {
                if let bottom, bottom.id == top.id {
                    continue
                }
                for shoe in shoes.prefix(6) {
                    if shoe.id == top.id || bottom.map({ shoe.id == $0.id }) == true {
                        continue
                    }
                    for jacket in jackets.prefix(4) {
                        if let jacket,
                           jacket.id == top.id ||
                            bottom.map({ jacket.id == $0.id }) == true ||
                            jacket.id == shoe.id {
                            continue
                        }
                        for accessory in accessories.prefix(4) {
                            if let accessory,
                               accessory.id == top.id ||
                                bottom.map({ accessory.id == $0.id }) == true ||
                                accessory.id == shoe.id ||
                                jacket.map({ accessory.id == $0.id }) == true {
                                    continue
                            }
                            var outfitItems = [top, shoe]
                            if let bottom {
                                outfitItems.append(bottom)
                            }
                            if let jacket {
                                outfitItems.append(jacket)
                            }
                            if let accessory {
                                outfitItems.append(accessory)
                            }
                            if let selected, !outfitItems.contains(where: { $0.id == selected.id }) {
                                outfitItems.append(selected)
                            }
                            if needsExerciseClothing && !outfitItems.contains(where: isExerciseItem) {
                                continue
                            }
                            if violatesHardFashionRules(outfitItems, request: request, stylePreference: stylePreference) {
                                continue
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

    private func constrainedBottomPool(
        categories: Set<ClothingCategory>,
        items: [ClothingItem],
        selectedItem: ClothingItem?
    ) -> [ClothingItem?] {
        if let selectedItem, selectedItem.category == .dress {
            return [nil]
        }
        if let selectedItem, categories.contains(selectedItem.category) {
            return [selectedItem]
        }

        return items
            .filter { categories.contains($0.category) }
            .sorted { itemSortScore($0) > itemSortScore($1) }
            .map { Optional($0) }
    }

    private func constrainedOptionalPool(
        categories: Set<ClothingCategory>,
        items: [ClothingItem],
        selectedItem: ClothingItem?,
        weather: WeatherInput,
        stylePreference: StylePreference?
    ) -> [ClothingItem?] {
        if let selectedItem, categories.contains(selectedItem.category) {
            return [selectedItem]
        }

        let pool = items
            .filter { categories.contains($0.category) }
            .filter { item in
                if item.category == .jacket {
                    return shouldConsiderJacket(item, weather: weather, stylePreference: stylePreference)
                }
                return true
            }
            .sorted { itemSortScore($0) > itemSortScore($1) }

        return [nil] + pool.map { Optional($0) }
    }

    private func shouldConsiderJacket(_ item: ClothingItem, weather: WeatherInput, stylePreference: StylePreference?) -> Bool {
        let hotAndHumid = weather.temperatureF >= 75 && (weather.humidityPercent ?? 0) >= 65
        let hot = weather.temperatureF >= 82

        if hot || hotAndHumid {
            if stylePreference?.temperatureSensitivity == .runsCold, weather.temperatureF < 80, !weather.isRaining {
                return true
            }
            guard weather.isRaining || weather.windMph >= 18 else {
                return stylePreference?.temperatureSensitivity == .runsCold && weather.temperatureF < 78
            }
            return isRainShell(item)
        }

        return weather.temperatureF <= 68 ||
            weather.isRaining ||
            weather.windMph >= 18 ||
            ClothingInference.weatherTags(for: item).contains("rain")
    }

    private func score(
        items: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest
    ) -> (value: Double, notes: [String]) {
        var value = 50.0
        var notes: [String] = []
        let completeness = completenessScore(items: items, request: request)
        value += completeness.value
        notes.append(contentsOf: completeness.notes)

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

        let feedbackValue = feedbackScore(items: items, feedback: feedback)
        value += feedbackValue.value
        notes.append(contentsOf: feedbackValue.notes)

        let fashionValue = fashionRuleScore(items: items, request: request, stylePreference: stylePreference)
        value += fashionValue.value
        notes.append(contentsOf: fashionValue.notes)

        let formalityValue = formalityScore(items: items, request: request)
        value += formalityValue.value
        notes.append(contentsOf: formalityValue.notes)

        return (value.rounded(), limitedUniqueNotes(notes))
    }

    private func itemScore(
        _ item: ClothingItem,
        request: RecommendationRequest,
        stylePreference: StylePreference?
    ) -> (value: Double, notes: [String]) {
        var value = 0.0
        var notes: [String] = []

        value += weatherScore(item, weather: request.weather)
        notes.append(contentsOf: weatherNotes(for: item, weather: request.weather, request: request))
        let comfort = temperatureComfortScore(item, weather: request.weather, stylePreference: stylePreference)
        value += comfort.value
        notes.append(contentsOf: comfort.notes)

        let occasionTags = ClothingInference.occasionTags(for: item)
        let activityTags = ClothingInference.activityTags(for: item)
        value += tagScore(occasionTags, target: request.occasion)
        value += tagScore(activityTags, target: request.activity)

        let targetFormality = targetFormality(for: request.occasion)
        let formalityDistance = abs(ClothingInference.formalityLevel(for: item) - targetFormality)
        value -= Double(formalityDistance * 4)

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
            if item.category == .shorts || item.category == .skirt {
                value -= 24
            }
        } else if weather.temperatureF >= 82 {
            value += weatherTags.contains("hot") ? 16 : 0
            if item.category == .jacket || item.category == .sweater {
                value -= isRainShell(item) && weather.isRaining ? 14 : 30
            }
            if item.category == .shorts || item.category == .skirt {
                value += 10
            }
        } else if weatherTags.contains("mild") {
            value += 8
        }

        if weather.isRaining {
            value += weatherTags.contains("rain") ? 18 : -8
            if [.shoes, .heels, .flats].contains(item.category) && weatherTags.contains("suede") {
                value -= 28
            }
        }

        if weather.windMph >= 18 {
            value += weatherTags.contains("wind") ? 8 : 0
        }

        if let humidity = weather.humidityPercent, humidity >= 70, weather.temperatureF >= 75 {
            value += weatherTags.contains("hot") ? 6 : 0
            if item.category == .jacket || item.category == .sweater {
                value -= isRainShell(item) && weather.isRaining ? 10 : 24
            }
        }

        return value
    }

    private func weatherNotes(for item: ClothingItem, weather: WeatherInput, request: RecommendationRequest) -> [String] {
        var notes: [String] = []
        let weatherTags = ClothingInference.weatherTags(for: item)

        if isExerciseContext(request), isExerciseItem(item) {
            notes.append("Gym-specific clothing selected")
        }

        if weather.temperatureF >= 82, weatherTags.contains("hot") {
            if ![.jacket, .sweater].contains(item.category) {
                notes.append("\(item.name) is heat-friendly")
            }
        }

        if weather.isRaining, weatherTags.contains("rain"), [.shoes, .heels, .flats, .jacket].contains(item.category) {
            notes.append("\(item.name) handles wet weather")
        }

        if weather.temperatureF <= 50, weatherTags.contains("cold") {
            notes.append("\(item.name) adds cold-weather warmth")
        }

        if let humidity = weather.humidityPercent, humidity >= 70, weather.temperatureF >= 75, item.category == .jacket, !isRainShell(item) {
            notes.append("\(item.name) is a poor hot-humidity layer")
        }

        return notes
    }

    private func temperatureComfortScore(
        _ item: ClothingItem,
        weather: WeatherInput,
        stylePreference: StylePreference?
    ) -> (value: Double, notes: [String]) {
        guard let stylePreference else { return (0, []) }

        let humidity = weather.humidityPercent ?? 0
        let hotForRunsHot = weather.temperatureF >= 72 || (weather.temperatureF >= 68 && humidity >= 65)
        let coolForRunsCold = weather.temperatureF <= 78 || (weather.temperatureF <= 82 && weather.windMph >= 12)

        switch stylePreference.temperatureSensitivity {
        case .runsHot where hotForRunsHot:
            switch item.category {
            case .shorts:
                return (16, ["Shorts fit your runs-hot profile"])
            case .shirt, .activewear:
                return (8, [])
            case .pants:
                return (-8, [])
            case .jacket, .sweater:
                return (-28, ["Layer is warm for your runs-hot profile"])
            default:
                return (0, [])
            }
        case .runsCold where coolForRunsCold:
            switch item.category {
            case .pants:
                return (10, ["Pants fit your runs-cold profile"])
            case .jacket, .sweater:
                return (8, [])
            case .shorts:
                return (-14, ["Shorts may feel cool for your runs-cold profile"])
            default:
                return (0, [])
            }
        default:
            return (0, [])
        }
    }

    private func completenessScore(items: [ClothingItem], request: RecommendationRequest) -> (value: Double, notes: [String]) {
        let issues = completenessIssues(for: items, request: request)
        if issues.isEmpty {
            return (10, [])
        }

        return (-Double(issues.count * 45), issues)
    }

    private func completenessIssues(for items: [ClothingItem], request: RecommendationRequest?) -> [String] {
        let hasDress = items.contains { $0.category == .dress }
        let hasTop = items.contains { isTopItem($0, request: request) }
        let hasBottom = items.contains { isBottomItem($0, request: request) }
        let hasShoes = items.contains { isFootwearItem($0, request: request) }
        var issues: [String] = []

        if !hasDress && !hasTop {
            issues.append("Missing a shirt, blouse, sweater, dress, or exercise top")
        }
        if !hasDress && !hasBottom {
            issues.append("Missing pants, shorts, skirt, dress, or exercise bottom")
        }
        if !hasShoes {
            issues.append("Missing shoes")
        }
        if let request, isExerciseContext(request), !items.contains(where: isExerciseItem) {
            issues.append("Missing exercise-specific clothing")
        }

        return issues
    }

    private func isTopItem(_ item: ClothingItem, request: RecommendationRequest?) -> Bool {
        if [.shirt, .blouse, .sweater, .dress].contains(item.category) {
            return true
        }
        guard item.category == .activewear else { return false }
        if isFootwearItem(item, request: request) {
            return false
        }
        if let request, isExerciseContext(request) {
            let text = item.name.lowercased()
            if text.containsAny(["short", "pant", "legging", "tight", "jogger", "bottom"]) {
                return false
            }
            return true
        }
        let text = item.name.lowercased()
        return text.containsAny(["shirt", "tee", "t-shirt", "tank", "top", "hoodie"])
    }

    private func isBottomItem(_ item: ClothingItem, request: RecommendationRequest?) -> Bool {
        if [.pants, .shorts, .skirt, .dress].contains(item.category) {
            return true
        }
        guard item.category == .activewear else { return false }
        if isFootwearItem(item, request: request) {
            return false
        }
        if let request, isExerciseContext(request) {
            let text = item.name.lowercased()
            return !text.containsAny(["shirt", "tee", "t-shirt", "tank", "top", "hoodie"])
        }
        let text = item.name.lowercased()
        return text.containsAny(["short", "pant", "legging", "tight", "jogger", "bottom"])
    }

    private func tagScore(_ tags: [String], target: String) -> Double {
        let storedTags = tags.joined(separator: ", ")
        return tagScore(storedTags, target: target)
    }

    private func tagsMatch(_ tags: [String], target: String) -> Bool {
        tags.joined(separator: ", ").fitcheckContainsTag(target)
    }

    private func tagScore(_ tags: String, target: String) -> Double {
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

    private func feedbackScore(items: [ClothingItem], feedback: [Feedback]) -> (value: Double, notes: [String]) {
        let combinationKey = OutfitRecommendation.combinationKey(for: items)
        var value = 0.0
        var notes: [String] = []

        for entry in feedback {
            if entry.type == .goodOutfit {
                if !entry.combinationKey.isEmpty && entry.combinationKey == combinationKey {
                    value += 18
                    notes.append("Past positive combo")
                }
                if let feedbackItem = entry.item, items.contains(where: { $0.id == feedbackItem.id }) {
                    value += 4
                }
            } else if entry.type.isNegative {
                if !entry.combinationKey.isEmpty && entry.combinationKey == combinationKey {
                    value -= 45
                    notes.append("Past negative combo")
                }
                if let feedbackItem = entry.item, items.contains(where: { $0.id == feedbackItem.id }) {
                    value -= 8
                }
            }
        }

        return (value, notes)
    }

    private func fashionRuleScore(
        items: [ClothingItem],
        request: RecommendationRequest,
        stylePreference: StylePreference?
    ) -> (value: Double, notes: [String]) {
        var value = 0.0
        var notes: [String] = []

        if hasShortsWithBoots(items) {
            value -= 120
            notes.append("Hard style rule: avoid shorts with boots")
        }

        if hotHumidJacketIsHardNo(weather: request.weather, stylePreference: stylePreference),
           items.contains(where: { $0.category == .jacket && !isRainShell($0) }) {
            value -= 90
            notes.append("Hard weather rule: skip non-rain-shell jackets in hot humidity")
        }

        return (value, notes)
    }

    private func violatesHardFashionRules(
        _ items: [ClothingItem],
        request: RecommendationRequest,
        stylePreference: StylePreference?
    ) -> Bool {
        if hasShortsWithBoots(items) {
            return true
        }

        if hotHumidJacketIsHardNo(weather: request.weather, stylePreference: stylePreference),
           items.contains(where: { $0.category == .jacket && !isRainShell($0) }) {
            return true
        }

        return false
    }

    private func hotHumidJacketIsHardNo(weather: WeatherInput, stylePreference: StylePreference?) -> Bool {
        let humidity = weather.humidityPercent ?? 0
        switch stylePreference?.temperatureSensitivity ?? .balanced {
        case .runsHot:
            return weather.temperatureF >= 72 && humidity >= 60
        case .balanced:
            return weather.temperatureF >= 82 && humidity >= 65
        case .runsCold:
            return weather.temperatureF >= 88 && humidity >= 70
        }
    }

    private func hasShortsWithBoots(_ items: [ClothingItem]) -> Bool {
        items.contains { $0.category == .shorts } &&
            items.contains { [.shoes, .heels, .flats].contains($0.category) && isBoot($0) }
    }

    private func isBoot(_ item: ClothingItem) -> Bool {
        [item.name, item.notes, item.brand]
            .joined(separator: " ")
            .lowercased()
            .contains("boot")
    }

    private func formalityScore(items: [ClothingItem], request: RecommendationRequest) -> (value: Double, notes: [String]) {
        var value = -formalitySpreadPenalty(items)
        let target = targetFormality(for: request.occasion)
        let mainItems = items.filter { [.shirt, .blouse, .sweater, .dress, .pants, .shorts, .skirt, .activewear, .shoes, .heels, .flats].contains($0.category) }
        guard !mainItems.isEmpty else { return (value, []) }

        let average = Double(mainItems.map { ClothingInference.formalityLevel(for: $0) }.reduce(0, +)) / Double(mainItems.count)
        let distance = abs(average - Double(target))
        if distance <= 0.75 {
            value += 8
            return (value, ["Dressiness fits \(contextLabel(for: request))"])
        }
        if distance >= 1.75 {
            value -= 12
            return (value, ["Dressiness may be off for \(contextLabel(for: request))"])
        }

        return (value, [])
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

    private func contextLabel(for request: RecommendationRequest) -> String {
        let occasion = request.occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = request.activity.trimmingCharacters(in: .whitespacesAndNewlines)

        if !occasion.isEmpty, !activity.isEmpty, occasion != activity {
            return "\(occasion) / \(activity)"
        }
        return occasion.isEmpty ? activity : occasion
    }

    private func isExerciseContext(_ request: RecommendationRequest) -> Bool {
        "\(request.occasion) \(request.activity)"
            .lowercased()
            .containsAny(["gym", "workout", "exercise", "running", "run", "training", "fitness"])
    }

    private func isExerciseItem(_ item: ClothingItem) -> Bool {
        if item.category == .activewear {
            return true
        }
        let text = [
            item.name,
            item.notes,
            item.activitySuitability,
            item.occasionSuitability
        ]
        .joined(separator: " ")
        .lowercased()
        return text.containsAny(["gym", "workout", "exercise", "running", "run", "training", "athletic", "performance", "trainer", "sneaker", "tennis"])
    }

    private func isFootwearItem(_ item: ClothingItem, request: RecommendationRequest?) -> Bool {
        if [.shoes, .heels, .flats].contains(item.category) {
            return true
        }

        guard item.category == .activewear, request.map(isExerciseContext) == true else {
            return false
        }

        let text = [
            item.name,
            item.notes,
            item.activitySuitability
        ]
        .joined(separator: " ")
        .lowercased()
        return text.containsAny(["shoe", "sneaker", "trainer", "running shoe", "runner"])
    }

    private func isRainShell(_ item: ClothingItem) -> Bool {
        let text = [
            item.name,
            item.brand,
            item.notes,
            item.weatherSuitability,
            item.activitySuitability
        ]
        .joined(separator: " ")
        .lowercased()

        let hasRainShellSignal = text.containsAny(["rain", "shell", "waterproof", "water-resistant", "gore-tex", "windbreaker"])
        let hasHeavySignal = text.containsAny(["down", "insulated", "puffer", "parka", "fleece", "wool", "heavy", "coat"])
        return hasRainShellSignal && !hasHeavySignal
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

    private func limitedUniqueNotes(_ notes: [String]) -> [String] {
        var seen = Set<String>()
        return notes.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
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
