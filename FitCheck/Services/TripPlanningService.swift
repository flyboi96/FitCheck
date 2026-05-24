import Foundation
import SwiftData

struct TripPlanningService {
    func rebuildPackingList(for trip: Trip, closet: [ClothingItem], context: ModelContext) {
        for list in trip.packingLists {
            context.delete(list)
        }

        let activeItems = closet.filter { $0.status == .active }
        let list = PackingList(title: "\(trip.title) Packing List", trip: trip)
        context.insert(list)
        trip.packingLists.append(list)

        let days = max(1, Calendar.current.dateComponents([.day], from: trip.startsAt, to: trip.endsAt).day ?? 1)
        let chosen = packingCandidates(from: activeItems, trip: trip, days: days)

        for item in chosen {
            let quantity = quantity(for: item, tripDays: days)
            let reason = packingReason(for: item, trip: trip)
            let packingItem = PackingListItem(quantity: quantity, reason: reason, item: item, packingList: list)
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
    ) {
        for itineraryOutfit in trip.itineraryOutfits {
            if let outfit = itineraryOutfit.outfit {
                context.delete(outfit)
            }
            context.delete(itineraryOutfit)
        }

        let engine = OutfitRecommendationEngine()
        let stops = trip.stops.sorted { $0.startsAt < $1.startsAt }

        for stop in stops {
            for date in dates(from: stop.startsAt, through: stop.endsAt) {
                let request = RecommendationRequest(
                    weather: WeatherInput(
                        temperatureF: inferredTemperature(from: stop.expectedWeather),
                        isRaining: stop.expectedWeather.localizedCaseInsensitiveContains("rain"),
                        windMph: stop.expectedWeather.localizedCaseInsensitiveContains("wind") ? 18 : 5,
                        location: stop.location
                    ),
                    occasion: "travel",
                    activity: stop.customsNotes.isEmpty ? "walking around city" : stop.customsNotes,
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
                    name: "\(stop.location) Outfit",
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

                let itinerary = DailyItineraryOutfit(date: date, location: stop.location, activity: request.activity, trip: trip, outfit: outfit)
                context.insert(itinerary)
                trip.itineraryOutfits.append(itinerary)
            }
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
                .filter { $0.category == .jacket || $0.weatherSuitability.fitcheckContainsTag("rain") || $0.weatherSuitability.fitcheckContainsTag("cold") }
                .prefix(2))
        }

        chosen.append(contentsOf: closet
            .filter { [.belt, .watch, .accessory, .bag].contains($0.category) }
            .prefix(3))

        var seen = Set<UUID>()
        return chosen.filter { seen.insert($0.id).inserted }
    }

    private func quantity(for item: ClothingItem, tripDays: Int) -> Int {
        switch item.category {
        case .shirt:
            min(max(2, tripDays / 2 + 1), 6)
        case .pants, .shorts:
            min(max(1, tripDays / 4 + 1), 3)
        default:
            1
        }
    }

    private func packingReason(for item: ClothingItem, trip: Trip) -> String {
        let weatherText = trip.stops.map(\.expectedWeather).joined(separator: " ")
        if !weatherText.isEmpty, item.weatherSuitability.fitcheckTags.contains(where: { weatherText.localizedCaseInsensitiveContains($0) }) {
            return "Weather match"
        }
        return item.category.displayName
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
}
