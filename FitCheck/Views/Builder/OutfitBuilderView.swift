import SwiftData
import SwiftUI

struct OutfitBuilderView: View {
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var stylePreferences: [StylePreference]

    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name
    @AppStorage("fitcheckWeatherFallbackLatitude") private var fallbackLatitude = WeatherLookupFallback.default.latitude
    @AppStorage("fitcheckWeatherFallbackLongitude") private var fallbackLongitude = WeatherLookupFallback.default.longitude

    @StateObject private var weatherLookup = WeatherLookupController()
    @State private var selectedItemID: UUID?
    @State private var occasion = "casual"
    @State private var activity = "walking around city"
    @State private var recommendations: [OutfitRecommendation] = []

    private let engine = OutfitRecommendationEngine()

    var body: some View {
        List {
            Section("Anchor Item") {
                Picker("Item", selection: $selectedItemID) {
                    Text("Choose Item").tag(nil as UUID?)
                    ForEach(activeItems) { item in
                        Text("\(item.name) - \(item.category.displayName)").tag(Optional(item.id))
                    }
                }
            }

            Section("Weather") {
                weatherStatus
                Button {
                    refreshWeather()
                } label: {
                    Label("Refresh Weather", systemImage: "location")
                }
                .disabled(weatherLookup.isLoading)
            }

            Section("Context") {
                TextField("Occasion", text: $occasion)
                    .textInputAutocapitalization(.words)
                TextField("Activity", text: $activity)
                    .textInputAutocapitalization(.sentences)
                Button {
                    generate()
                } label: {
                    Label("Build Outfit", systemImage: "wand.and.stars")
                }
                .disabled(selectedItem == nil || weatherLookup.result == nil)
            }

            if !recommendations.isEmpty {
                Section("Outfits") {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
            }
        }
        .navigationTitle("Builder")
        .task {
            if weatherLookup.result == nil {
                refreshWeather()
            }
        }
    }

    private var activeItems: [ClothingItem] {
        closetItems.filter { $0.status == .active }
    }

    private var selectedItem: ClothingItem? {
        guard let selectedItemID else { return nil }
        return activeItems.first { $0.id == selectedItemID }
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
                Text("\(result.input.location) · Wind \(Int(result.input.windMph.rounded())) mph")
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

    private func generate() {
        guard let selectedItem, let weather = weatherLookup.result?.input else { return }
        recommendations = engine.recommend(
            closet: closetItems,
            feedback: feedback,
            stylePreference: stylePreferences.first,
            request: RecommendationRequest(
                weather: weather,
                occasion: occasion,
                activity: activity,
                selectedItem: selectedItem
            )
        )
    }
}
