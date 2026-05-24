import Foundation
import SwiftData

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
    }

    func rebuildItinerary(
        for trip: Trip,
        closet: [ClothingItem],
        feedback: [Feedback],
        stylePreference: StylePreference?,
        context: ModelContext
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
            let activity = isTravelDay ? ActivityOption.travel.rawValue : activity(for: dayStops)
            let request = RecommendationRequest(
                weather: weather,
                occasion: isTravelDay ? OccasionOption.travelDay.rawValue : OccasionOption.casual.rawValue,
                activity: activity,
                selectedItem: nil
            )
            let availableCloset = closetAvailableForTripDay(
                closet: closet,
                plannedWearCounts: plannedWearCounts,
                wearsBeforeWash: trip.wearsBeforeWash
            )

            guard let recommendation = engine.recommend(
                closet: availableCloset,
                feedback: feedback,
                stylePreference: stylePreference,
                request: request,
                limit: 1
            ).first ?? engine.recommend(
                closet: closet,
                feedback: feedback,
                stylePreference: stylePreference,
                request: request,
                limit: 1
            ).first else {
                continue
            }

            recordPlannedWears(for: recommendation.items, counts: &plannedWearCounts)

            let outfit = Outfit(
                name: "\(locationLabel) Outfit",
                occasion: request.occasion,
                activity: request.activity,
                weatherSummary: request.weather.summary,
                score: recommendation.score
            )
            context.insert(outfit)

            for item in recommendation.items {
                let link = OutfitItemLink(slot: item.category.displayName, outfit: outfit, item: item)
                context.insert(link)
                outfit.items.append(link)
            }

            let itinerary = DailyItineraryOutfit(date: date, location: locationLabel, activity: request.activity, trip: trip, outfit: outfit)
            context.insert(itinerary)
            trip.itineraryOutfits.append(itinerary)
        }
    }

    private func packingCandidates(from closet: [ClothingItem], trip: Trip, days: Int) -> [ClothingItem] {
        var chosen: [ClothingItem] = []
        let topLimit = clothingLimit(for: trip, days: days, minimum: 1, maximum: 6)
        let bottomLimit = clothingLimit(for: trip, days: days, minimum: 1, maximum: 4)
        let shoeLimit = min(2, max(1, days / 5 + 1))

        chosen.append(contentsOf: chooseItems(from: closet, categories: [.shirt, .sweater], limit: topLimit))
        chosen.append(contentsOf: chooseItems(from: closet, categories: [.pants, .shorts], limit: bottomLimit))
        chosen.append(contentsOf: chooseItems(from: closet, categories: [.shoes], limit: shoeLimit))

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
            .filter { [.belt, .watch, .accessory, .bag].contains($0.category) }
            .prefix(3))

        var seen = Set<UUID>()
        return chosen.filter { seen.insert($0.id).inserted }
    }

    private func chooseItems(from closet: [ClothingItem], categories: Set<ClothingCategory>, limit: Int) -> [ClothingItem] {
        closet
            .filter { categories.contains($0.category) }
            .sorted { $0.wearCount < $1.wearCount }
            .prefix(limit)
            .map { $0 }
    }

    private func clothingLimit(for trip: Trip, days: Int, minimum: Int, maximum: Int) -> Int {
        let laundryWindow = laundryWindowDays(for: trip, days: days)
        let wearsBeforeWash = max(1, trip.wearsBeforeWash)
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
        if trip.laundryIntervalDays > 0 || trip.wearsBeforeWash > 1 {
            let window = laundryWindowDays(for: trip, days: days)
            return "Covers \(window) days between laundry; rewear up to \(max(1, trip.wearsBeforeWash))x"
        }
        return item.category.displayName
    }

    private func shouldResetLaundryCounts(for trip: Trip, dayIndex: Int) -> Bool {
        trip.laundryIntervalDays > 0 && dayIndex > 0 && dayIndex % trip.laundryIntervalDays == 0
    }

    private func closetAvailableForTripDay(
        closet: [ClothingItem],
        plannedWearCounts: [UUID: Int],
        wearsBeforeWash: Int
    ) -> [ClothingItem] {
        let allowedWears = max(1, wearsBeforeWash)
        return closet.filter { item in
            guard isLaundryTracked(item) else { return true }
            return plannedWearCounts[item.id, default: 0] < allowedWears
        }
    }

    private func recordPlannedWears(for items: [ClothingItem], counts: inout [UUID: Int]) {
        for item in items where isLaundryTracked(item) {
            counts[item.id, default: 0] += 1
        }
    }

    private func isLaundryTracked(_ item: ClothingItem) -> Bool {
        switch item.category {
        case .shirt, .pants, .shorts, .jacket, .sweater:
            return true
        case .shoes, .belt, .watch, .accessory, .bag, .other:
            return false
        }
    }

    private func refreshStopWeather(for stops: [TripStop]) async {
        for stop in stops where !stop.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            location: locationLabel
        )
    }

    private func weatherResult(for location: String, date: Date) async -> WeatherLookupResult? {
        if let daily = try? await weatherClient.dailyWeather(for: location, date: date) {
            return daily
        }
        return try? await weatherClient.currentWeather(for: location)
    }

    private func weatherSummaryText(for result: WeatherLookupResult) -> String {
        "\(Int(result.input.temperatureF.rounded()))F, \(result.condition), wind \(Int(result.input.windMph.rounded())) mph"
    }

    private func activity(for stops: [TripStop]) -> String {
        stops
            .map(\.customsNotes)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ActivityOption.walkingAroundCity.rawValue
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
}
