import Foundation
import SwiftData

struct TripAIOptions {
    var client: BackendOutfitAIClient
    var styleDescription: String
    var recentFeedback: [String]
}

@MainActor
struct TripPlanningService {
    private let weatherClient = OpenMeteoWeatherClient()

    func rebuildPackingList(for trip: Trip, closet: [ClothingItem], context: ModelContext) async {
        await refreshStopWeather(for: trip.stops)

        for list in trip.packingLists {
            context.delete(list)
        }

        let activeItems = closet.filter { $0.status == .active }
        let list = PackingList(title: "\(trip.title) Packing List", trip: trip)
        context.insert(list)
        trip.packingLists.append(list)

        let days = max(1, dates(from: trip.startsAt, through: trip.endsAt).count)
        let chosen = packingCandidates(from: activeItems, trip: trip, days: days)

        for item in chosen {
            let reason = packingReason(for: item, trip: trip, days: days)
            let packingItem = PackingListItem(quantity: 1, reason: reason, item: item, packingList: list)
            context.insert(packingItem)
            list.items.append(packingItem)
        }

        addQuantityBasedPackingItems(
            category: .underwear,
            needed: baseLayerQuantityNeeded(for: trip, days: days),
            closet: activeItems,
            list: list,
            context: context
        )

        addQuantityBasedPackingItems(
            category: .socks,
            needed: baseLayerQuantityNeeded(for: trip, days: days),
            closet: activeItems,
            list: list,
            context: context
        )

        for extra in packingExtras(for: trip, days: days, chosenItems: chosen) {
            let packingItem = PackingListItem(quantity: extra.quantity, reason: extra.title, item: nil, packingList: list)
            context.insert(packingItem)
            list.items.append(packingItem)
        }
    }

    func rebuildItinerary(
        for trip: Trip,
        closet: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        context: ModelContext,
        aiOptions: TripAIOptions? = nil
    ) async {
        await refreshStopWeather(for: trip.stops)

        for itineraryOutfit in trip.itineraryOutfits {
            if let outfit = itineraryOutfit.outfit {
                context.delete(outfit)
            }
            context.delete(itineraryOutfit)
        }

        let engine = OutfitRecommendationEngine()
        let stops = trip.stops.sorted { $0.startsAt < $1.startsAt }
        let stopsByDay = stopsGroupedByDay(stops)
        let tripDates = stopsByDay.keys.sorted()
        var plannedWearCounts: [UUID: Int] = [:]
        let exerciseTargetDays = exerciseTargetDays(for: trip, days: tripDates.count)
        var plannedExerciseDays = 0

        for (dayIndex, date) in tripDates.enumerated() {
            if shouldResetLaundryCounts(for: trip, dayIndex: dayIndex) {
                plannedWearCounts.removeAll()
            }

            let dayStops = stopsByDay[date, default: []].sorted { $0.startsAt < $1.startsAt }
            guard let primaryStop = dayStops.last else { continue }

            let locations = uniqueLocations(from: dayStops)
            let locationLabel = locations.joined(separator: " -> ")
            let isTravelDay = locations.count > 1
            let weather = await weatherInput(for: primaryStop, date: date, locationLabel: locationLabel)
            var contexts = itineraryContexts(for: dayStops, trip: trip, isTravelDay: isTravelDay)
            if plannedExerciseDays < exerciseTargetDays {
                contexts.append(.gym)
                plannedExerciseDays += 1
            }
            contexts = deduplicatedContexts(contexts)

            for outfitContext in contexts {
                let request = RecommendationRequest(
                    weather: weather,
                    occasion: outfitContext.occasion,
                    activity: outfitContext.activity,
                    selectedItem: nil
                )
                let availableCloset = closetAvailableForTripDay(
                    closet: closet,
                    plannedWearCounts: plannedWearCounts,
                    trip: trip
                )

                let localRecommendations = engine.recommend(
                    closet: availableCloset,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    limit: 3
                )
                let fallbackRecommendations = engine.recommend(
                    closet: closet,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    limit: 3
                )

                guard var recommendation = localRecommendations.first ?? fallbackRecommendations.first else {
                    continue
                }
                guard engine.isAcceptableOutfit(recommendation.items, request: request, stylePreference: stylePreference) else {
                    continue
                }

                if let aiOptions,
                   let aiRecommendation = await aiFilteredRecommendation(
                    localRecommendation: recommendation,
                    closet: availableCloset.isEmpty ? closet : availableCloset,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    aiOptions: aiOptions,
                    engine: engine
                   ) {
                    recommendation = aiRecommendation
                }

                recordPlannedWears(for: recommendation.items, counts: &plannedWearCounts)

                let outfit = Outfit(
                    name: "\(locationLabel) \(outfitContext.displayName) Outfit",
                    occasion: request.occasion,
                    activity: request.activity,
                    weatherSummary: request.weather.summary,
                    score: recommendation.score,
                    notes: recommendation.notes.joined(separator: "\n")
                )
                context.insert(outfit)

                for item in recommendation.items {
                    let link = OutfitItemLink(slot: item.category.displayName, outfit: outfit, item: item)
                    context.insert(link)
                    outfit.items.append(link)
                }

                let itinerary = DailyItineraryOutfit(date: date, location: locationLabel, activity: outfitContext.displayName, trip: trip, outfit: outfit)
                context.insert(itinerary)
                trip.itineraryOutfits.append(itinerary)
            }
        }
    }

    private func packingCandidates(from closet: [ClothingItem], trip: Trip, days: Int) -> [ClothingItem] {
        var chosen: [ClothingItem] = []
        let topLimit = clothingLimit(for: trip, category: .shirt, days: days, minimum: 1, maximum: 6)
        let bottomLimit = clothingLimit(for: trip, category: .pants, days: days, minimum: 1, maximum: 4)
        let activewearLimit = tripHasExercise(trip) ? clothingLimit(for: trip, category: .activewear, days: days, minimum: 1, maximum: 4) : 0
        let shoeLimit = min(2, max(1, days / 5 + 1))

        chosen.append(contentsOf: chooseItems(from: closet, categories: [.shirt, .blouse, .sweater, .dress], limit: topLimit))
        chosen.append(contentsOf: chooseItems(from: closet, categories: [.pants, .shorts, .skirt], limit: bottomLimit))
        chosen.append(contentsOf: chooseItems(from: closet, categories: [.shoes, .heels, .flats], limit: shoeLimit))
        chosen.append(contentsOf: chooseItems(from: closet, categories: [.activewear], limit: activewearLimit))

        let weatherText = trip.stops.map(\.expectedWeather).joined(separator: " ").lowercased()
        if weatherText.contains("rain") || weatherText.contains("cold") {
            chosen.append(contentsOf: chooseItems(
                from: closet.filter {
                    $0.category == .jacket ||
                        ClothingInference.weatherTags(for: $0).contains("rain") ||
                        ClothingInference.weatherTags(for: $0).contains("cold")
                },
                categories: Set(ClothingCategory.allCases),
                limit: 2
            ))
        }

        chosen.append(contentsOf: closet
            .filter { [.belt, .watch, .jewelry, .accessory, .bag, .purse].contains($0.category) }
            .prefix(3))

        var seen = Set<UUID>()
        return chosen.filter { seen.insert($0.id).inserted }
    }

    private func aiFilteredRecommendation(
        localRecommendation: OutfitRecommendation,
        closet: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        request: RecommendationRequest,
        aiOptions: TripAIOptions,
        engine: OutfitRecommendationEngine
    ) async -> OutfitRecommendation? {
        do {
            let response = try await aiOptions.client.suggestOutfit(
                request: AIOutfitRequest(
                    closet: closet.map(AIClothingItemPayload.init),
                    weatherSummary: request.weather.summary,
                    occasion: request.occasion,
                    activity: request.activity,
                    styleDescription: aiOptions.styleDescription,
                    selectedItemID: nil,
                    candidateItemIDs: localRecommendation.items.map(\.id),
                    localScore: localRecommendation.score,
                    localNotes: localRecommendation.notes,
                    recentFeedback: aiOptions.recentFeedback
                )
            )
            let itemsByID = Dictionary(uniqueKeysWithValues: closet.map { ($0.id, $0) })
            let items = response.itemIDs.compactMap { itemsByID[$0] }
            guard engine.isAcceptableOutfit(items, request: request, stylePreference: stylePreference) else { return nil }
            var recommendation = engine.scoreExistingOutfit(
                items: items,
                feedback: feedback,
                stylePreference: stylePreference,
                request: request,
                title: "AI Trip Fit"
            )
            recommendation.notes.append("AI: \(response.rationale)")
            recommendation.notes.append(contentsOf: response.cautions.map { "AI caution: \($0)" })
            return recommendation
        } catch {
            return nil
        }
    }

    private func chooseItems(from closet: [ClothingItem], categories: Set<ClothingCategory>, limit: Int) -> [ClothingItem] {
        closet
            .filter { categories.contains($0.category) }
            .sorted { $0.wearCount < $1.wearCount }
            .prefix(limit)
            .map { $0 }
    }

    private func clothingLimit(for trip: Trip, category: ClothingCategory, days: Int, minimum: Int, maximum: Int) -> Int {
        let laundryWindow = laundryWindowDays(for: trip, days: days)
        let wearsBeforeWash = wearLimit(for: category, trip: trip)
        let needed = Int(ceil(Double(laundryWindow) / Double(wearsBeforeWash)))
        return min(maximum, max(minimum, needed))
    }

    private func laundryWindowDays(for trip: Trip, days: Int) -> Int {
        guard trip.laundryIntervalDays > 0 else { return max(1, days) }
        return max(1, min(days, trip.laundryIntervalDays))
    }

    private func packingReason(for item: ClothingItem, trip: Trip, days: Int) -> String {
        let weatherText = trip.stops.map(\.expectedWeather).joined(separator: " ")
        if !weatherText.isEmpty, ClothingInference.weatherTags(for: item).contains(where: { weatherText.localizedCaseInsensitiveContains($0) }) {
            return "Weather match"
        }
        if trip.laundryIntervalDays > 0 || wearLimit(for: item.category, trip: trip) > 1 {
            let window = laundryWindowDays(for: trip, days: days)
            return "Covers \(window) days between laundry; rewear up to \(wearLimit(for: item.category, trip: trip))x"
        }
        return item.category.displayName
    }

    private func baseLayerQuantityNeeded(for trip: Trip, days: Int) -> Int {
        let exerciseDays = exerciseTargetDays(for: trip, days: days)
        return days + exerciseDays
    }

    private func addQuantityBasedPackingItems(
        category: ClothingCategory,
        needed: Int,
        closet: [ClothingItem],
        list: PackingList,
        context: ModelContext
    ) {
        var remaining = max(0, needed)
        guard remaining > 0 else { return }

        let candidates = closet
            .filter { $0.category == category }
            .sorted { $0.wearCount < $1.wearCount }

        for item in candidates where remaining > 0 {
            let quantity = min(max(1, item.quantity), remaining)
            let reason = "Need \(needed) total; saved quantity \(max(1, item.quantity))"
            let packingItem = PackingListItem(quantity: quantity, reason: reason, item: item, packingList: list)
            context.insert(packingItem)
            list.items.append(packingItem)
            remaining -= quantity
        }

        if remaining > 0 {
            let packingItem = PackingListItem(
                quantity: remaining,
                reason: "\(category.displayName) - add enough for the remaining trip days",
                item: nil,
                packingList: list
            )
            context.insert(packingItem)
            list.items.append(packingItem)
        }
    }

    private func packingExtras(for trip: Trip, days: Int, chosenItems: [ClothingItem]) -> [PackingExtra] {
        var extras: [PackingExtra] = []

        if tripHasExercise(trip), !chosenItems.contains(where: { $0.category == .activewear }) {
            let exerciseDays = max(1, exerciseTargetDays(for: trip, days: days))
            extras.append(PackingExtra(title: "Exercise outfit\(exerciseDays > 1 ? "s" : "")", quantity: exerciseDays))
        }

        return extras
    }

    private func tripHasExercise(_ trip: Trip) -> Bool {
        let text = ([trip.notes] + trip.stops.flatMap { [$0.customsNotes, $0.location] })
            .joined(separator: " ")
            .lowercased()
        return text.containsAny(["gym", "workout", "exercise", "run", "running", "training", "hike", "hiking"])
    }

    private func wearLimit(for category: ClothingCategory, trip: Trip) -> Int {
        switch category {
        case .shirt, .blouse, .dress:
            return max(1, trip.topWearsBeforeWash)
        case .pants, .shorts, .skirt:
            return max(1, trip.bottomWearsBeforeWash)
        case .sweater:
            return max(1, trip.sweaterWearsBeforeWash)
        case .jacket:
            return max(1, trip.jacketWearsBeforeWash)
        case .activewear:
            return max(1, trip.activewearWearsBeforeWash)
        case .underwear, .socks:
            return 1
        case .shoes, .heels, .flats, .belt, .watch, .jewelry, .accessory, .bag, .purse, .other:
            return max(1, trip.wearsBeforeWash)
        }
    }

    private func shouldResetLaundryCounts(for trip: Trip, dayIndex: Int) -> Bool {
        trip.laundryIntervalDays > 0 && dayIndex > 0 && dayIndex % trip.laundryIntervalDays == 0
    }

    private func closetAvailableForTripDay(
        closet: [ClothingItem],
        plannedWearCounts: [UUID: Int],
        trip: Trip
    ) -> [ClothingItem] {
        return closet.filter { item in
            guard isLaundryTracked(item) else { return true }
            return plannedWearCounts[item.id, default: 0] < wearLimit(for: item.category, trip: trip)
        }
    }

    private func recordPlannedWears(for items: [ClothingItem], counts: inout [UUID: Int]) {
        for item in items where isLaundryTracked(item) {
            counts[item.id, default: 0] += 1
        }
    }

    private func isLaundryTracked(_ item: ClothingItem) -> Bool {
        switch item.category {
        case .shirt, .blouse, .pants, .shorts, .dress, .skirt, .jacket, .sweater, .activewear, .underwear, .socks:
            return true
        case .shoes, .heels, .flats, .belt, .watch, .jewelry, .accessory, .bag, .purse, .other:
            return false
        }
    }

    private func refreshStopWeather(for stops: [TripStop]) async {
        for stop in stops where !stop.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hasManualWeather = !stop.expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !stop.expectedWeather.localizedCaseInsensitiveContains("lookup unavailable")
            guard !hasManualWeather else { continue }

            if let result = await weatherResult(for: stop.location, date: stop.startsAt) {
                stop.expectedWeather = weatherSummaryText(for: result)
            } else {
                if stop.expectedWeather.isEmpty {
                    stop.expectedWeather = "Weather lookup unavailable"
                }
            }
        }
    }

    private func stopsGroupedByDay(_ stops: [TripStop]) -> [Date: [TripStop]] {
        var result: [Date: [TripStop]] = [:]
        for stop in stops {
            for date in dates(from: stop.startsAt, through: stop.endsAt) {
                result[date, default: []].append(stop)
            }
        }
        return result
    }

    private func uniqueLocations(from stops: [TripStop]) -> [String] {
        var seen = Set<String>()
        return stops.compactMap { stop in
            let location = stop.location.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !location.isEmpty, seen.insert(location).inserted else { return nil }
            return location
        }
    }

    private func weatherInput(for stop: TripStop, date: Date, locationLabel: String) async -> WeatherInput {
        if let result = await weatherResult(for: stop.location, date: date) {
            stop.expectedWeather = weatherSummaryText(for: result)
            var input = result.input
            input.location = locationLabel
            return input
        }

        return WeatherInput(
            temperatureF: inferredTemperature(from: stop.expectedWeather),
            isRaining: stop.expectedWeather.localizedCaseInsensitiveContains("rain"),
            windMph: inferredWind(from: stop.expectedWeather),
            location: locationLabel,
            humidityPercent: inferredHumidity(from: stop.expectedWeather)
        )
    }

    private func weatherResult(for location: String, date: Date) async -> WeatherLookupResult? {
        if let daily = try? await weatherClient.dailyWeather(for: location, date: date) {
            return daily
        }
        return try? await weatherClient.currentWeather(for: location)
    }

    private func weatherSummaryText(for result: WeatherLookupResult) -> String {
        [
            "\(Int(result.input.temperatureF.rounded()))F",
            result.condition,
            "wind \(Int(result.input.windMph.rounded())) mph",
            result.input.humidityPercent.map { "humidity \(Int($0.rounded()))%" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func itineraryContexts(for stops: [TripStop], trip: Trip, isTravelDay: Bool) -> [OutfitContextOption] {
        let text = ([trip.notes] + stops.map(\.customsNotes))
            .joined(separator: " ")
            .lowercased()
        var contexts: [OutfitContextOption] = []
        let hasWorkContext = text.containsAny(["work", "office", "business", "conference", "meeting", "pilot", "flight", "flying", "airline", "duty"])

        if isTravelDay && !hasWorkContext {
            contexts.append(.travelDay)
        }
        if hasWorkContext {
            contexts.append(.workDay)
        }
        if text.containsAny(["wedding", "formal", "ceremony"]) {
            contexts.append(.wedding)
        }
        if text.containsAny(["date", "date night"]) {
            contexts.append(.dateNight)
        } else if text.containsAny(["dinner", "night", "restaurant", "evening"]) {
            contexts.append(.dinner)
        }
        if text.containsAny(["casual", "fun", "sightseeing", "walking", "tour", "errands"]) {
            contexts.append(.walkingAroundCity)
        }

        if contexts.isEmpty {
            contexts.append(isTravelDay ? .travelDay : .casualDay)
        }

        return contexts
    }

    private func deduplicatedContexts(_ contexts: [OutfitContextOption]) -> [OutfitContextOption] {
        var seen = Set<String>()
        return contexts.filter { seen.insert($0.rawValue).inserted }
    }

    private func exerciseTargetDays(for trip: Trip, days: Int) -> Int {
        guard tripHasExercise(trip) else { return 0 }
        let text = ([trip.notes] + trip.stops.map(\.customsNotes))
            .joined(separator: " ")
            .lowercased()
        let numbers = text
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .filter { (1...max(1, days)).contains($0) }

        return min(days, numbers.first ?? 1)
    }

    private func dates(from start: Date, through end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = Calendar.current.startOfDay(for: start)
        let final = Calendar.current.startOfDay(for: end)

        while cursor <= final {
            result.append(cursor)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return result
    }

    private func inferredTemperature(from text: String) -> Double {
        let numbers = text.split { !$0.isNumber }.compactMap { Double($0) }
        if let first = numbers.first {
            return first
        }
        if text.localizedCaseInsensitiveContains("cold") {
            return 48
        }
        if text.localizedCaseInsensitiveContains("hot") {
            return 86
        }
        return 70
    }

    private func inferredWind(from text: String) -> Double {
        let numbers = text.split { !$0.isNumber && $0 != "." }.compactMap { Double($0) }
        if numbers.count > 1 {
            return numbers[1]
        }
        return text.localizedCaseInsensitiveContains("wind") ? 18 : 5
    }

    private func inferredHumidity(from text: String) -> Double? {
        let lowercased = text.lowercased()
        guard lowercased.contains("humid") || lowercased.contains("humidity") || lowercased.contains("%") else {
            return nil
        }
        return text.split { !$0.isNumber && $0 != "." }.compactMap { Double($0) }.last
    }
}

private struct PackingExtra {
    var title: String
    var quantity: Int
}

private extension String {
    func containsAny(_ values: [String]) -> Bool {
        values.contains { contains($0) }
    }
}
