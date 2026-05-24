import SwiftData
import SwiftUI

struct OutfitBuilderView: View {
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var stylePreferences: [StylePreference]

    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name

    @StateObject private var weatherLookup = WeatherLookupController()
    @State private var manualLocationQuery = ""
    @State private var selectedItemID: UUID?
    @State private var occasion = OccasionOption.casual.rawValue
    @State private var activity = ActivityOption.walkingAroundCity.rawValue
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
                Picker("Occasion", selection: $occasion) {
                    ForEach(OccasionOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                Picker("Activity", selection: $activity) {
                    ForEach(ActivityOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
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

    private func refreshWeather() {
        weatherLookup.refresh(defaultLocationName: fallbackName)
    }

    private func lookupManualWeather() {
        weatherLookup.refresh(searchText: manualLocationQuery)
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
