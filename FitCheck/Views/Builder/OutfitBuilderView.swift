import SwiftData
import SwiftUI

struct OutfitBuilderView: View {
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var stylePreferences: [StylePreference]

    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name
    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @StateObject private var weatherLookup = WeatherLookupController()
    @State private var manualLocationQuery = ""
    @State private var selectedItemID: UUID?
    @State private var itemSearchText = ""
    @State private var selectedCategoryRawValue = "all"
    @State private var selectedContext = OutfitContextOption.casualDay.rawValue
    @State private var recommendations: [OutfitRecommendation] = []
    @State private var aiReviews: [String: AIOutfitResponse] = [:]
    @State private var aiReviewErrors: [String: String] = [:]
    @State private var reviewingCombinationKeys = Set<String>()

    private let engine = OutfitRecommendationEngine()

    var body: some View {
        List {
            Section("Anchor Item") {
                if let selectedItem {
                    HStack {
                        Label(selectedItem.name, systemImage: iconName(for: selectedItem.category))
                        Spacer()
                        Text(selectedItem.category.displayName)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Choose one closet item to build around", systemImage: "tshirt")
                        .foregroundStyle(.secondary)
                }

                TextField("Search closet", text: $itemSearchText)
                    .textInputAutocapitalization(.words)

                Picker("Category", selection: $selectedCategoryRawValue) {
                    Text("All Categories").tag("all")
                    ForEach(availableCategories) { category in
                        Text(category.displayName).tag(category.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            if filteredItemGroups.isEmpty {
                Section("Items") {
                    ContentUnavailableView("No Matching Items", systemImage: "magnifyingglass")
                }
            } else {
                ForEach(filteredItemGroups) { group in
                    Section(group.category.displayName) {
                        ForEach(group.items) { item in
                            Button {
                                selectedItemID = item.id
                            } label: {
                                HStack {
                                    Image(systemName: iconName(for: item.category))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.body.weight(item.id == selectedItemID ? .semibold : .regular))
                                        Text(itemDetail(for: item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if item.id == selectedItemID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
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
                Picker("Context", selection: $selectedContext) {
                    ForEach(OutfitContextOption.allCases) { option in
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
                        RecommendationCard(
                            recommendation: recommendation,
                            aiReview: aiReviews[recommendation.combinationKey],
                            aiReviewError: aiReviewErrors[recommendation.combinationKey],
                            isAIReviewing: reviewingCombinationKeys.contains(recommendation.combinationKey),
                            onAIReview: aiReviewAction(for: recommendation)
                        )
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
        closetItems
            .filter { $0.status == .active }
            .sorted {
                if $0.category == $1.category {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return categorySortIndex($0.category) < categorySortIndex($1.category)
            }
    }

    private var selectedItem: ClothingItem? {
        guard let selectedItemID else { return nil }
        return activeItems.first { $0.id == selectedItemID }
    }

    private var availableCategories: [ClothingCategory] {
        let categories = Set(activeItems.map(\.category))
        return ClothingCategory.allCases.filter { categories.contains($0) }
    }

    private var filteredItemGroups: [ItemCategoryGroup] {
        let search = itemSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = activeItems.filter { item in
            let matchesCategory = selectedCategoryRawValue == "all" || item.category.rawValue == selectedCategoryRawValue
            let matchesSearch = search.isEmpty || item.name.localizedCaseInsensitiveContains(search)
            return matchesCategory && matchesSearch
        }

        return availableCategories.compactMap { category in
            let items = filtered.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            return ItemCategoryGroup(category: category, items: items)
        }
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
        aiReviews = [:]
        aiReviewErrors = [:]
        recommendations = engine.recommend(
            closet: closetItems,
            feedback: feedback,
            stylePreference: stylePreferences.first,
            request: RecommendationRequest(
                weather: weather,
                occasion: currentContext.occasion,
                activity: currentContext.activity,
                selectedItem: selectedItem
            )
        )
    }

    private func aiReviewAction(for recommendation: OutfitRecommendation) -> (() -> Void)? {
        guard useAIProxy, configuredAIProxyURL != nil else { return nil }
        return {
            Task {
                await reviewWithAI(recommendation)
            }
        }
    }

    private var configuredAIProxyURL: URL? {
        let trimmed = aiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    @MainActor
    private func reviewWithAI(_ recommendation: OutfitRecommendation) async {
        guard let baseURL = configuredAIProxyURL else { return }

        let key = recommendation.combinationKey
        reviewingCombinationKeys.insert(key)
        aiReviewErrors[key] = nil
        defer {
            reviewingCombinationKeys.remove(key)
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)

        do {
            let response = try await client.suggestOutfit(request: aiRequest(for: recommendation))
            aiReviews[key] = response
        } catch {
            aiReviewErrors[key] = error.localizedDescription
        }
    }

    private func aiRequest(for recommendation: OutfitRecommendation) -> AIOutfitRequest {
        AIOutfitRequest(
            closet: closetItems.map(AIClothingItemPayload.init),
            weatherSummary: weatherLookup.result?.input.summary ?? "",
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            styleDescription: styleDescription,
            selectedItemID: selectedItem?.id,
            candidateItemIDs: recommendation.items.map(\.id),
            localScore: recommendation.score,
            localNotes: recommendation.notes,
            recentFeedback: feedback.prefix(12).map(feedbackSummary)
        )
    }

    private var styleDescription: String {
        let wearerLine = currentWearerProfile == .unspecified ? nil : "Wearer profile: \(currentWearerProfile.displayName)"
        guard let stylePreference = stylePreferences.first else { return wearerLine ?? "" }
        return [
            wearerLine,
            stylePreference.styleDescription,
            stylePreference.favoriteLooks,
            stylePreference.preferredColors,
            stylePreference.preferredFit,
            stylePreference.rules,
            stylePreference.dislikedCombinations.isEmpty ? nil : "Avoid: \(stylePreference.dislikedCombinations)"
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func feedbackSummary(_ entry: Feedback) -> String {
        [
            entry.type.displayName,
            entry.note,
            entry.item?.name
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
    }

    private var currentContext: OutfitContextOption {
        OutfitContextOption(rawValue: selectedContext) ?? .casualDay
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }

    private func itemDetail(for item: ClothingItem) -> String {
        let parts = [
            ClothingInference.color(for: item),
            ClothingInference.pattern(for: item)
        ]
        .filter { !$0.isEmpty }

        return parts.isEmpty ? item.category.displayName : parts.joined(separator: " · ")
    }

    private func iconName(for category: ClothingCategory) -> String {
        switch category {
        case .shirt, .sweater:
            "tshirt"
        case .activewear:
            "figure.run"
        case .underwear:
            "person"
        case .socks:
            "shoeprints.fill"
        case .pants, .shorts:
            "figure.stand"
        case .shoes:
            "shoeprints.fill"
        case .jacket:
            "cloud"
        case .belt, .watch, .accessory:
            "sparkles"
        case .bag:
            "bag"
        case .other:
            "circle"
        }
    }

    private func categorySortIndex(_ category: ClothingCategory) -> Int {
        ClothingCategory.allCases.firstIndex(of: category) ?? ClothingCategory.allCases.count
    }
}

private struct ItemCategoryGroup: Identifiable {
    var category: ClothingCategory
    var items: [ClothingItem]

    var id: String { category.rawValue }
}
