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
        trip.packingLists.removeAll()

        let activeItems = closet.filter { $0.status == .active }
        let list = PackingList(title: "\(trip.title) Packing List", trip: trip)
        context.insert(list)
        trip.packingLists.append(list)

        let days = max(1, dates(from: trip.startsAt, through: trip.endsAt).count)
        let chosen = packingCandidates(from: activeItems, trip: trip, days: days)

        for item in chosen {
            let reason = packingReason(for: item, trip: trip, days: days)
            upsertPackingItem(quantity: 1, reason: reason, item: item, list: list, context: context)
        }

        let exerciseDays = exerciseTargetDays(for: trip, days: days)
        var packedBaseLayerQuantities: [UUID: Int] = [:]

        addBaseLayerPackingItems(
            category: .underwear,
            needed: days,
            purpose: .daily,
            trip: trip,
            closet: activeItems,
            list: list,
            context: context,
            packedQuantities: &packedBaseLayerQuantities
        )

        addBaseLayerPackingItems(
            category: .socks,
            needed: days,
            purpose: .daily,
            trip: trip,
            closet: activeItems,
            list: list,
            context: context,
            packedQuantities: &packedBaseLayerQuantities
        )

        addBaseLayerPackingItems(
            category: .underwear,
            needed: exerciseDays,
            purpose: .exercise,
            trip: trip,
            closet: activeItems,
            list: list,
            context: context,
            packedQuantities: &packedBaseLayerQuantities
        )

        addBaseLayerPackingItems(
            category: .socks,
            needed: exerciseDays,
            purpose: .exercise,
            trip: trip,
            closet: activeItems,
            list: list,
            context: context,
            packedQuantities: &packedBaseLayerQuantities
        )

        for extra in packingExtras(for: trip, days: days, chosenItems: chosen) {
            upsertPackingItem(quantity: extra.quantity, reason: extra.title, item: nil, list: list, context: context)
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
        trip.itineraryOutfits.removeAll()

        let engine = OutfitRecommendationEngine()
        let stops = trip.stops.sorted { $0.startsAt < $1.startsAt }
        let stopsByDay = stopsGroupedByDay(stops)
        let tripDates = stopsByDay.keys.sorted()
        var plannedWearCounts: [UUID: Int] = [:]
        var lastPlannedDayByItemID: [UUID: Int] = [:]
        let explicitDailyPlanning = tripUsesExplicitContexts(trip)
        let activeCloset = closet.filter { $0.status == .active }
        let existingPackingItemIDs = Set(trip.packingLists.flatMap(\.items).compactMap { $0.item?.id })
        let preferredPackingCloset = existingPackingItemIDs.isEmpty
            ? packingCandidates(from: activeCloset, trip: trip, days: max(1, tripDates.count))
            : activeCloset.filter { existingPackingItemIDs.contains($0.id) }
        let preferredPackingIDs = Set(preferredPackingCloset.map(\.id))

        for (dayIndex, date) in tripDates.enumerated() {
            if shouldResetLaundryCounts(for: trip, dayIndex: dayIndex) {
                plannedWearCounts.removeAll()
            }

            let dayStops = stopsByDay[date, default: []].sorted { $0.startsAt < $1.startsAt }
            let locationStops = locationStops(for: dayStops)
            guard let primaryStop = locationStops.last ?? dayStops.last else { continue }

            let locations = uniqueLocations(from: locationStops.isEmpty ? dayStops : locationStops)
            let locationLabel = locations.joined(separator: " -> ")
            let isTravelDay = locations.count > 1
            let weather = await weatherInput(for: primaryStop, date: date, locationLabel: locationLabel)
            let contexts = deduplicatedContexts(itineraryContexts(
                for: dayStops,
                trip: trip,
                isTravelDay: isTravelDay,
                explicitDailyPlanning: explicitDailyPlanning
            ))

            for outfitContext in contexts {
                let request = RecommendationRequest(
                    weather: weather,
                    occasion: outfitContext.occasion,
                    activity: outfitContext.activity,
                    selectedItem: nil
                )
                let availableCloset = closetAvailableForTripDay(
                    closet: activeCloset,
                    plannedWearCounts: plannedWearCounts,
                    lastPlannedDayByItemID: lastPlannedDayByItemID,
                    dayIndex: dayIndex,
                    trip: trip
                )
                let availablePackingCloset = availableCloset.filter { preferredPackingIDs.contains($0.id) }
                let primaryCloset = availablePackingCloset.isEmpty ? availableCloset : availablePackingCloset
                let fallbackCloset = availablePackingCloset.isEmpty ? availableCloset : availablePackingCloset

                let localRecommendations = engine.recommend(
                    closet: primaryCloset,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    limit: 3
                )
                let fallbackRecommendations = engine.recommend(
                    closet: fallbackCloset,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    limit: 3
                )
                let fullClosetRecommendations = engine.recommend(
                    closet: availableCloset,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    limit: 3
                )

                guard var recommendation = localRecommendations.first ?? fallbackRecommendations.first ?? fullClosetRecommendations.first else {
                    continue
                }
                guard engine.isCompleteOutfit(recommendation.items, request: request) else {
                    continue
                }

                if let aiOptions,
                    let aiRecommendation = await aiFilteredRecommendation(
                    localRecommendation: recommendation,
                    closet: primaryCloset.isEmpty ? availableCloset : primaryCloset,
                    feedback: feedback,
                    stylePreference: stylePreference,
                    request: request,
                    aiOptions: aiOptions,
                    engine: engine
                   ) {
                    recommendation = aiRecommendation
                }

                recordPlannedWears(
                    for: recommendation.items,
                    dayIndex: dayIndex,
                    counts: &plannedWearCounts,
                    lastPlannedDayByItemID: &lastPlannedDayByItemID
                )

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
        let itineraryItems = trip.itineraryOutfits
            .flatMap { $0.outfit?.items.compactMap(\.item) ?? [] }
            .filter { $0.status == .active }
        chosen.append(contentsOf: itineraryItems)
        if !itineraryItems.isEmpty {
            var seen = Set<UUID>()
            return chosen.filter { seen.insert($0.id).inserted }
        }

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

        let accessoryCategories = packingAccessoryCategories(for: trip)
        chosen.append(contentsOf: closet
            .filter { accessoryCategories.contains($0.category) }
            .prefix(3))

        var seen = Set<UUID>()
        return chosen.filter { seen.insert($0.id).inserted }
    }

    private func packingAccessoryCategories(for trip: Trip) -> Set<ClothingCategory> {
        let requestedContexts = trip.stops
            .filter(isDailyPlanStop)
            .flatMap(\.requestedContexts)
        if !requestedContexts.isEmpty, requestedContexts.allSatisfy(isExerciseContext) {
            return []
        }

        let text = ([trip.notes] + trip.stops.map(\.customsNotes))
            .joined(separator: " ")
            .lowercased()
        let hasExerciseText = text.containsAny(["gym", "workout", "exercise", "run", "running", "lift", "lifting", "weights", "strength", "training"])
        let hasNonExerciseText = text.containsAny(["work", "office", "business", "conference", "meeting", "dinner", "date", "wedding", "formal", "travel", "casual", "sightseeing"])
        if hasExerciseText && !hasNonExerciseText {
            return []
        }

        let needsBeltOrDressAccessory = requestedContexts.contains { [.businessCasual, .businessFormal, .smartCasual, .smartStreetwear, .workDay, .dateNight, .dinner, .wedding].contains($0) } ||
            text.containsAny(["work", "office", "business", "conference", "meeting", "dinner", "date", "wedding", "formal", "collared", "belt"])

        if needsBeltOrDressAccessory {
            return [.belt, .watch, .jewelry, .accessory, .bag, .purse]
        }

        return [.watch, .accessory, .bag, .purse]
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
            guard engine.isCompleteOutfit(items, request: request) else { return nil }
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
        if !isLaundryTrackedCategory(item.category) {
            return "Reusable item; no laundry limit"
        }

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

    private func addBaseLayerPackingItems(
        category: ClothingCategory,
        needed: Int,
        purpose: BaseLayerPurpose,
        trip: Trip,
        closet: [ClothingItem],
        list: PackingList,
        context: ModelContext,
        packedQuantities: inout [UUID: Int]
    ) {
        var remaining = max(0, needed)
        guard remaining > 0 else { return }

        let candidates = baseLayerCandidates(category: category, purpose: purpose, trip: trip, closet: closet)

        for item in candidates where remaining > 0 {
            let alreadyPacked = packedQuantities[item.id, default: 0]
            let availableQuantity = max(0, max(1, item.quantity) - alreadyPacked)
            guard availableQuantity > 0 else { continue }

            let quantity = min(availableQuantity, remaining)
            let reason = "\(purpose.displayName(for: category)): target \(needed); this item has \(max(1, item.quantity)) available"
            upsertPackingItem(quantity: quantity, reason: reason, item: item, list: list, context: context)
            packedQuantities[item.id, default: 0] += quantity
            remaining -= quantity
        }

        if remaining > 0 {
            upsertPackingItem(
                quantity: remaining,
                reason: "Add \(purpose.reasonLabel(for: category))",
                item: nil,
                list: list,
                context: context
            )
        }
    }

    private func upsertPackingItem(
        quantity: Int,
        reason: String,
        item: ClothingItem?,
        list: PackingList,
        context: ModelContext
    ) {
        if let item,
           let existing = list.items.first(where: { $0.item?.id == item.id }) {
            existing.quantity = max(existing.quantity, quantity)
            existing.reason = mergedReason(existing.reason, reason)
            return
        }

        if item == nil,
           let existing = list.items.first(where: { $0.item == nil && $0.reason == reason }) {
            existing.quantity += quantity
            return
        }

        let packingItem = PackingListItem(quantity: max(1, quantity), reason: reason, item: item, packingList: list)
        context.insert(packingItem)
        list.items.append(packingItem)
    }

    private func mergedReason(_ first: String, _ second: String) -> String {
        let parts = [first, second]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return parts
            .filter { seen.insert($0).inserted }
            .joined(separator: " + ")
    }

    private func baseLayerCandidates(
        category: ClothingCategory,
        purpose: BaseLayerPurpose,
        trip: Trip,
        closet: [ClothingItem]
    ) -> [ClothingItem] {
        let categoryItems = closet.filter { baseLayerCategoryMatches($0, category: category) }
        guard !categoryItems.isEmpty else { return [] }

        let dailyItems = categoryItems.filter { !isExerciseBaseLayerItem($0) }
        let exerciseItems = categoryItems.filter { isExerciseBaseLayerItem($0) }
        let preferredItems: [ClothingItem]

        switch purpose {
        case .daily:
            preferredItems = dailyItems.isEmpty ? exerciseItems : dailyItems
        case .exercise:
            preferredItems = exerciseItems.isEmpty ? dailyItems : exerciseItems
        }

        return preferredItems.sorted {
            baseLayerSortScore($0, purpose: purpose, trip: trip) > baseLayerSortScore($1, purpose: purpose, trip: trip)
        }
    }

    private func baseLayerCategoryMatches(_ item: ClothingItem, category: ClothingCategory) -> Bool {
        if item.category == category {
            return true
        }

        let text = itemSearchText(item)
        if category == .underwear,
           [.activewear, .shorts].contains(item.category),
           text.contains("compression"),
           text.containsAny(["short", "brief", "underwear", "base layer", "baselayer", "liner"]) {
            return true
        }

        if category == .socks,
           item.category == .activewear,
           text.containsAny(["sock", "socks"]) {
            return true
        }

        return false
    }

    private func baseLayerSortScore(_ item: ClothingItem, purpose: BaseLayerPurpose, trip: Trip) -> Double {
        let text = itemSearchText(item)
        var score = 100.0 - Double(item.wearCount)

        switch purpose {
        case .daily:
            score += isExerciseBaseLayerItem(item) ? -25 : 25
        case .exercise:
            score += isExerciseBaseLayerItem(item) ? 50 : -20
            let focuses = exerciseFocuses(for: trip)
            if focuses.contains("running"), text.containsAny(["running", "runner", "run"]) {
                score += 40
            }
            if focuses.contains("lifting"), text.containsAny(["lifting", "lift", "weight", "strength", "training"]) {
                score += 40
            }
            if item.category == .socks, text.containsAny(["boot", "dress", "office", "work"]) {
                score -= 50
            }
        }

        return score
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
        let dailyPlanEntries = trip.stops.filter(isDailyPlanStop)
        let requestedContexts = dailyPlanEntries
            .flatMap(\.requestedContexts)
        if !dailyPlanEntries.isEmpty {
            return requestedContexts.contains(where: isExerciseContext)
        }

        let text = ([trip.notes] + trip.stops.flatMap { [$0.customsNotes, $0.location] })
            .joined(separator: " ")
            .lowercased()
        return text.containsAny(["gym", "workout", "exercise", "run", "running", "lift", "lifting", "weights", "strength", "training", "hike", "hiking"])
    }

    private func tripUsesExplicitContexts(_ trip: Trip) -> Bool {
        trip.stops.contains(where: isDailyPlanStop)
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
            return Int.max
        }
    }

    private func shouldResetLaundryCounts(for trip: Trip, dayIndex: Int) -> Bool {
        trip.laundryIntervalDays > 0 && dayIndex > 0 && dayIndex % trip.laundryIntervalDays == 0
    }

    private func closetAvailableForTripDay(
        closet: [ClothingItem],
        plannedWearCounts: [UUID: Int],
        lastPlannedDayByItemID: [UUID: Int],
        dayIndex: Int,
        trip: Trip
    ) -> [ClothingItem] {
        return closet.filter { item in
            guard !isLaundryTracked(item) || lastPlannedDayByItemID[item.id] != dayIndex - 1 else { return false }
            guard isLaundryTracked(item) else { return true }
            return plannedWearCounts[item.id, default: 0] < wearLimit(for: item.category, trip: trip)
        }
    }

    private func recordPlannedWears(
        for items: [ClothingItem],
        dayIndex: Int,
        counts: inout [UUID: Int],
        lastPlannedDayByItemID: inout [UUID: Int]
    ) {
        for item in items {
            lastPlannedDayByItemID[item.id] = dayIndex
            guard isLaundryTracked(item) else { continue }
            counts[item.id, default: 0] += 1
        }
    }

    private func isLaundryTracked(_ item: ClothingItem) -> Bool {
        isLaundryTrackedCategory(item.category)
    }

    private func isLaundryTrackedCategory(_ category: ClothingCategory) -> Bool {
        switch category {
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
            let key = normalizedLocationKey(location)
            guard !location.isEmpty, seen.insert(key).inserted else { return nil }
            return location
        }
    }

    private func locationStops(for stops: [TripStop]) -> [TripStop] {
        let broadStops = stops.filter { !isDailyPlanStop($0) }
        return broadStops.isEmpty ? stops : broadStops
    }

    private func normalizedLocationKey(_ location: String) -> String {
        location
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .split(separator: " ")
            .joined(separator: " ")
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

    private func itineraryContexts(
        for stops: [TripStop],
        trip: Trip,
        isTravelDay: Bool,
        explicitDailyPlanning: Bool
    ) -> [OutfitContextOption] {
        let requestedContexts = stops
            .filter(isDailyPlanStop)
            .flatMap(\.requestedContexts)
        if explicitDailyPlanning {
            return requestedContexts
        }
        if !requestedContexts.isEmpty {
            return requestedContexts
        }

        let text = stops.map(\.customsNotes)
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
        if text.containsAny(["run", "running"]) {
            contexts.append(.runningDay)
        } else if text.containsAny(["lift", "lifting", "weights", "strength"]) {
            contexts.append(.liftingDay)
        } else if text.containsAny(["gym", "workout", "exercise", "training"]) {
            contexts.append(.gym)
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
        let explicitExerciseDays = Set(
            trip.stops
                .filter { isDailyPlanStop($0) && $0.requestedContexts.contains(where: isExerciseContext) }
                .flatMap { stop in
                    dates(from: stop.startsAt, through: stop.endsAt).map { date in
                        Calendar.current.startOfDay(for: date)
                    }
                }
        ).count
        if explicitExerciseDays > 0 {
            return min(days, explicitExerciseDays)
        }

        let text = ([trip.notes] + trip.stops.map(\.customsNotes))
            .joined(separator: " ")
            .lowercased()
        let numbers = text
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .filter { (1...max(1, days)).contains($0) }

        return min(days, numbers.first ?? 1)
    }

    private func exerciseContext(for stops: [TripStop], trip: Trip) -> OutfitContextOption {
        let text = ([trip.notes] + stops.map(\.customsNotes))
            .joined(separator: " ")
            .lowercased()
        if text.containsAny(["run", "running"]) {
            return .runningDay
        }
        if text.containsAny(["lift", "lifting", "weights", "strength"]) {
            return .liftingDay
        }
        return .gym
    }

    private func isExerciseContext(_ context: OutfitContextOption) -> Bool {
        switch context {
        case .gym, .runningDay, .liftingDay:
            return true
        case .businessCasual, .businessFormal, .smartCasual, .smartStreetwear, .casualDay, .everydayCasual, .streetCasual, .floridaCasual, .dateNight, .workDay, .travelDay, .dinner, .athleisure, .walkingAroundCity, .outdoors, .errands, .wedding:
            return false
        }
    }

    private func exerciseFocuses(for trip: Trip) -> Set<String> {
        var focuses = Set<String>()
        for context in trip.stops.filter(isDailyPlanStop).flatMap(\.requestedContexts) {
            if context == .runningDay { focuses.insert("running") }
            if context == .liftingDay { focuses.insert("lifting") }
        }

        let text = ([trip.notes] + trip.stops.map(\.customsNotes))
            .joined(separator: " ")
            .lowercased()
        if text.containsAny(["run", "running"]) {
            focuses.insert("running")
        }
        if text.containsAny(["lift", "lifting", "weights", "strength"]) {
            focuses.insert("lifting")
        }
        if focuses.isEmpty, tripHasExercise(trip) {
            focuses.insert("gym")
        }
        return focuses
    }

    private func isExerciseBaseLayerItem(_ item: ClothingItem) -> Bool {
        let explicitText = [
            item.name,
            item.brand,
            item.notes
        ]
        .joined(separator: " ")
        .lowercased()

        guard item.category == .underwear ||
            item.category == .socks ||
            baseLayerCategoryMatches(item, category: .underwear) ||
            baseLayerCategoryMatches(item, category: .socks)
        else {
            return false
        }

        return explicitText.containsAny([
            "compression",
            "running",
            "runner",
            "run",
            "lifting",
            "lift",
            "gym",
            "workout",
            "training",
            "athletic",
            "performance",
            "sport"
        ])
    }

    private func isDailyPlanStop(_ stop: TripStop) -> Bool {
        if stop.isDailyPlanEntry {
            return true
        }

        let startsAt = Calendar.current.startOfDay(for: stop.startsAt)
        let endsAt = Calendar.current.startOfDay(for: stop.endsAt)
        return startsAt == endsAt && !stop.requestedContexts.isEmpty
    }

    private func itemSearchText(_ item: ClothingItem) -> String {
        [
            item.name,
            item.brand,
            item.notes,
            item.activitySuitability,
            item.occasionSuitability
        ]
        .joined(separator: " ")
        .lowercased()
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

private enum BaseLayerPurpose {
    case daily
    case exercise

    func displayName(for category: ClothingCategory) -> String {
        switch (self, category) {
        case (.daily, .underwear):
            return "Daily underwear"
        case (.daily, .socks):
            return "Daily socks"
        case (.exercise, .underwear):
            return "Exercise underwear"
        case (.exercise, .socks):
            return "Exercise socks"
        default:
            return category.displayName
        }
    }

    func reasonLabel(for category: ClothingCategory) -> String {
        switch (self, category) {
        case (.daily, .underwear):
            return "daily underwear"
        case (.daily, .socks):
            return "daily socks"
        case (.exercise, .underwear):
            return "exercise underwear"
        case (.exercise, .socks):
            return "exercise socks"
        default:
            return category.displayName.lowercased()
        }
    }
}

private extension String {
    func containsAny(_ values: [String]) -> Bool {
        values.contains { contains($0) }
    }
}
