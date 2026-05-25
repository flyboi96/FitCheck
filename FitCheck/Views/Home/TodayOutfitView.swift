import SwiftData
import SwiftUI

struct TodayOutfitView: View {
    @Environment(\.modelContext) private var modelContext
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
    @State private var selectedContext = OutfitContextOption.casualDay.rawValue
    @State private var recommendations: [OutfitRecommendation] = []
    @State private var aiReviews: [String: AIOutfitResponse] = [:]
    @State private var aiReviewErrors: [String: String] = [:]
    @State private var reviewingCombinationKeys = Set<String>()
    @State private var lastAction: TodayUndoAction?

    private let engine = OutfitRecommendationEngine()
    private let historyService = FitCheckHistoryService()

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
                Picker("Context", selection: $selectedContext) {
                    ForEach(OutfitContextOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                Button {
                    generate()
                } label: {
                    Label("Generate Outfit", systemImage: "wand.and.stars")
                }
                .disabled(!hasEnoughItemsForOutfit || weatherLookup.result == nil)
            }

            if !hasEnoughItemsForOutfit {
                ContentUnavailableView("Add Closet Items", systemImage: "tshirt", description: Text("FitCheck needs a top or dress, shoes, and either a bottom or dress before it can score outfits."))
            }

            if !recommendations.isEmpty {
                if let lastAction {
                    Section("Last Action") {
                        HStack {
                            Text(lastAction.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if lastAction.canUndo {
                                Button("Undo") {
                                    undoLastAction()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(
                            recommendation: recommendation,
                            primaryTitle: "Log Wear",
                            onPrimary: { logWear(recommendation, feedbackType: nil) },
                            onGood: { logWear(recommendation, feedbackType: .goodOutfit) },
                            onBad: { recordNegativeFeedback(for: recommendation, type: .badOutfit) },
                            aiReview: aiReviews[recommendation.combinationKey],
                            aiReviewError: aiReviewErrors[recommendation.combinationKey],
                            isAIReviewing: reviewingCombinationKeys.contains(recommendation.combinationKey),
                            onAIReview: aiReviewAction(for: recommendation)
                        )
                    }
                } header: {
                    Text("Recommendations")
                } footer: {
                    Text("Log Wear records that you wore it. Wore + Liked records the wear and boosts similar outfits. Reject saves negative feedback without logging a wear.")
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

    private var hasEnoughItemsForOutfit: Bool {
        let categories = Set(activeItems.map(\.category))
        let hasTop = categories.contains(.shirt) || categories.contains(.blouse) || categories.contains(.sweater)
        let hasDress = categories.contains(.dress)
        let hasBottom = categories.contains(.pants) || categories.contains(.shorts) || categories.contains(.skirt)
        let hasShoes = categories.contains(.shoes) || categories.contains(.heels) || categories.contains(.flats)
        return hasShoes && (hasDress || (hasTop && hasBottom))
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

    private func refreshWeather() {
        weatherLookup.refresh(defaultLocationName: fallbackName)
    }

    private func lookupManualWeather() {
        weatherLookup.refresh(searchText: manualLocationQuery)
    }

    private func generate() {
        guard weatherLookup.result != nil else { return }
        aiReviews = [:]
        aiReviewErrors = [:]
        recommendations = engine.recommend(
            closet: closetItems,
            feedback: feedback,
            stylePreference: stylePreferences.first,
            request: RecommendationRequest(
                weather: currentWeather,
                occasion: currentContext.occasion,
                activity: currentContext.activity,
                selectedItem: nil
            )
        )
    }

    private func logWear(_ recommendation: OutfitRecommendation, feedbackType: FeedbackType?) {
        let outfit = Outfit(
            name: recommendation.title,
            wornAt: Date(),
            occasion: currentContext.occasion,
            activity: currentContext.activity,
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
        lastAction = .loggedOutfit(outfit.id, feedbackType == .goodOutfit ? "Logged wear and positive feedback." : "Logged wear.")
        generate()
    }

    private func recordNegativeFeedback(for recommendation: OutfitRecommendation, type: FeedbackType) {
        let entry = Feedback(type: type, combinationKey: recommendation.combinationKey)
        modelContext.insert(entry)
        try? modelContext.save()
        lastAction = .feedback(entry.id, "Saved rejection feedback.")
        generate()
    }

    private func undoLastAction() {
        guard let lastAction else { return }

        do {
            switch lastAction {
            case .loggedOutfit(let outfitID, _):
                if let outfit = try modelContext.fetch(FetchDescriptor<Outfit>()).first(where: { $0.id == outfitID }) {
                    try historyService.deleteOutfit(outfit, context: modelContext)
                }
            case .feedback(let feedbackID, _):
                if let entry = try modelContext.fetch(FetchDescriptor<Feedback>()).first(where: { $0.id == feedbackID }) {
                    try historyService.deleteFeedback(entry, context: modelContext)
                }
            case .message:
                break
            }
            self.lastAction = nil
            generate()
        } catch {
            self.lastAction = .message("Undo failed: \(error.localizedDescription)")
        }
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
            let response = try await client.suggestOutfit(request: aiRequest(for: recommendation, selectedItemID: nil))
            aiReviews[key] = response
        } catch {
            aiReviewErrors[key] = error.localizedDescription
        }
    }

    private func aiRequest(for recommendation: OutfitRecommendation, selectedItemID: UUID?) -> AIOutfitRequest {
        AIOutfitRequest(
            closet: closetItems.map(AIClothingItemPayload.init),
            weatherSummary: currentWeather.summary,
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            styleDescription: styleDescription,
            selectedItemID: selectedItemID,
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
}

private enum TodayUndoAction {
    case loggedOutfit(UUID, String)
    case feedback(UUID, String)
    case message(String)

    var message: String {
        switch self {
        case .loggedOutfit(_, let message), .feedback(_, let message), .message(let message):
            message
        }
    }

    var canUndo: Bool {
        switch self {
        case .loggedOutfit, .feedback:
            true
        case .message:
            false
        }
    }
}

private extension WeatherLookupFallback {
    static var defaultWeather: WeatherInput {
        WeatherInput(temperatureF: 72, isRaining: false, windMph: 6, location: Self.default.name)
    }
}
