import SwiftData
import SwiftUI

struct TodayOutfitView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var stylePreferences: [StylePreference]

    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name
    @AppStorage("fitcheckWeatherFallbackLatitude") private var fallbackLatitude = WeatherLookupFallback.default.latitude
    @AppStorage("fitcheckWeatherFallbackLongitude") private var fallbackLongitude = WeatherLookupFallback.default.longitude

    @StateObject private var weatherLookup = WeatherLookupController()
    @State private var manualLocationQuery = ""
    @State private var occasion = "casual"
    @State private var activity = "walking around city"
    @State private var recommendations: [OutfitRecommendation] = []

    private let engine = OutfitRecommendationEngine()

    var body: some View {
        List {
            Section("Weather") {
                weatherStatus
                TextField("City or place", text: $manualLocationQuery)
                    .textInputAutocapitalization(.words)
                Button {
                    refreshWeather()
                } label: {
                    Label("Use Current Location", systemImage: "location")
                }
                .disabled(weatherLookup.isLoading)

                Button {
                    lookupManualWeather()
                } label: {
                    Label("Look Up Location", systemImage: "magnifyingglass")
                }
                .disabled(weatherLookup.isLoading || manualLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Context") {
                TextField("Occasion", text: $occasion)
                    .textInputAutocapitalization(.words)
                TextField("Activity", text: $activity)
                    .textInputAutocapitalization(.sentences)
                Button {
                    generate()
                } label: {
                    Label("Generate Outfit", systemImage: "wand.and.stars")
                }
                .disabled(activeItems.count < 3 || weatherLookup.result == nil)
            }

            if activeItems.count < 3 {
                ContentUnavailableView("Add Closet Items", systemImage: "tshirt", description: Text("A shirt, bottom, and shoes are needed before FitCheck can score outfits."))
            }

            if !recommendations.isEmpty {
                Section("Recommendations") {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(
                            recommendation: recommendation,
                            primaryTitle: "Wear",
                            onPrimary: { logWear(recommendation, feedbackType: nil) },
                            onGood: { logWear(recommendation, feedbackType: .goodOutfit) },
                            onBad: { recordNegativeFeedback(for: recommendation, type: .badOutfit) }
                        )
                    }
                }
            }
        }
        .navigationTitle("Today")
        .task {
            if weatherLookup.result == nil {
                refreshWeather()
            }
        }
    }

    private var activeItems: [ClothingItem] {
        closetItems.filter { $0.status == .active }
    }

    private var currentWeather: WeatherInput {
        weatherLookup.result?.input ?? WeatherLookupFallback.defaultWeather
    }

    @ViewBuilder
    private var weatherStatus: some View {
        if weatherLookup.isLoading {
            Label("Looking up weather", systemImage: "cloud.sun")
                .foregroundStyle(.secondary)
        } else if let result = weatherLookup.result {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(result.input.temperatureF.rounded()))F · \(result.condition)")
                    .font(.body.weight(.medium))
                Text("\(result.input.location) · Wind \(Int(result.input.windMph.rounded())) mph · \(result.sourceDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Weather not loaded", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }

        if let message = weatherLookup.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fallback: WeatherLookupFallback {
        WeatherLookupFallback(name: fallbackName, latitude: fallbackLatitude, longitude: fallbackLongitude)
    }

    private func refreshWeather() {
        weatherLookup.refresh(fallback: fallback)
    }

    private func lookupManualWeather() {
        weatherLookup.refresh(searchText: manualLocationQuery)
    }

    private func generate() {
        guard weatherLookup.result != nil else { return }
        recommendations = engine.recommend(
            closet: closetItems,
            feedback: feedback,
            stylePreference: stylePreferences.first,
            request: RecommendationRequest(
                weather: currentWeather,
                occasion: occasion,
                activity: activity,
                selectedItem: nil
            )
        )
    }

    private func logWear(_ recommendation: OutfitRecommendation, feedbackType: FeedbackType?) {
        let outfit = Outfit(
            name: recommendation.title,
            wornAt: Date(),
            occasion: occasion,
            activity: activity,
            weatherSummary: currentWeather.summary,
            score: recommendation.score,
            rating: feedbackType == .goodOutfit ? 1 : 0
        )
        modelContext.insert(outfit)

        for item in recommendation.items {
            let link = OutfitItemLink(slot: item.category.displayName, outfit: outfit, item: item)
            modelContext.insert(link)
            outfit.items.append(link)

            item.wearCount += 1
            item.lastWornAt = Date()
            item.updatedAt = Date()

            let wearLog = WearLog(date: Date(), item: item, outfit: outfit)
            modelContext.insert(wearLog)
        }

        if let feedbackType {
            let entry = Feedback(type: feedbackType, combinationKey: recommendation.combinationKey, outfit: outfit)
            modelContext.insert(entry)
            outfit.feedback.append(entry)
        }

        try? modelContext.save()
        generate()
    }

    private func recordNegativeFeedback(for recommendation: OutfitRecommendation, type: FeedbackType) {
        let entry = Feedback(type: type, combinationKey: recommendation.combinationKey)
        modelContext.insert(entry)
        try? modelContext.save()
        generate()
    }
}

private extension WeatherLookupFallback {
    static var defaultWeather: WeatherInput {
        WeatherInput(temperatureF: 72, isRaining: false, windMph: 6, location: Self.default.name)
    }
}
