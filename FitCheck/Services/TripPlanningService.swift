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
            let reason = packingReason(for: item, trip: trip)
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

        for date in stopsByDay.keys.sorted() {
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

            guard let recommendation = engine.recommend(
                closet: closet,
                feedback: feedback,
                stylePreference: stylePreference,
                request: request,
                limit: 1
            ).first else {
                continue
            }

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
        let requiredCategories: [ClothingCategory] = [.shirt, .pants, .shorts, .shoes]
        var chosen: [ClothingItem] = []

        for category in requiredCategories {
            let limit = category == .shoes ? min(2, max(1, days / 4 + 1)) : min(max(2, days / 2 + 1), 5)
            chosen.append(contentsOf: closet
                .filter { $0.category == category }
                .sorted { $0.wearCount < $1.wearCount }
                .prefix(limit))
        }

        let weatherText = trip.stops.map(\.expectedWeather).joined(separator: " ").lowercased()
        if weatherText.contains("rain") || weatherText.contains("cold") {
            chosen.append(contentsOf: closet
                .filter {
                    $0.category == .jacket ||
                    ClothingInference.weatherTags(for: $0).contains("rain") ||
                    ClothingInference.weatherTags(for: $0).contains("cold")
                }
                .prefix(2))
        }

        chosen.append(contentsOf: closet
            .filter { [.belt, .watch, .accessory, .bag].contains($0.category) }
            .prefix(3))

        var seen = Set<UUID>()
        return chosen.filter { seen.insert($0.id).inserted }
    }

    private func packingReason(for item: ClothingItem, trip: Trip) -> String {
        let weatherText = trip.stops.map(\.expectedWeather).joined(separator: " ")
        if !weatherText.isEmpty, ClothingInference.weatherTags(for: item).contains(where: { weatherText.localizedCaseInsensitiveContains($0) }) {
            return "Weather match"
        }
        return item.category.displayName
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
